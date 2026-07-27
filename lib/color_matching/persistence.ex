defmodule ColorMatching.Persistence do
  @moduledoc """
  Persistence boundary for palettes, palette colors, and printer profiles.
  """

  import Ecto.Query, warn: false

  alias ColorMatching.PaletteStorage
  alias ColorMatching.Persistence.{Palette, PrinterProfile}
  alias ColorMatching.Repo

  @type palette_attrs :: %{
          optional(:name) => String.t(),
          optional(:is_preset) => boolean(),
          optional(:colors) => [map()]
        }

  @spec list_palettes() :: [Palette.t()]
  def list_palettes do
    Palette
    |> order_by([palette], asc: palette.name)
    |> preload(:colors)
    |> Repo.all()
  end

  @spec get_palette!(integer()) :: Palette.t()
  def get_palette!(id) do
    Palette
    |> Repo.get!(id)
    |> Repo.preload(:colors)
  end

  @spec create_palette(palette_attrs()) :: {:ok, Palette.t()} | {:error, Ecto.Changeset.t()}
  def create_palette(attrs) when is_map(attrs) do
    %Palette{}
    |> Palette.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_printer_profiles() :: [PrinterProfile.t()]
  def list_printer_profiles do
    PrinterProfile
    |> order_by([profile], asc: profile.printer_make_model, asc: profile.paper_type)
    |> Repo.all()
  end

  @spec get_printer_profile!(integer()) :: PrinterProfile.t()
  def get_printer_profile!(id), do: Repo.get!(PrinterProfile, id)

  @spec create_printer_profile(map()) :: {:ok, PrinterProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_printer_profile(attrs) when is_map(attrs) do
    %PrinterProfile{}
    |> PrinterProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Imports the built-in preset palettes into the database.

  Existing preset rows are updated in place by palette name. If a user-created
  palette already uses a built-in preset name, the import fails instead of
  overwriting that row.
  """
  @spec import_preset_palettes() :: {:ok, [Palette.t()]} | {:error, Ecto.Changeset.t()}
  def import_preset_palettes do
    import_preset_palettes(PaletteStorage.get_preset_palettes())
  end

  @spec import_preset_palettes([ColorMatching.Palette.t()]) ::
          {:ok, [Palette.t()]} | {:error, Ecto.Changeset.t()}
  def import_preset_palettes(preset_palettes) when is_list(preset_palettes) do
    Repo.transaction(fn ->
      Enum.reduce(preset_palettes, [], fn preset_palette, imported ->
        attrs = %{
          name: preset_palette.name,
          is_preset: true,
          colors:
            preset_palette.colors
            |> Enum.with_index()
            |> Enum.map(fn {hex_color, index} ->
              %{hex_color: hex_color, sort_order: index, display_label: nil}
            end)
        }

        case upsert_preset_palette(attrs) do
          {:ok, palette} -> [palette | imported]
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> Enum.reverse()
    end)
    |> case do
      {:ok, palettes} -> {:ok, palettes}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec upsert_preset_palette(palette_attrs()) ::
          {:ok, Palette.t()} | {:error, Ecto.Changeset.t()}
  defp upsert_preset_palette(attrs) do
    palette_name = Map.fetch!(attrs, :name)

    case Repo.get_by(Palette, name: palette_name, is_preset: true) do
      %Palette{} = palette ->
        palette = Repo.preload(palette, :colors)
        attrs = merge_palette_color_ids(attrs, palette)

        palette
        |> Palette.changeset(attrs)
        |> Repo.update()

      nil ->
        case Repo.get_by(Palette, name: palette_name) do
          %Palette{is_preset: false} ->
            {:error, preset_palette_name_conflict_changeset(attrs)}

          nil ->
            create_palette(attrs)
        end
    end
  end

  @spec preset_palette_name_conflict_changeset(palette_attrs()) :: Ecto.Changeset.t()
  defp preset_palette_name_conflict_changeset(attrs) do
    %Palette{}
    |> Ecto.Changeset.change(attrs)
    |> Ecto.Changeset.add_error(
      :name,
      "conflicts with an existing user palette; rename or remove the user palette before importing presets"
    )
  end

  @spec merge_palette_color_ids(palette_attrs(), Palette.t()) :: palette_attrs()
  defp merge_palette_color_ids(attrs, %Palette{} = palette) do
    existing_colors_by_hex =
      palette
      |> Map.fetch!(:colors)
      |> Enum.group_by(& &1.hex_color)

    Map.update(attrs, :colors, [], fn colors ->
      {merged_colors, _remaining_colors_by_hex} =
        Enum.map_reduce(colors, existing_colors_by_hex, &merge_palette_color_id/2)

      merged_colors
    end)
  end

  @spec merge_palette_color_id(map(), %{required(String.t()) => [map()]}) ::
          {map(), %{required(String.t()) => [map()]}}
  defp merge_palette_color_id(color_attrs, existing_colors_by_hex) do
    hex_color = Map.fetch!(color_attrs, :hex_color)

    case Map.get(existing_colors_by_hex, hex_color, []) do
      [existing_color | remaining_colors] ->
        {
          Map.put(color_attrs, :id, existing_color.id),
          Map.put(existing_colors_by_hex, hex_color, remaining_colors)
        }

      [] ->
        {color_attrs, existing_colors_by_hex}
    end
  end
end

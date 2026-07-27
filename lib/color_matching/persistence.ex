defmodule ColorMatching.Persistence do
  @moduledoc """
  Persistence boundary for palettes, palette colors, and printer profiles.
  """

  import Ecto.Query, warn: false

  alias ColorMatching.PaletteStorage
  alias ColorMatching.Persistence.{Palette, PaletteColor, PrinterProfile}
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

  @spec get_palette!(Ecto.UUID.t() | integer()) :: Palette.t()
  def get_palette!(id) do
    Palette
    |> Repo.get!(id)
    |> Repo.preload(:colors)
  end

  @spec create_palette(map()) :: {:ok, Palette.t()} | {:error, Ecto.Changeset.t()}
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

  @spec get_printer_profile!(Ecto.UUID.t() | integer()) :: PrinterProfile.t()
  def get_printer_profile!(id), do: Repo.get!(PrinterProfile, id)

  @spec create_printer_profile(map()) :: {:ok, PrinterProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_printer_profile(attrs) when is_map(attrs) do
    %PrinterProfile{}
    |> PrinterProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Imports the built-in preset palettes into the database.

  Existing preset rows are updated in place by palette name, making the import
  safe to run from seeds or from an API bootstrap step.
  """
  @spec import_preset_palettes() :: {:ok, [Palette.t()]} | {:error, Ecto.Changeset.t()}
  def import_preset_palettes do
    PaletteStorage.get_preset_palettes()
    |> Enum.reduce_while({:ok, []}, fn preset_palette, {:ok, imported} ->
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
        {:ok, palette} -> {:cont, {:ok, [palette | imported]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, palettes} -> {:ok, Enum.reverse(palettes)}
      error -> error
    end
  end

  defp upsert_preset_palette(attrs) do
    case Repo.get_by(Palette, name: Map.fetch!(attrs, :name)) do
      nil ->
        create_palette(attrs)

      %Palette{} = palette ->
        palette
        |> Repo.preload(:colors)
        |> Palette.changeset(attrs)
        |> Repo.update()
    end
  end
end

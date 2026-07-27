defmodule ColorMatching.Persistence do
  @moduledoc """
  Persistence boundary for palettes, palette colors, and printer profiles.
  """

  import Ecto.Query, warn: false

  alias ColorMatching.PaletteStorage
  alias ColorMatching.Persistence.{IlluminantMeasurement, Palette, PrinterProfile}
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

  @spec create_illuminant_measurement(map()) ::
          {:ok, IlluminantMeasurement.t()} | {:error, Ecto.Changeset.t()}
  def create_illuminant_measurement(attrs) when is_map(attrs) do
    %IlluminantMeasurement{}
    |> IlluminantMeasurement.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_illuminant_measurements(integer(), integer()) :: [IlluminantMeasurement.t()]
  def list_illuminant_measurements(palette_color_id, printer_profile_id) do
    IlluminantMeasurement
    |> where(
      [measurement],
      measurement.palette_color_id == ^palette_color_id and
        measurement.printer_profile_id == ^printer_profile_id
    )
    |> order_by([measurement],
      asc: measurement.light_source,
      asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", measurement.measured_at),
      desc: measurement.measured_at,
      desc: measurement.inserted_at,
      desc: measurement.id
    )
    |> Repo.all()
  end

  @spec get_latest_illuminant_measurement(integer(), integer(), String.t()) ::
          IlluminantMeasurement.t() | nil
  def get_latest_illuminant_measurement(palette_color_id, printer_profile_id, light_source) do
    palette_color_id
    |> latest_illuminant_measurements_query(printer_profile_id, light_source)
    |> Repo.one()
  end

  @spec latest_illuminant_measurements_by_light_source(integer(), integer()) ::
          %{optional(String.t()) => IlluminantMeasurement.t()}
  def latest_illuminant_measurements_by_light_source(palette_color_id, printer_profile_id) do
    palette_color_id
    |> latest_illuminant_measurements_query(printer_profile_id)
    |> Repo.all()
    |> Map.new(&{&1.light_source, &1})
  end

  @spec latest_illuminant_measurements_query(integer(), integer(), String.t() | nil) ::
          Ecto.Query.t()
  defp latest_illuminant_measurements_query(
         palette_color_id,
         printer_profile_id,
         light_source \\ nil
       ) do
    ranked_measurement_ids_query =
      palette_color_id
      |> ranked_illuminant_measurement_ids_query(printer_profile_id, light_source)
      |> subquery()

    from(ranked_measurement in ranked_measurement_ids_query,
      where: ranked_measurement.latest_rank == 1,
      join: measurement in IlluminantMeasurement,
      on: measurement.id == ranked_measurement.id,
      order_by: [asc: measurement.light_source],
      select: measurement
    )
  end

  @spec ranked_illuminant_measurement_ids_query(integer(), integer(), String.t() | nil) ::
          Ecto.Query.t()
  defp ranked_illuminant_measurement_ids_query(
         palette_color_id,
         printer_profile_id,
         light_source
       ) do
    IlluminantMeasurement
    |> where(
      [measurement],
      measurement.palette_color_id == ^palette_color_id and
        measurement.printer_profile_id == ^printer_profile_id
    )
    |> maybe_filter_light_source(light_source)
    |> windows([measurement],
      per_light_source: [
        partition_by: measurement.light_source,
        order_by: [
          asc: fragment("CASE WHEN ? IS NULL THEN 1 ELSE 0 END", measurement.measured_at),
          desc: measurement.measured_at,
          desc: measurement.inserted_at,
          desc: measurement.id
        ]
      ]
    )
    |> select([measurement], %{
      id: measurement.id,
      latest_rank: over(row_number(), :per_light_source)
    })
  end

  @spec maybe_filter_light_source(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_light_source(query, nil), do: query

  defp maybe_filter_light_source(query, light_source) do
    where(query, [measurement], measurement.light_source == ^light_source)
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
    case Repo.transaction(fn ->
           preset_palettes
           |> Enum.map(&preset_palette_attrs/1)
           |> Enum.reduce_while([], &upsert_or_rollback/2)
           |> finalize_transaction_result()
         end) do
      {:ok, {:ok, palettes}} -> {:ok, palettes}
      {:ok, {:error, _} = error} -> error
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec upsert_or_rollback(palette_attrs(), [Palette.t()]) ::
          {:cont, [Palette.t()]} | {:halt, {:error, Ecto.Changeset.t()}}
  defp upsert_or_rollback(attrs, imported) do
    case upsert_preset_palette(attrs) do
      {:ok, palette} -> {:cont, [palette | imported]}
      {:error, changeset} -> {:halt, Repo.rollback(changeset)}
    end
  end

  @spec finalize_transaction_result([Palette.t()] | {:error, term()}) ::
          {:ok, [Palette.t()]} | {:error, term()}
  defp finalize_transaction_result(imported) when is_list(imported) do
    {:ok, Enum.reverse(imported)}
  end

  defp finalize_transaction_result({:error, _} = error), do: error

  @spec preset_palette_attrs(ColorMatching.Palette.t()) :: palette_attrs()
  defp preset_palette_attrs(preset_palette) do
    %{
      name: preset_palette.name,
      is_preset: true,
      colors:
        preset_palette.colors
        |> Enum.with_index()
        |> Enum.map(fn {hex_color, index} ->
          %{hex_color: hex_color, sort_order: index, display_label: nil}
        end)
    }
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

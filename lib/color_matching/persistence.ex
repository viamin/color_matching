defmodule ColorMatching.Persistence do
  @moduledoc """
  Persistence boundary for palettes, palette colors, printer profiles, test sheets, and illuminant measurements.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [add_error: 3]

  alias ColorMatching.PaletteStorage

  alias ColorMatching.Persistence.{
    Capture,
    CaptureJudgmentUpload,
    CaptureUpload,
    IlluminantMeasurement,
    IlluminantResponse,
    PairFinding,
    PairFindingObservation,
    Palette,
    PaletteColor,
    PrintedPairClassification,
    PrinterProfile,
    TestSheet,
    TestSheetPair
  }

  alias ColorMatching.Repo
  alias ColorMatching.ResponseVector

  @type palette_attrs :: %{
          optional(:name) => String.t(),
          optional(:is_preset) => boolean(),
          optional(:colors) => [map()]
        }
  @type measurement_error_map :: %{optional(atom()) => [String.t()]}
  @type capture_upload_error_map :: %{optional(atom()) => [String.t()]}
  @type judgment_error_map :: %{optional(atom()) => [String.t()]}
  @type invalid_bulk_measurement_row :: %{
          index: non_neg_integer(),
          color_id: term(),
          errors: measurement_error_map()
        }
  @type invalid_capture_upload_row :: %{
          index: non_neg_integer(),
          identifier: term(),
          errors: capture_upload_error_map()
        }
  @type invalid_judgment_row :: %{
          index: non_neg_integer(),
          identifier: term(),
          errors: judgment_error_map()
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

  @spec get_palette(integer()) :: Palette.t() | nil
  def get_palette(id) do
    case Repo.get(Palette, id) do
      %Palette{} = palette -> Repo.preload(palette, :colors)
      nil -> nil
    end
  end

  @doc """
  Fetches a single palette color preloaded with its parent palette.

  Raises `Ecto.NoResultsError` when the color id is unknown.
  """
  @spec get_palette_color!(integer()) :: PaletteColor.t()
  def get_palette_color!(id) do
    PaletteColor
    |> Repo.get!(id)
    |> Repo.preload(:palette)
  end

  @doc """
  Fetches a single palette color preloaded with its parent palette, or
  returns `nil` when no row matches the given id.
  """
  @spec get_palette_color(integer()) :: PaletteColor.t() | nil
  def get_palette_color(id) do
    case Repo.get(PaletteColor, id) do
      %PaletteColor{} = palette_color -> Repo.preload(palette_color, :palette)
      nil -> nil
    end
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

  @spec get_printer_profile(integer()) :: PrinterProfile.t() | nil
  def get_printer_profile(id), do: Repo.get(PrinterProfile, id)

  @spec create_printer_profile(map()) :: {:ok, PrinterProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_printer_profile(attrs) when is_map(attrs) do
    %PrinterProfile{}
    |> PrinterProfile.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Test sheets
  # ---------------------------------------------------------------------------

  @doc """
  Returns the most recent test sheets up to `limit`, without preloading
  associations.

  Use this instead of `list_test_sheets/0` when only top-level sheet fields
  (e.g. `lookup_code`) are needed, to avoid loading unnecessary data.
  """
  @spec list_recent_test_sheets(keyword()) :: [TestSheet.t()]
  def list_recent_test_sheets(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    TestSheet
    |> order_by([sheet], desc: sheet.inserted_at, desc: sheet.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_test_sheet!(integer()) :: TestSheet.t()
  def get_test_sheet!(id) do
    TestSheet
    |> Repo.get!(id)
    |> preload_test_sheet_associations()
  end

  @doc """
  Fetches a test sheet by its stable lookup code.

  Returns `nil` when no sheet with that code exists.
  """
  @spec get_test_sheet_by_lookup_code(String.t()) :: TestSheet.t() | nil
  def get_test_sheet_by_lookup_code(lookup_code) do
    TestSheet
    |> Repo.get_by(lookup_code: lookup_code)
    |> case do
      nil -> nil
      test_sheet -> preload_test_sheet_associations(test_sheet)
    end
  end

  @doc """
  Fetches a test sheet by its stable lookup code, preloading the palette
  with its colors in addition to the printer profile and pairs.

  Raises `Ecto.NoResultsError` when no sheet with that code exists.
  """
  @spec get_test_sheet_by_lookup_code!(String.t()) :: TestSheet.t()
  def get_test_sheet_by_lookup_code!(lookup_code) do
    TestSheet
    |> Repo.get_by!(lookup_code: lookup_code)
    |> preload_test_sheet_associations()
  end

  @spec create_test_sheet(map()) :: {:ok, TestSheet.t()} | {:error, Ecto.Changeset.t()}
  def create_test_sheet(attrs) when is_map(attrs) do
    %TestSheet{}
    |> TestSheet.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Capture sessions
  # ---------------------------------------------------------------------------

  @spec create_capture(String.t(), map()) :: {:ok, Capture.t()} | {:error, term()}
  def create_capture(sheet_lookup_code, attrs)
      when is_binary(sheet_lookup_code) and is_map(attrs) do
    case Repo.get_by(TestSheet, lookup_code: sheet_lookup_code) do
      nil ->
        {:error, :test_sheet_not_found}

      %TestSheet{} = test_sheet ->
        attrs =
          attrs
          |> normalize_capture_attrs()
          |> Map.put(:test_sheet_id, test_sheet.id)

        %Capture{}
        |> Capture.changeset(attrs)
        |> Repo.insert()
    end
  end

  @spec get_capture(integer()) :: Capture.t() | nil
  def get_capture(id) do
    case Repo.get(Capture, id) do
      %Capture{} = capture -> Repo.preload(capture, :test_sheet)
      nil -> nil
    end
  end

  @spec list_capture_patch_measurements(integer()) :: [
          ColorMatching.Persistence.CapturePatchMeasurement.t()
        ]
  def list_capture_patch_measurements(capture_id) do
    ColorMatching.Persistence.CapturePatchMeasurement
    |> where([measurement], measurement.capture_id == ^capture_id)
    |> order_by([measurement], asc: measurement.patch_id)
    |> Repo.all()
  end

  @spec list_capture_pair_scores(integer()) :: [ColorMatching.Persistence.CapturePairScore.t()]
  def list_capture_pair_scores(capture_id) do
    ColorMatching.Persistence.CapturePairScore
    |> where([pair_score], pair_score.capture_id == ^capture_id)
    |> order_by([pair_score], asc: pair_score.pair_id, asc: pair_score.algorithm_version)
    |> Repo.all()
  end

  @spec list_pair_findings() :: [PairFinding.t()]
  def list_pair_findings do
    PairFinding
    |> order_by([pair_finding], asc: pair_finding.pair_id)
    |> Repo.all()
  end

  @spec get_pair_finding_by_pair_id(String.t()) :: PairFinding.t() | nil
  def get_pair_finding_by_pair_id(pair_id) when is_binary(pair_id) do
    Repo.get_by(PairFinding, pair_id: pair_id)
  end

  @spec list_pair_finding_observations(String.t()) :: [PairFindingObservation.t()]
  def list_pair_finding_observations(pair_id) when is_binary(pair_id) do
    PairFindingObservation
    |> where([observation], observation.pair_id == ^pair_id)
    |> order_by([observation], asc: observation.observed_at, asc: observation.id)
    |> Repo.all()
  end

  @spec upload_capture_measurements(integer(), map()) ::
          {:ok,
           %{
             measurements: [ColorMatching.Persistence.CapturePatchMeasurement.t()],
             pair_scores: [ColorMatching.Persistence.CapturePairScore.t()]
           }}
          | {:error, :capture_not_found}
          | {:error, {:invalid_request, capture_upload_error_map()}}
          | {:error,
             {:invalid_rows,
              %{
                measurements: [invalid_capture_upload_row()],
                pair_scores: [invalid_capture_upload_row()]
              }}}
  def upload_capture_measurements(capture_id, attrs)
      when is_integer(capture_id) and is_map(attrs) do
    case get_capture(capture_id) do
      nil ->
        {:error, :capture_not_found}

      %Capture{test_sheet_id: test_sheet_id} = capture ->
        valid_pair_ids = valid_pair_ids_for_sheet(test_sheet_id)
        CaptureUpload.upload(capture, attrs, valid_pair_ids)
    end
  end

  @spec upload_capture_judgments(integer(), map()) ::
          {:ok, [PairFindingObservation.t()]}
          | {:error, :capture_not_found}
          | {:error, {:invalid_request, judgment_error_map()}}
          | {:error, {:invalid_rows, [invalid_judgment_row()]}}
  def upload_capture_judgments(capture_id, attrs)
      when is_integer(capture_id) and is_map(attrs) do
    case get_capture(capture_id) do
      nil -> {:error, :capture_not_found}
      %Capture{} = capture -> CaptureJudgmentUpload.upload(capture, attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # Printed pair classifications
  # ---------------------------------------------------------------------------

  @spec list_printed_pair_classifications(keyword() | map()) :: [PrintedPairClassification.t()]
  def list_printed_pair_classifications(filters \\ %{}) do
    filters = normalize_printed_pair_classification_filters(filters)

    PrintedPairClassification
    |> join(:inner, [classification], pair in TestSheetPair,
      on: pair.id == classification.test_sheet_pair_id
    )
    |> maybe_filter_printed_pair_classification(:test_sheet_pair_id, filters[:test_sheet_pair_id])
    |> maybe_filter_printed_pair_classification(
      :reproduction_profile_id,
      filters[:reproduction_profile_id]
    )
    |> maybe_filter_printed_pair_classification(:illuminant, filters[:illuminant])
    |> maybe_filter_printed_pair_classification(:classification, filters[:classification])
    |> maybe_filter_printed_pair_classification(:active, filters[:active])
    |> maybe_filter_printed_pair_id(filters[:pair_id])
    |> order_by([classification, pair],
      asc: pair.pair_id,
      asc: classification.illuminant,
      desc: classification.active,
      desc: classification.inserted_at,
      desc: classification.id
    )
    |> select([classification, _pair], classification)
    |> Repo.all()
    |> Repo.preload([:reproduction_profile, :test_sheet_pair])
  end

  @spec list_printed_pair_classification_history(integer(), integer(), String.t()) ::
          [PrintedPairClassification.t()]
  def list_printed_pair_classification_history(
        test_sheet_pair_id,
        reproduction_profile_id,
        illuminant
      )
      when is_integer(test_sheet_pair_id) and is_integer(reproduction_profile_id) and
             is_binary(illuminant) do
    list_printed_pair_classifications(%{
      test_sheet_pair_id: test_sheet_pair_id,
      reproduction_profile_id: reproduction_profile_id,
      illuminant: illuminant,
      active: nil
    })
  end

  @spec get_active_printed_pair_classification(integer(), integer(), String.t()) ::
          PrintedPairClassification.t() | nil
  def get_active_printed_pair_classification(
        test_sheet_pair_id,
        reproduction_profile_id,
        illuminant
      )
      when is_integer(test_sheet_pair_id) and is_integer(reproduction_profile_id) and
             is_binary(illuminant) do
    list_printed_pair_classifications(%{
      test_sheet_pair_id: test_sheet_pair_id,
      reproduction_profile_id: reproduction_profile_id,
      illuminant: illuminant,
      active: true
    })
    |> List.first()
  end

  @spec set_printed_pair_classification(map()) ::
          {:ok, PrintedPairClassification.t()} | {:error, Ecto.Changeset.t()}
  def set_printed_pair_classification(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_printed_pair_classification_attrs()
      |> Map.put(:active, true)

    changeset =
      %PrintedPairClassification{}
      |> PrintedPairClassification.changeset(attrs)
      |> validate_printed_pair_classification_references(attrs)

    if changeset.valid? do
      persist_printed_pair_classification(changeset, attrs)
    else
      {:error, changeset}
    end
  end

  @spec clear_printed_pair_classification(integer(), integer(), String.t()) ::
          {non_neg_integer(), nil}
  def clear_printed_pair_classification(test_sheet_pair_id, reproduction_profile_id, illuminant)
      when is_integer(test_sheet_pair_id) and is_integer(reproduction_profile_id) and
             is_binary(illuminant) do
    deactivate_printed_pair_classification_scope(%{
      test_sheet_pair_id: test_sheet_pair_id,
      reproduction_profile_id: reproduction_profile_id,
      illuminant: illuminant
    })
  end

  @spec preload_test_sheet_associations(TestSheet.t() | [TestSheet.t()]) ::
          TestSheet.t() | [TestSheet.t()]
  defp preload_test_sheet_associations(test_sheet_or_sheets) do
    Repo.preload(test_sheet_or_sheets, [{:palette, :colors}, :printer_profile, :pairs])
  end

  # ---------------------------------------------------------------------------
  # Illuminant responses
  # ---------------------------------------------------------------------------

  @spec set_illuminant_response(map()) ::
          {:ok, IlluminantResponse.t()} | {:error, Ecto.Changeset.t()}
  def set_illuminant_response(attrs) when is_map(attrs) do
    attrs = normalize_illuminant_response_attrs(attrs)

    changeset =
      %IlluminantResponse{}
      |> IlluminantResponse.changeset(attrs)
      |> validate_illuminant_response_references(attrs)

    if changeset.valid? do
      Repo.insert(changeset,
        on_conflict: {:replace, [:apparent_brightness, :notes, :source_measurement_id, :updated_at]},
        conflict_target: [:palette_color_id, :printer_profile_id, :illuminant]
      )
    else
      {:error, changeset}
    end
  end

  @spec update_illuminant_response(map()) ::
          {:ok, IlluminantResponse.t()} | {:error, Ecto.Changeset.t()}
  def update_illuminant_response(attrs), do: set_illuminant_response(attrs)

  @spec clear_illuminant_response(integer(), integer(), String.t()) :: {non_neg_integer(), nil}
  def clear_illuminant_response(palette_color_id, printer_profile_id, illuminant) do
    IlluminantResponse
    |> where(
      [response],
      response.palette_color_id == ^palette_color_id and
        response.printer_profile_id == ^printer_profile_id and response.illuminant == ^illuminant
    )
    |> Repo.delete_all()
  end

  @spec list_illuminant_responses(integer(), integer()) ::
          %{optional(String.t()) => IlluminantResponse.t()}
  def list_illuminant_responses(palette_color_id, printer_profile_id) do
    IlluminantResponse
    |> where(
      [response],
      response.palette_color_id == ^palette_color_id and
        response.printer_profile_id == ^printer_profile_id
    )
    |> order_by([response], asc: response.illuminant)
    |> Repo.all()
    |> Map.new(&{&1.illuminant, &1})
  end

  @spec get_illuminant_response(integer(), integer(), String.t()) :: IlluminantResponse.t() | nil
  def get_illuminant_response(palette_color_id, printer_profile_id, illuminant) do
    Repo.get_by(IlluminantResponse,
      palette_color_id: palette_color_id,
      printer_profile_id: printer_profile_id,
      illuminant: illuminant
    )
  end

  # ---------------------------------------------------------------------------
  # Illuminant measurements
  # ---------------------------------------------------------------------------

  @spec create_illuminant_measurement(map()) ::
          {:ok, IlluminantMeasurement.t()} | {:error, Ecto.Changeset.t()}
  def create_illuminant_measurement(attrs) when is_map(attrs) do
    attrs = normalize_measurement_attrs(attrs)

    %IlluminantMeasurement{}
    |> IlluminantMeasurement.changeset(attrs)
    |> validate_measurement_references(attrs)
    |> Repo.insert()
  end

  @spec create_illuminant_measurements_bulk(map()) ::
          {:ok, [IlluminantMeasurement.t()]}
          | {:error, {:invalid_request, measurement_error_map()}}
          | {:error, {:invalid_rows, [invalid_bulk_measurement_row()]}}
  def create_illuminant_measurements_bulk(attrs) when is_map(attrs) do
    case fetch_bulk_measurements(attrs) do
      {:ok, measurements} ->
        shared_attrs =
          attrs
          |> Map.drop([:measurements, "measurements"])
          |> normalize_measurement_attrs()

        prepared_measurements =
          measurements
          |> Enum.with_index()
          |> prepare_bulk_measurements(shared_attrs)

        case collect_invalid_bulk_rows(prepared_measurements) do
          [] -> insert_bulk_measurements(prepared_measurements)
          invalid_rows -> {:error, {:invalid_rows, invalid_rows}}
        end

      error ->
        error
    end
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

  @spec response_vectors([PaletteColor.t()], PrinterProfile.t()) :: [ResponseVector.t()]
  def response_vectors(palette_colors, %PrinterProfile{id: printer_profile_id})
      when is_list(palette_colors) and is_integer(printer_profile_id) do
    palette_color_ids = Enum.map(palette_colors, & &1.id)

    responses_by_palette_color =
      IlluminantResponse
      |> where(
        [response],
        response.palette_color_id in ^palette_color_ids and
          response.printer_profile_id == ^printer_profile_id
      )
      |> Repo.all()
      |> Enum.group_by(& &1.palette_color_id, &{&1.illuminant, &1})
      |> Map.new(fn {palette_color_id, responses} ->
        {palette_color_id, Map.new(responses)}
      end)

    measurements_by_palette_color =
      palette_color_ids
      |> latest_illuminant_measurements_query(printer_profile_id)
      |> Repo.all()
      |> Enum.group_by(& &1.palette_color_id, &{&1.light_source, &1})
      |> Map.new(fn {palette_color_id, measurements} ->
        {palette_color_id, Map.new(measurements)}
      end)

    Enum.map(
      palette_colors,
      &response_vector_from_records(
        &1,
        printer_profile_id,
        Map.get(responses_by_palette_color, &1.id, %{}),
        Map.get(measurements_by_palette_color, &1.id, %{})
      )
    )
  end

  def response_vectors(_palette_colors, %PrinterProfile{}) do
    raise ArgumentError, "response_vectors/2 requires a persisted printer profile"
  end

  @doc """
  Builds a response vector for a palette color under a printer profile using
  the latest persisted illuminant measurements.

  Light sources without any persisted measurement contribute `:missing` to
  the resulting vector so callers can distinguish "never measured" from
  "measured as zero brightness".
  """
  @spec response_vector(PaletteColor.t(), PrinterProfile.t()) :: ResponseVector.t()
  def response_vector(
        %PaletteColor{id: palette_color_id, hex_color: hex_color},
        %PrinterProfile{id: printer_profile_id}
      )
      when is_integer(palette_color_id) and is_binary(hex_color) and
             is_integer(printer_profile_id) do
    records =
      list_illuminant_responses(palette_color_id, printer_profile_id)
      |> Map.merge(latest_illuminant_measurements_by_light_source(palette_color_id, printer_profile_id),
        fn _illuminant, response, _measurement -> response end
      )

    ResponseVector.new(hex_color, printer_profile_id, records)
  end

  def response_vector(%PaletteColor{}, %PrinterProfile{}) do
    raise ArgumentError, "response_vector/2 requires persisted palette color and printer profile"
  end

  @spec latest_illuminant_measurements_query(
          integer() | [integer()],
          integer(),
          String.t() | nil
        ) :: Ecto.Query.t()
  defp latest_illuminant_measurements_query(
         palette_color_ids,
         printer_profile_id,
         light_source \\ nil
       ) do
    ranked_measurement_ids_query =
      ranked_illuminant_measurement_ids_query(
        List.wrap(palette_color_ids),
        printer_profile_id,
        light_source
      )
      |> subquery()

    from(ranked_measurement in ranked_measurement_ids_query,
      where: ranked_measurement.latest_rank == 1,
      join: measurement in IlluminantMeasurement,
      on: measurement.id == ranked_measurement.id,
      order_by: [asc: measurement.light_source],
      select: measurement
    )
  end

  @spec ranked_illuminant_measurement_ids_query([integer()], integer(), String.t() | nil) ::
          Ecto.Query.t()
  defp ranked_illuminant_measurement_ids_query(
         palette_color_ids,
         printer_profile_id,
         light_source
       ) do
    IlluminantMeasurement
    |> where(
      [measurement],
      measurement.palette_color_id in ^palette_color_ids and
        measurement.printer_profile_id == ^printer_profile_id
    )
    |> maybe_filter_light_source(light_source)
    |> windows([measurement],
      per_light_source: [
        partition_by: [measurement.palette_color_id, measurement.light_source],
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

  defp response_vector_from_records(
         %PaletteColor{id: palette_color_id, hex_color: hex_color},
         printer_profile_id,
         responses,
         measurements
       )
       when is_integer(palette_color_id) and is_binary(hex_color) do
    records = Map.merge(measurements, responses, fn _source, _measurement, response -> response end)
    ResponseVector.new(hex_color, printer_profile_id, records)
  end

  defp response_vector_from_records(%PaletteColor{}, _printer_profile_id, _responses, _measurements) do
    raise ArgumentError, "response_vectors/2 requires persisted palette colors with hex colors"
  end

         %PaletteColor{id: palette_color_id, hex_color: hex_color},
         printer_profile_id,
         measurements_by_palette_color
       )
       when is_integer(palette_color_id) and is_binary(hex_color) do
    measurements = Map.get(measurements_by_palette_color, palette_color_id, %{})
    ResponseVector.new(hex_color, printer_profile_id, measurements)
  end

  defp response_vector_from_measurements(%PaletteColor{}, _printer_profile_id, _measurements) do
    raise ArgumentError, "response_vectors/2 requires persisted palette colors with hex colors"
  end

  @spec fetch_bulk_measurements(map()) ::
          {:ok, [map()]} | {:error, {:invalid_request, measurement_error_map()}}
  defp fetch_bulk_measurements(attrs) do
    case first_present_value(attrs, [:measurements, "measurements"]) do
      measurements when is_list(measurements) and measurements != [] ->
        if Enum.all?(measurements, &is_map/1) do
          {:ok, measurements}
        else
          {:error, {:invalid_request, %{measurements: ["must contain only measurement objects"]}}}
        end

      [] ->
        {:error, {:invalid_request, %{measurements: ["must contain at least one measurement"]}}}

      nil ->
        {:error, {:invalid_request, %{measurements: ["is required"]}}}

      _other ->
        {:error, {:invalid_request, %{measurements: ["must be a list"]}}}
    end
  end

  @spec prepare_bulk_measurements([{map(), non_neg_integer()}], map()) :: [map()]
  defp prepare_bulk_measurements(indexed_measurements, shared_attrs) do
    printer_profile_ids =
      indexed_measurements
      |> Enum.map(fn {measurement_attrs, _index} ->
        measurement_attrs
        |> normalize_measurement_attrs()
        |> Map.get(:printer_profile_id, shared_attrs[:printer_profile_id])
      end)
      |> Enum.reject(&is_nil/1)
      |> existing_ids(PrinterProfile)

    palette_color_ids =
      indexed_measurements
      |> Enum.map(fn {measurement_attrs, _index} ->
        measurement_attrs
        |> normalize_measurement_attrs()
        |> Map.get(:palette_color_id, shared_attrs[:palette_color_id])
      end)
      |> Enum.reject(&is_nil/1)
      |> existing_ids(PaletteColor)

    Enum.map(indexed_measurements, fn {measurement_attrs, index} ->
      attrs =
        shared_attrs
        |> Map.merge(normalize_measurement_attrs(measurement_attrs))

      changeset =
        %IlluminantMeasurement{}
        |> IlluminantMeasurement.changeset(attrs)
        |> validate_measurement_references(palette_color_ids, printer_profile_ids)

      %{
        index: index,
        color_id: attrs[:palette_color_id],
        changeset: changeset
      }
    end)
  end

  @spec existing_ids([term()], module()) :: MapSet.t(integer())
  defp existing_ids([], _schema), do: MapSet.new()

  defp existing_ids(ids, schema) do
    ids = cast_integer_ids(ids)

    schema
    |> where([record], record.id in ^ids)
    |> select([record], record.id)
    |> Repo.all()
    |> MapSet.new()
  end

  @spec cast_integer_ids([term()]) :: [integer()]
  defp cast_integer_ids(ids) do
    ids
    |> Enum.map(&Ecto.Type.cast(:integer, &1))
    |> Enum.flat_map(fn
      {:ok, id} -> [id]
      :error -> []
    end)
    |> Enum.uniq()
  end

  @spec collect_invalid_bulk_rows([map()]) :: [invalid_bulk_measurement_row()]
  defp collect_invalid_bulk_rows(prepared_measurements) do
    prepared_measurements
    |> Enum.flat_map(fn prepared_measurement ->
      if prepared_measurement.changeset.valid? do
        []
      else
        [
          %{
            index: prepared_measurement.index,
            color_id: prepared_measurement.color_id,
            errors: changeset_errors(prepared_measurement.changeset)
          }
        ]
      end
    end)
  end

  @spec insert_bulk_measurements([map()]) ::
          {:ok, [IlluminantMeasurement.t()]}
          | {:error, {:invalid_rows, [invalid_bulk_measurement_row()]}}
  defp insert_bulk_measurements(prepared_measurements) do
    transaction_result =
      fn -> insert_each_measurement(prepared_measurements) end
      |> Repo.transaction()

    case transaction_result do
      {:ok, inserted_measurements} -> {:ok, Enum.reverse(inserted_measurements)}
      {:error, {:invalid_rows, invalid_rows}} -> {:error, {:invalid_rows, invalid_rows}}
    end
  end

  @spec insert_each_measurement([map()]) :: [IlluminantMeasurement.t()]
  defp insert_each_measurement(prepared_measurements) do
    Enum.reduce_while(prepared_measurements, [], fn prepared_measurement, inserted ->
      case Repo.insert(prepared_measurement.changeset) do
        {:ok, measurement} ->
          {:cont, [measurement | inserted]}

        {:error, changeset} ->
          Repo.rollback(invalid_row(prepared_measurement, changeset))
      end
    end)
  end

  @spec invalid_row(map(), Ecto.Changeset.t()) ::
          {:invalid_rows, [invalid_bulk_measurement_row()]}
  defp invalid_row(prepared_measurement, changeset) do
    {:invalid_rows,
     [
       %{
         index: prepared_measurement.index,
         color_id: prepared_measurement.color_id,
         errors: changeset_errors(changeset)
       }
     ]}
  end

  @spec normalize_illuminant_response_attrs(map()) :: map()
  defp normalize_illuminant_response_attrs(attrs) do
    attrs
    |> normalize_measurement_key(:palette_color_id, [:palette_color_id, "palette_color_id", :color_id, "color_id"])
    |> normalize_measurement_key(:printer_profile_id, [:printer_profile_id, "printer_profile_id", :reproduction_profile_id, "reproduction_profile_id"])
    |> normalize_measurement_key(:illuminant, [:illuminant, "illuminant", :light_source, "light_source"])
    |> normalize_measurement_key(:apparent_brightness, [:apparent_brightness, "apparent_brightness", :brightness_score, "brightness_score"])
    |> normalize_measurement_key(:notes, [:notes, "notes"])
    |> normalize_measurement_key(:source_measurement_id, [:source_measurement_id, "source_measurement_id"])
  end

  @spec validate_illuminant_response_references(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_illuminant_response_references(changeset, attrs) do
    changeset
    |> validate_measurement_references(
      attrs |> Map.get(:palette_color_id) |> List.wrap() |> existing_ids(PaletteColor),
      attrs |> Map.get(:printer_profile_id) |> List.wrap() |> existing_ids(PrinterProfile)
    )
  end

  defp normalize_measurement_attrs(attrs) do
    attrs
    |> normalize_measurement_key(:palette_color_id, [
      :palette_color_id,
      "palette_color_id",
      :color_id,
      "color_id"
    ])
    |> normalize_measurement_key(:normalized_brightness, [
      :normalized_brightness,
      "normalized_brightness",
      :brightness,
      "brightness"
    ])
    |> normalize_measurement_key(:raw_measured_value, [
      :raw_measured_value,
      "raw_measured_value",
      :raw_value,
      "raw_value"
    ])
    |> normalize_measurement_key(:raw_value_unit, [
      :raw_value_unit,
      "raw_value_unit",
      :raw_unit,
      "raw_unit"
    ])
    |> normalize_measurement_key(:printer_profile_id, [
      :printer_profile_id,
      "printer_profile_id"
    ])
    |> normalize_measurement_key(:light_source, [:light_source, "light_source"])
    |> normalize_measurement_key(:notes, [:notes, "notes"])
    |> normalize_measurement_key(:measured_at, [:measured_at, "measured_at"])
    |> normalize_measurement_key(:measurement_method, [:measurement_method, "measurement_method"])
    |> normalize_measurement_key(:measurement_device, [:measurement_device, "measurement_device"])
    |> normalize_measurement_key(:test_run_id, [:test_run_id, "test_run_id"])
  end

  @spec normalize_printed_pair_classification_attrs(map()) :: map()
  defp normalize_printed_pair_classification_attrs(attrs) do
    attrs
    |> normalize_measurement_key(:test_sheet_pair_id, [:test_sheet_pair_id, "test_sheet_pair_id"])
    |> normalize_measurement_key(:reproduction_profile_id, [
      :reproduction_profile_id,
      "reproduction_profile_id",
      :printer_profile_id,
      "printer_profile_id"
    ])
    |> normalize_measurement_key(:illuminant, [:illuminant, "illuminant"])
    |> normalize_measurement_key(:classification, [:classification, "classification"])
    |> normalize_measurement_key(:active, [:active, "active"])
    |> normalize_measurement_key(:notes, [:notes, "notes"])
  end

  @spec normalize_capture_attrs(map()) :: map()
  defp normalize_capture_attrs(attrs) do
    attrs
    |> normalize_capture_key(:device_model)
    |> normalize_capture_key(:lens)
    |> normalize_capture_key(:exposure_duration)
    |> normalize_capture_key(:iso)
    |> normalize_capture_key(:focus_lens_position)
    |> normalize_capture_key(:image_width)
    |> normalize_capture_key(:image_height)
    |> normalize_capture_key(:app_version)
    |> normalize_capture_key(:timestamp)
    |> normalize_capture_key(:detected_marker_count)
    |> normalize_capture_key(:blur_score)
    |> normalize_capture_json_key(:white_balance_gains)
    |> normalize_capture_json_key(:rejection_reasons)
    |> Map.take([
      :device_model,
      :lens,
      :exposure_duration,
      :iso,
      :focus_lens_position,
      :image_width,
      :image_height,
      :app_version,
      :timestamp,
      :detected_marker_count,
      :blur_score,
      :white_balance_gains,
      :rejection_reasons
    ])
  end

  @spec normalize_capture_key(map(), atom()) :: map()
  defp normalize_capture_key(attrs, key) do
    case first_present_value(attrs, [key, Atom.to_string(key)]) do
      nil -> attrs
      value -> Map.put(attrs, key, value)
    end
  end

  @spec normalize_capture_json_key(map(), atom()) :: map()
  defp normalize_capture_json_key(attrs, key) do
    case first_present_value(attrs, [key, Atom.to_string(key)]) do
      nil ->
        attrs

      value when is_binary(value) ->
        Map.put(attrs, key, value)

      value ->
        Map.put(attrs, key, Jason.encode!(value))
    end
  end

  @spec normalize_measurement_key(map(), atom(), [atom() | String.t()]) :: map()
  defp normalize_measurement_key(attrs, canonical_key, source_keys) do
    case first_present_value(attrs, source_keys) do
      nil ->
        attrs

      value ->
        attrs
        |> Map.drop(source_keys)
        |> Map.put(canonical_key, value)
    end
  end

  @spec valid_pair_ids_for_sheet(integer()) :: MapSet.t(String.t())
  defp valid_pair_ids_for_sheet(test_sheet_id) do
    ColorMatching.Persistence.TestSheetPair
    |> where([pair], pair.test_sheet_id == ^test_sheet_id)
    |> select([pair], pair.pair_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @spec normalize_printed_pair_classification_filters(keyword() | map()) :: map()
  defp normalize_printed_pair_classification_filters(filters) when is_list(filters) do
    filters |> Enum.into(%{}) |> normalize_printed_pair_classification_filters()
  end

  defp normalize_printed_pair_classification_filters(filters) when is_map(filters) do
    filters
    |> normalize_measurement_key(:test_sheet_pair_id, [:test_sheet_pair_id, "test_sheet_pair_id"])
    |> normalize_measurement_key(:pair_id, [:pair_id, "pair_id"])
    |> normalize_measurement_key(:reproduction_profile_id, [
      :reproduction_profile_id,
      "reproduction_profile_id",
      :printer_profile_id,
      "printer_profile_id"
    ])
    |> normalize_measurement_key(:illuminant, [:illuminant, "illuminant"])
    |> normalize_measurement_key(:classification, [:classification, "classification"])
    |> normalize_measurement_key(:active, [:active, "active"])
  end

  @spec maybe_filter_printed_pair_classification(Ecto.Query.t(), atom(), term()) :: Ecto.Query.t()
  defp maybe_filter_printed_pair_classification(query, _field, nil), do: query

  defp maybe_filter_printed_pair_classification(query, field, value) do
    where(query, [classification, _pair], field(classification, ^field) == ^value)
  end

  @spec maybe_filter_printed_pair_id(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_printed_pair_id(query, nil), do: query

  defp maybe_filter_printed_pair_id(query, pair_id) do
    where(query, [_classification, pair], pair.pair_id == ^pair_id)
  end

  @spec first_present_value(map(), [atom() | String.t()]) :: term() | nil
  defp first_present_value(attrs, keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(attrs, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  @spec validate_measurement_references(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_measurement_references(changeset, attrs) do
    palette_color_ids =
      attrs
      |> Map.get(:palette_color_id)
      |> List.wrap()
      |> existing_ids(PaletteColor)

    printer_profile_ids =
      attrs
      |> Map.get(:printer_profile_id)
      |> List.wrap()
      |> existing_ids(PrinterProfile)

    validate_measurement_references(changeset, palette_color_ids, printer_profile_ids)
  end

  @spec validate_measurement_references(
          Ecto.Changeset.t(),
          MapSet.t(integer()),
          MapSet.t(integer())
        ) :: Ecto.Changeset.t()
  defp validate_measurement_references(
         changeset,
         existing_palette_color_ids,
         existing_printer_profile_ids
       ) do
    changeset
    |> maybe_add_missing_reference_error(
      :palette_color_id,
      Ecto.Changeset.get_field(changeset, :palette_color_id),
      existing_palette_color_ids
    )
    |> maybe_add_missing_reference_error(
      :printer_profile_id,
      Ecto.Changeset.get_field(changeset, :printer_profile_id),
      existing_printer_profile_ids
    )
  end

  @spec validate_printed_pair_classification_references(Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  defp validate_printed_pair_classification_references(changeset, attrs) do
    test_sheet_pair_ids =
      attrs
      |> Map.get(:test_sheet_pair_id)
      |> List.wrap()
      |> existing_ids(TestSheetPair)

    reproduction_profile_ids =
      attrs
      |> Map.get(:reproduction_profile_id)
      |> List.wrap()
      |> existing_ids(PrinterProfile)

    changeset
    |> maybe_add_missing_reference_error(
      :test_sheet_pair_id,
      Ecto.Changeset.get_field(changeset, :test_sheet_pair_id),
      test_sheet_pair_ids
    )
    |> maybe_add_missing_reference_error(
      :reproduction_profile_id,
      Ecto.Changeset.get_field(changeset, :reproduction_profile_id),
      reproduction_profile_ids
    )
  end

  @spec persist_printed_pair_classification(Ecto.Changeset.t(), map()) ::
          {:ok, PrintedPairClassification.t()} | {:error, Ecto.Changeset.t()}
  defp persist_printed_pair_classification(changeset, attrs) do
    case Repo.transaction(fn ->
           deactivate_printed_pair_classification_scope(attrs)
           insert_printed_pair_classification(changeset)
         end) do
      {:ok, classification} -> {:ok, classification}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @spec insert_printed_pair_classification(Ecto.Changeset.t()) :: PrintedPairClassification.t()
  defp insert_printed_pair_classification(changeset) do
    case Repo.insert(changeset) do
      {:ok, classification} ->
        Repo.preload(classification, [:reproduction_profile, :test_sheet_pair])

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @spec deactivate_printed_pair_classification_scope(map()) :: {non_neg_integer(), nil}
  defp deactivate_printed_pair_classification_scope(attrs) do
    PrintedPairClassification
    |> where(
      [classification],
      classification.test_sheet_pair_id == ^attrs[:test_sheet_pair_id] and
        classification.reproduction_profile_id == ^attrs[:reproduction_profile_id] and
        classification.illuminant == ^attrs[:illuminant] and
        classification.active == true
    )
    |> Repo.update_all(set: [active: false])
  end

  @spec maybe_add_missing_reference_error(
          Ecto.Changeset.t(),
          atom(),
          integer() | nil,
          MapSet.t(integer())
        ) :: Ecto.Changeset.t()
  defp maybe_add_missing_reference_error(changeset, _field, nil, _existing_ids), do: changeset

  defp maybe_add_missing_reference_error(changeset, field, id, existing_ids) do
    if MapSet.member?(existing_ids, id) do
      changeset
    else
      add_error(changeset, field, "does not exist")
    end
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
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

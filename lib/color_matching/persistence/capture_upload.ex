defmodule ColorMatching.Persistence.CaptureUpload do
  @moduledoc """
  Validates and upserts patch measurements plus pair scores for a capture.
  """

  import Ecto.Changeset, only: [add_error: 3]
  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi

  alias ColorMatching.Persistence.{
    Capture,
    CapturePairScore,
    CapturePatchMeasurement
  }

  alias ColorMatching.Repo

  @type invalid_row :: %{
          index: non_neg_integer(),
          identifier: term(),
          errors: %{optional(atom()) => [String.t()]}
        }

  @type invalid_rows :: %{
          measurements: [invalid_row()],
          pair_scores: [invalid_row()]
        }

  @type invalid_request :: %{optional(atom()) => [String.t()]}

  @spec upload(Capture.t(), map(), MapSet.t(String.t()), MapSet.t(String.t())) ::
          {:ok,
           %{measurements: [CapturePatchMeasurement.t()], pair_scores: [CapturePairScore.t()]}}
          | {:error, {:invalid_request, invalid_request()}}
          | {:error, {:invalid_rows, invalid_rows()}}
  def upload(%Capture{id: capture_id}, attrs, valid_patch_ids, valid_pair_ids)
      when is_integer(capture_id) do
    with {:ok, measurements, pair_scores} <- fetch_payload_lists(attrs),
         prepared_measurements <- prepare_measurements(measurements, capture_id, valid_patch_ids),
         prepared_pair_scores <- prepare_pair_scores(pair_scores, capture_id, valid_pair_ids),
         {:ok, %{measurements: persisted_measurements, pair_scores: persisted_pair_scores}} <-
           persist(prepared_measurements, prepared_pair_scores) do
      {:ok, %{measurements: persisted_measurements, pair_scores: persisted_pair_scores}}
    else
      {:error, _reason} = error ->
        error
    end
  end

  @spec fetch_payload_lists(map()) ::
          {:ok, [map()], [map()]} | {:error, {:invalid_request, invalid_request()}}
  defp fetch_payload_lists(attrs) when is_map(attrs) do
    measurements = Map.get(attrs, "measurements", Map.get(attrs, :measurements, []))
    pair_scores = Map.get(attrs, "pair_scores", Map.get(attrs, :pair_scores, []))

    errors =
      %{}
      |> validate_list_field(:measurements, measurements)
      |> validate_list_field(:pair_scores, pair_scores)
      |> validate_non_empty_upload(measurements, pair_scores)

    if map_size(errors) == 0 do
      {:ok, measurements || [], pair_scores || []}
    else
      {:error, {:invalid_request, errors}}
    end
  end

  @spec validate_list_field(map(), atom(), term()) :: map()
  defp validate_list_field(errors, _field, nil), do: errors

  defp validate_list_field(errors, field, values) when is_list(values) do
    if Enum.all?(values, &is_map/1) do
      errors
    else
      Map.put(errors, field, ["must contain only objects"])
    end
  end

  defp validate_list_field(errors, field, _values) do
    Map.put(errors, field, ["must be a list"])
  end

  @spec validate_non_empty_upload(map(), term(), term()) :: map()
  defp validate_non_empty_upload(errors, measurements, pair_scores) do
    if List.wrap(measurements) == [] and List.wrap(pair_scores) == [] do
      Map.put(errors, :base, ["must include at least one measurement or pair score"])
    else
      errors
    end
  end

  @spec prepare_measurements([map()], integer(), MapSet.t(String.t())) :: [map()]
  defp prepare_measurements(measurements, capture_id, valid_pair_ids) do
    Enum.with_index(measurements)
    |> Enum.map(fn {measurement_attrs, index} ->
      attrs = normalize_measurement_attrs(measurement_attrs, capture_id)

      changeset =
        %CapturePatchMeasurement{}
        |> CapturePatchMeasurement.changeset(attrs)
        |> validate_manifest_id(:patch_id, attrs[:patch_id], valid_pair_ids)

      %{index: index, identifier: attrs[:patch_id], changeset: changeset}
    end)
  end

  @spec prepare_pair_scores([map()], integer(), MapSet.t(String.t())) :: [map()]
  defp prepare_pair_scores(pair_scores, capture_id, valid_pair_ids) do
    Enum.with_index(pair_scores)
    |> Enum.map(fn {pair_score_attrs, index} ->
      attrs = normalize_pair_score_attrs(pair_score_attrs, capture_id)

      changeset =
        %CapturePairScore{}
        |> CapturePairScore.changeset(attrs)
        |> validate_manifest_id(:pair_id, attrs[:pair_id], valid_pair_ids)

      %{index: index, identifier: attrs[:pair_id], changeset: changeset}
    end)
  end

  @spec validate_manifest_id(Ecto.Changeset.t(), atom(), term(), MapSet.t(String.t())) ::
          Ecto.Changeset.t()
  defp validate_manifest_id(changeset, field, id, valid_pair_ids) do
    if is_binary(id) and MapSet.member?(valid_pair_ids, id) do
      changeset
    else
      add_error(changeset, field, "is not present on the capture sheet")
    end
  end

  @spec normalize_measurement_attrs(map(), integer()) :: map()
  defp normalize_measurement_attrs(attrs, capture_id) do
    # The iOS contract nests robustness stats under "stats"; older callers send
    # them flat. Accept both, with the top-level value preferred.
    stats = fetch_value(attrs, :stats) || %{}

    %{
      capture_id: capture_id,
      patch_id: fetch_value(attrs, :patch_id),
      linear_rgb_median: encode_rgb_payload(fetch_value(attrs, :linear_rgb_median)),
      normalized_linear_rgb_median:
        encode_rgb_payload(fetch_value(attrs, :normalized_linear_rgb_median)),
      sample_count: fetch_value(attrs, :sample_count) || fetch_value(stats, :sample_count),
      clipping_fraction:
        fetch_value(attrs, :clipping_fraction) || fetch_value(stats, :clipping_fraction),
      mean: encode_rgb_payload(fetch_value(attrs, :mean) || fetch_value(stats, :mean)),
      standard_deviation:
        encode_rgb_payload(
          fetch_value(attrs, :standard_deviation) || fetch_value(stats, :standard_deviation)
        )
    }
  end

  @spec normalize_pair_score_attrs(map(), integer()) :: map()
  defp normalize_pair_score_attrs(attrs, capture_id) do
    %{
      capture_id: capture_id,
      pair_id: fetch_value(attrs, :pair_id),
      algorithm_version: fetch_value(attrs, :algorithm_version),
      score: resolve_score(attrs)
    }
  end

  @spec resolve_score(map()) :: term()
  defp resolve_score(attrs) do
    # The iOS contract sends pair similarity as "similarity" (0..1) or
    # "distance" (0..1, lower is closer). Map either onto the stored "score".
    score = fetch_value(attrs, :score)
    similarity = fetch_value(attrs, :similarity)
    distance = fetch_value(attrs, :distance)

    cond do
      present?(score) -> score
      present?(similarity) -> similarity
      is_number(distance) -> max(0.0, 1.0 - distance * 1.0)
      true -> nil
    end
  end

  defp present?(nil), do: false
  defp present?(_), do: true

  @spec fetch_value(map(), atom()) :: term()
  defp fetch_value(attrs, key) when is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  @spec encode_rgb_payload(term()) :: String.t() | term()
  defp encode_rgb_payload(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} ->
        case normalize_rgb(decoded) do
          {:ok, rgb} -> Jason.encode!(rgb)
          :error -> decoded
        end

      {:error, _reason} ->
        value
    end
  end

  defp encode_rgb_payload(value) do
    case normalize_rgb(value) do
      {:ok, rgb} -> Jason.encode!(rgb)
      :error -> value
    end
  end

  @spec normalize_rgb(term()) :: {:ok, [number()]} | :error
  defp normalize_rgb([r, g, b])
       when is_number(r) and is_number(g) and is_number(b),
       do: {:ok, [r, g, b]}

  defp normalize_rgb(%{"r" => r, "g" => g, "b" => b})
       when is_number(r) and is_number(g) and is_number(b),
       do: {:ok, [r, g, b]}

  defp normalize_rgb(%{r: r, g: g, b: b})
       when is_number(r) and is_number(g) and is_number(b),
       do: {:ok, [r, g, b]}

  defp normalize_rgb(_value), do: :error

  @spec persist([map()], [map()]) ::
          {:ok,
           %{measurements: [CapturePatchMeasurement.t()], pair_scores: [CapturePairScore.t()]}}
          | {:error, {:invalid_rows, invalid_rows()}}
  defp persist(prepared_measurements, prepared_pair_scores) do
    invalid_rows = %{
      measurements: collect_invalid_rows(prepared_measurements),
      pair_scores: collect_invalid_rows(prepared_pair_scores)
    }

    if invalid_rows.measurements == [] and invalid_rows.pair_scores == [] do
      do_persist(prepared_measurements, prepared_pair_scores)
    else
      {:error, {:invalid_rows, invalid_rows}}
    end
  end

  @spec collect_invalid_rows([map()]) :: [invalid_row()]
  defp collect_invalid_rows(prepared_rows) do
    prepared_rows
    |> Enum.flat_map(fn prepared_row ->
      if prepared_row.changeset.valid? do
        []
      else
        [
          %{
            index: prepared_row.index,
            identifier: prepared_row.identifier,
            errors: changeset_errors(prepared_row.changeset)
          }
        ]
      end
    end)
  end

  @spec do_persist([map()], [map()]) ::
          {:ok,
           %{measurements: [CapturePatchMeasurement.t()], pair_scores: [CapturePairScore.t()]}}
  defp do_persist(prepared_measurements, prepared_pair_scores) do
    capture_id = capture_id_from_rows(prepared_measurements, prepared_pair_scores)

    multi =
      Multi.new()
      |> upsert_measurements(prepared_measurements)
      |> upsert_pair_scores(prepared_pair_scores)
      |> Multi.run(:measurements, fn _repo, _changes -> {:ok, load_measurements(capture_id)} end)
      |> Multi.run(:pair_scores, fn _repo, _changes -> {:ok, load_pair_scores(capture_id)} end)

    {:ok, %{measurements: measurements, pair_scores: pair_scores}} = Repo.transaction(multi)
    {:ok, %{measurements: measurements, pair_scores: pair_scores}}
  end

  @spec upsert_measurements(Ecto.Multi.t(), [map()]) :: Ecto.Multi.t()
  defp upsert_measurements(multi, []), do: multi

  defp upsert_measurements(multi, prepared_measurements) do
    rows =
      Enum.map(
        prepared_measurements,
        &insertable_attrs(&1.changeset, [
          :capture_id,
          :patch_id,
          :linear_rgb_median,
          :normalized_linear_rgb_median,
          :sample_count,
          :clipping_fraction,
          :mean,
          :standard_deviation
        ])
      )

    Multi.insert_all(
      multi,
      :upsert_measurements,
      CapturePatchMeasurement,
      rows,
      conflict_target: [:capture_id, :patch_id],
      on_conflict: {:replace, measurement_updatable_fields()},
      returning: false
    )
  end

  @spec upsert_pair_scores(Ecto.Multi.t(), [map()]) :: Ecto.Multi.t()
  defp upsert_pair_scores(multi, []), do: multi

  defp upsert_pair_scores(multi, prepared_pair_scores) do
    rows =
      Enum.map(
        prepared_pair_scores,
        &insertable_attrs(&1.changeset, [
          :capture_id,
          :pair_id,
          :algorithm_version,
          :score
        ])
      )

    Multi.insert_all(
      multi,
      :upsert_pair_scores,
      CapturePairScore,
      rows,
      conflict_target: [:capture_id, :pair_id, :algorithm_version],
      on_conflict: {:replace, [:score, :updated_at]},
      returning: false
    )
  end

  @spec insertable_attrs(Ecto.Changeset.t(), [atom()]) :: map()
  defp insertable_attrs(changeset, fields) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(fields)
    |> Map.put(:inserted_at, timestamp)
    |> Map.put(:updated_at, timestamp)
  end

  @spec measurement_updatable_fields() :: [atom()]
  defp measurement_updatable_fields do
    [
      :linear_rgb_median,
      :normalized_linear_rgb_median,
      :sample_count,
      :clipping_fraction,
      :mean,
      :standard_deviation,
      :updated_at
    ]
  end

  @spec capture_id_from_rows([map()], [map()]) :: integer()
  defp capture_id_from_rows([first | _rest], _pair_scores),
    do: Ecto.Changeset.get_field(first.changeset, :capture_id)

  defp capture_id_from_rows([], [first | _rest]),
    do: Ecto.Changeset.get_field(first.changeset, :capture_id)

  @spec load_measurements(integer()) :: [CapturePatchMeasurement.t()]
  defp load_measurements(capture_id) do
    from(measurement in CapturePatchMeasurement,
      where: measurement.capture_id == ^capture_id,
      order_by: [asc: measurement.patch_id]
    )
    |> Repo.all()
  end

  @spec load_pair_scores(integer()) :: [CapturePairScore.t()]
  defp load_pair_scores(capture_id) do
    from(pair_score in CapturePairScore,
      where: pair_score.capture_id == ^capture_id,
      order_by: [asc: pair_score.pair_id, asc: pair_score.algorithm_version]
    )
    |> Repo.all()
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

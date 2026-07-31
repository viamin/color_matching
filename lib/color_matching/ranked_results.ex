defmodule ColorMatching.RankedResults do
  @moduledoc """
  Aggregates pair scores and finding observations across every capture of a
  test sheet into a deterministic, ranked list of results.

  Ranking orders pairs by descending aggregate (mean) pair score, with stable
  tie-breaks so identical inputs always produce identical ordering. Pairs
  without any scored capture sort last, and pairs that were scored but never
  judged stay distinguishable from pairs explicitly judged `no_match`.
  """

  alias ColorMatching.Persistence

  alias ColorMatching.Persistence.{
    Capture,
    CapturePairScore,
    PairFinding,
    PairFindingObservation,
    TestSheet
  }

  @score_precision 6
  @min_datetime ~U[0001-01-01 00:00:00Z]

  defmodule Score do
    @moduledoc false

    @type t :: %__MODULE__{
            average: float() | nil,
            latest: float() | nil,
            minimum: float() | nil,
            maximum: float() | nil,
            capture_count: non_neg_integer(),
            sample_count: non_neg_integer(),
            algorithm_versions: [String.t()]
          }

    defstruct [
      :average,
      :latest,
      :minimum,
      :maximum,
      :capture_count,
      :sample_count,
      :algorithm_versions
    ]
  end

  defmodule LatestObservation do
    @moduledoc false

    @type t :: %__MODULE__{judgment: String.t(), observed_at: DateTime.t()}

    defstruct [:judgment, :observed_at]
  end

  defmodule Pair do
    @moduledoc false

    @type t :: %__MODULE__{
            rank: pos_integer(),
            pair_id: String.t(),
            algorithm_version: String.t() | nil,
            row: integer() | nil,
            col: integer() | nil,
            color_a_hex: String.t() | nil,
            color_b_hex: String.t() | nil,
            score: ColorMatching.RankedResults.Score.t(),
            current_judgment: String.t() | nil,
            current_judgment_observed_at: DateTime.t() | nil,
            observation_count: non_neg_integer(),
            latest_observation: ColorMatching.RankedResults.LatestObservation.t() | nil,
            latest_capture_at: DateTime.t() | nil,
            earliest_capture_at: DateTime.t() | nil
          }

    defstruct [
      :rank,
      :pair_id,
      :algorithm_version,
      :row,
      :col,
      :color_a_hex,
      :color_b_hex,
      :score,
      :current_judgment,
      :current_judgment_observed_at,
      :observation_count,
      :latest_observation,
      :latest_capture_at,
      :earliest_capture_at
    ]
  end

  @type t :: %__MODULE__{
          results: [Pair.t()],
          capture_count: non_neg_integer(),
          latest_capture_at: DateTime.t() | nil,
          earliest_capture_at: DateTime.t() | nil,
          algorithm_versions: [String.t()]
        }

  defstruct [
    :results,
    :capture_count,
    :latest_capture_at,
    :earliest_capture_at,
    :algorithm_versions
  ]

  @spec for_sheet(TestSheet.t()) :: t()
  def for_sheet(%TestSheet{} = sheet) do
    build(%{
      sheet: sheet,
      captures: Persistence.list_captures_for_sheet(sheet.id),
      pair_scores: Persistence.list_pair_scores_for_sheet(sheet.id),
      findings: Persistence.list_pair_findings_for_sheet(sheet.id),
      observations: Persistence.list_pair_finding_observations_for_sheet(sheet.id)
    })
  end

  @spec build(%{
          required(:sheet) => TestSheet.t(),
          required(:captures) => [Capture.t()],
          required(:pair_scores) => [CapturePairScore.t()],
          required(:findings) => [PairFinding.t()],
          required(:observations) => [PairFindingObservation.t()]
        }) :: t()
  def build(%{
        sheet: sheet,
        captures: captures,
        pair_scores: pair_scores,
        findings: findings,
        observations: observations
      }) do
    indexes = %{
      captures: Map.new(captures, &{&1.id, &1}),
      scores: Enum.group_by(pair_scores, & &1.pair_id),
      findings: Map.new(findings, &{&1.pair_id, &1}),
      observations: Enum.group_by(observations, & &1.pair_id)
    }

    results =
      sheet.pairs
      |> Enum.flat_map(&build_pair_results(&1, indexes))
      |> rank()

    %__MODULE__{
      results: results,
      capture_count: length(captures),
      latest_capture_at: boundary_timestamp(captures, &max_timestamp/1),
      earliest_capture_at: boundary_timestamp(captures, &min_timestamp/1),
      algorithm_versions: distinct_algorithm_versions(pair_scores)
    }
  end

  defp build_pair_results(pair, indexes) do
    scores = Map.get(indexes.scores, pair.pair_id, [])

    case Enum.group_by(scores, & &1.algorithm_version) do
      grouped_scores when map_size(grouped_scores) > 0 ->
        grouped_scores
        |> Enum.sort_by(fn {algorithm_version, _scores} -> algorithm_version end)
        |> Enum.map(fn {algorithm_version, version_scores} ->
          build_pair_result(pair, algorithm_version, version_scores, indexes)
        end)

      _empty ->
        [build_pair_result(pair, nil, [], indexes)]
    end
  end

  defp build_pair_result(pair, algorithm_version, scores, indexes) do
    observations = Map.get(indexes.observations, pair.pair_id, [])
    finding = Map.get(indexes.findings, pair.pair_id)

    %Pair{
      pair_id: pair.pair_id,
      algorithm_version: algorithm_version,
      row: pair.row,
      col: pair.col,
      color_a_hex: pair.color_a_hex,
      color_b_hex: pair.color_b_hex,
      score: aggregate_score(scores, indexes.captures),
      current_judgment: finding && finding.current_judgment,
      current_judgment_observed_at: finding && finding.current_observed_at,
      observation_count: length(observations),
      latest_observation: latest_observation(observations),
      latest_capture_at: capture_boundary(scores, indexes.captures, &max_timestamp/1),
      earliest_capture_at: capture_boundary(scores, indexes.captures, &min_timestamp/1)
    }
  end

  defp aggregate_score([], _captures_by_id), do: empty_score()

  defp aggregate_score(scores, captures_by_id) do
    values = Enum.map(scores, & &1.score)

    %Score{
      average: round_value(average(values)),
      latest: latest_score(scores, captures_by_id),
      minimum: round_value(Enum.min(values)),
      maximum: round_value(Enum.max(values)),
      capture_count: distinct_capture_count(scores),
      sample_count: length(scores),
      algorithm_versions: scores |> Enum.map(& &1.algorithm_version) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp empty_score do
    %Score{
      average: nil,
      latest: nil,
      minimum: nil,
      maximum: nil,
      capture_count: 0,
      sample_count: 0,
      algorithm_versions: []
    }
  end

  defp latest_score(scores, captures_by_id) do
    scores
    |> Enum.max_by(&score_capture_rank(&1, captures_by_id), fn -> nil end)
    |> case do
      nil -> nil
      score -> round_value(score.score)
    end
  end

  defp score_capture_rank(score, captures_by_id) do
    timestamp =
      captures_by_id
      |> Map.get(score.capture_id)
      |> capture_timestamp()

    {timestamp || @min_datetime, score.capture_id}
  end

  defp latest_observation([]), do: nil

  defp latest_observation(observations) do
    observation = Enum.max_by(observations, &{&1.observed_at, &1.id})

    %LatestObservation{judgment: observation.judgment, observed_at: observation.observed_at}
  end

  defp capture_boundary([], _captures_by_id, _chooser), do: nil

  defp capture_boundary(scores, captures_by_id, chooser) do
    timestamps =
      scores
      |> Enum.map(&capture_timestamp(Map.get(captures_by_id, &1.capture_id)))
      |> Enum.reject(&is_nil/1)

    case timestamps do
      [] -> nil
      _ -> chooser.(timestamps)
    end
  end

  defp capture_timestamp(nil), do: nil
  defp capture_timestamp(%Capture{} = capture), do: capture.timestamp || capture.inserted_at

  defp boundary_timestamp([], _chooser), do: nil

  defp boundary_timestamp(captures, chooser) do
    captures
    |> Enum.map(&capture_timestamp/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      timestamps -> chooser.(timestamps)
    end
  end

  defp max_timestamp(timestamps), do: Enum.max(timestamps, DateTime)
  defp min_timestamp(timestamps), do: Enum.min(timestamps, DateTime)

  defp distinct_algorithm_versions(pair_scores) do
    pair_scores
    |> Enum.map(& &1.algorithm_version)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp distinct_capture_count(scores) do
    scores |> Enum.map(& &1.capture_id) |> Enum.uniq() |> length()
  end

  defp average(values), do: Enum.sum(values) / length(values)

  defp round_value(nil), do: nil
  defp round_value(value), do: Float.round(value * 1.0, @score_precision)

  defp rank(pairs) do
    pairs
    |> Enum.sort_by(&rank_key/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {pair, rank} -> %Pair{pair | rank: rank} end)
  end

  defp rank_key(%Pair{
         score: %Score{average: average, latest: latest},
         pair_id: pair_id,
         algorithm_version: algorithm_version
       }) do
    has_score = if average == nil, do: 0, else: 1
    {-has_score, -(average || 0.0), -(latest || 0.0), pair_id, algorithm_version || ""}
  end
end

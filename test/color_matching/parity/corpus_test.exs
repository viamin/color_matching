defmodule ColorMatching.Parity.CorpusTest do
  @moduledoc """
  Replays the committed golden-vector corpus through the Elixir solver and
  asserts exact agreement.

  The corpus is the parity contract shared with ColorMatching-macOS: any
  change in missing-measurement exclusion, tie-breaking, or channel
  weighting shows up here as a mismatch and requires bumping
  `ColorMatching.Parity.Corpus.algorithm_version/0` and regenerating.
  """

  use ExUnit.Case, async: true

  alias ColorMatching.IlluminantMatching
  alias ColorMatching.Parity.Corpus
  alias ColorMatching.ResponseVector

  @corpus_path Corpus.output_path()

  describe "committed corpus fixture" do
    test "exists and is stamped with the current algorithm version" do
      corpus = decode_corpus()

      assert corpus["algorithm_version"] == Corpus.algorithm_version()
      assert corpus["scorer"] == "ColorMatching.WeightedSquaredError"
      assert corpus["selection"] == "earliest-index-wins"
      assert corpus["light_sources"] == ~w(white red green blue lps)
    end

    test "byte-matches a fresh deterministic generation" do
      assert File.exists?(@corpus_path),
             "parity corpus is missing at #{@corpus_path}; run `mix parity.generate`"

      assert File.read!(@corpus_path) == Corpus.encode()
    end

    test "contains intentionally tied scenarios" do
      scenarios = decode_corpus()["scenarios"]

      tied_scenarios = Enum.count(scenarios, & &1["expected"]["tie_broke"])
      null_selections = Enum.count(scenarios, &is_nil(&1["expected"]["selected_index"]))

      assert tied_scenarios >= 1
      assert null_selections >= 1
    end
  end

  describe "scenario replay" do
    for scenario <- Corpus.scenarios() do
      @tag scenario: scenario.id
      test "replays #{scenario.id} with exact agreement" do
        run_scenario_and_assert(find_decoded!(unquote(scenario.id)))
      end
    end
  end

  defp decode_corpus do
    assert File.exists?(@corpus_path),
           "parity corpus is missing at #{@corpus_path}; run `mix parity.generate`"

    @corpus_path |> File.read!() |> Jason.decode!()
  end

  defp find_decoded!(id) do
    Enum.find(decode_corpus()["scenarios"], &(&1["id"] == id)) ||
      flunk("scenario #{inspect(id)} missing from committed corpus")
  end

  defp run_scenario_and_assert(scenario) do
    weights = decode_weights(scenario["weights"])
    target = decode_vector(scenario["target"])
    vectors = scenario["palette"] |> Enum.sort_by(& &1["index"]) |> Enum.map(&decode_vector/1)

    scored = IlluminantMatching.score_candidates(vectors, target, weights)
    best = IlluminantMatching.best_match(vectors, target, weights)
    expected = scenario["expected"]

    assert_scores(scored, expected["scores"], scenario["id"])
    assert_selection(best, expected, vectors, scenario["id"])
    assert_tie_evidence(scored, best, expected)
  end

  defp assert_scores(scored, expected_scores, scenario_id) do
    assert length(scored) == length(expected_scores), scenario_id

    Enum.zip(scored, Enum.sort_by(expected_scores, & &1["index"]))
    |> Enum.each(fn {{_vector, score}, expected} ->
      case expected["score"] do
        "excluded" ->
          assert score == :excluded, scenario_id

        error when is_float(error) ->
          assert score == error, "#{scenario_id}: #{score} != #{error}"
      end
    end)
  end

  defp assert_selection(best, expected, vectors, scenario_id) do
    case expected["selected_index"] do
      nil ->
        assert best == nil, "#{scenario_id}: expected no selection, got #{inspect(best)}"

      selected_index ->
        assert {%ResponseVector{} = selected, error} = best, scenario_id

        assert selected == Enum.at(vectors, selected_index),
               "#{scenario_id}: selected vector is not at expected index #{selected_index}"

        assert selected.hex_color == expected["selected_hex_color"], scenario_id
        assert error == expected["error"], scenario_id
    end
  end

  defp assert_tie_evidence(scored, best, expected) do
    case best do
      nil ->
        assert expected["tie_broke"] == nil
        assert expected["tied_indices"] == []

      {_vector, error} ->
        assert_ties_for_selection(scored, expected, error)
    end
  end

  defp assert_ties_for_selection(scored, expected, error) do
    recomputed_ties = recomputed_tied_indices(scored, error)

    assert expected["tied_indices"] == recomputed_ties
    assert expected["tie_broke"] == length(recomputed_ties) > 1
    assert hd(recomputed_ties) == expected["selected_index"]
  end

  defp recomputed_tied_indices(scored, error) do
    scored
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_vector, score}, index} ->
      if score == error, do: [index], else: []
    end)
    |> Enum.sort()
  end

  defp decode_weights(encoded) do
    known = MapSet.new(ResponseVector.light_sources(), &Atom.to_string/1)

    Map.new(encoded, fn {source, weight} ->
      key = if source in known, do: String.to_existing_atom(source), else: source
      {key, weight}
    end)
  end

  defp decode_vector(encoded) do
    brightnesses =
      Map.new(ResponseVector.light_sources(), fn source ->
        {source, Map.get(encoded["channels"], Atom.to_string(source), :missing)}
      end)

    %ResponseVector{
      hex_color: encoded["hex_color"],
      printer_profile_id: "parity-corpus-replay",
      missing?: Enum.any?(Map.values(brightnesses), &(&1 == :missing)),
      white: brightnesses.white,
      red: brightnesses.red,
      green: brightnesses.green,
      blue: brightnesses.blue,
      lps: brightnesses.lps
    }
  end
end

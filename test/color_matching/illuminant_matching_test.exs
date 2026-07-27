defmodule ColorMatching.IlluminantMatchingTest do
  use ExUnit.Case, async: true

  alias ColorMatching.IlluminantMatching
  alias ColorMatching.ResponseVector
  alias ColorMatching.TestSupport.ConstantScorer
  alias ColorMatching.WeightedSquaredError

  @weights %{white: 0.5, red: 1.0, green: 1.0, blue: 0.0, lps: 1.5}

  describe "best_match/4" do
    test "returns the candidate with the lowest weighted squared error" do
      target = vector("#000000", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5)

      close = vector("#112233", white: 0.75, red: 0.25, green: 0.65, blue: 0.15, lps: 0.45)
      exact = vector("#222222", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5)
      far = vector("#FF0000", white: 0.0, red: 0.0, green: 0.0, blue: 0.0, lps: 0.0)

      assert {matched, 0.0} =
               IlluminantMatching.best_match([close, exact, far], target, @weights)

      assert matched == exact
    end

    test "is deterministic when multiple candidates tie" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      first = vector("#AAAAAA", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      second = vector("#BBBBBB", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      third = vector("#CCCCCC", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      assert {winner, 0.0} =
               IlluminantMatching.best_match([first, second, third], target, @weights)

      assert winner.hex_color == "#AAAAAA"
    end

    test "excludes candidates missing any positive-weight light source" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      scorable = vector("#AAAAAA", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      missing = vector("#BBBBBB", white: 0.5, red: :missing, green: 0.5, blue: 0.5, lps: 0.5)

      assert {winner, 0.0} =
               IlluminantMatching.best_match([missing, scorable], target, @weights)

      assert winner.hex_color == "#AAAAAA"
    end

    test "returns nil when every candidate is excluded" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      first = vector("#AAAAAA", white: :missing, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      second = vector("#BBBBBB", white: 0.5, red: :missing, green: 0.5, blue: 0.5, lps: 0.5)

      assert IlluminantMatching.best_match([first, second], target, @weights) == nil
    end

    test "returns nil when no candidates are supplied" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      assert IlluminantMatching.best_match([], target, @weights) == nil
    end

    test "honors a custom scoring module" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      candidate = vector("#FFFFFF", white: 1.0, red: 1.0, green: 1.0, blue: 1.0, lps: 1.0)

      assert {^candidate, :custom_score} =
               IlluminantMatching.best_match([candidate], target, @weights, ConstantScorer)
    end
  end

  describe "score_candidates/4" do
    test "returns a scored tuple for every candidate including excluded ones" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      scorable = vector("#AAAAAA", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      missing = vector("#BBBBBB", white: 0.5, red: :missing, green: 0.5, blue: 0.5, lps: 0.5)

      assert [
               {%ResponseVector{hex_color: "#AAAAAA"}, 0.0},
               {%ResponseVector{hex_color: "#BBBBBB"}, :excluded}
             ] = IlluminantMatching.score_candidates([scorable, missing], target, @weights)
    end

    test "uses the default scorer when none is supplied" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      candidate = vector("#FFFFFF", white: 1.0, red: 1.0, green: 1.0, blue: 1.0, lps: 1.0)

      assert [
               {%ResponseVector{}, score}
             ] = IlluminantMatching.score_candidates([candidate], target, @weights)

      # Score matches what the default WeightedSquaredError scorer would compute.
      assert score == WeightedSquaredError.score(candidate, target, @weights)
    end
  end

  defp vector(hex_color, brightnesses) do
    %ResponseVector{
      hex_color: hex_color,
      printer_profile_id: "profile-test",
      measured_at: nil,
      inserted_at: nil,
      missing?: false,
      white: Keyword.get(brightnesses, :white, :missing),
      red: Keyword.get(brightnesses, :red, :missing),
      green: Keyword.get(brightnesses, :green, :missing),
      blue: Keyword.get(brightnesses, :blue, :missing),
      lps: Keyword.get(brightnesses, :lps, :missing)
    }
  end
end

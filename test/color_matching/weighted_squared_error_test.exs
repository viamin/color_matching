defmodule ColorMatching.WeightedSquaredErrorTest do
  use ExUnit.Case, async: true

  alias ColorMatching.IlluminantScoring
  alias ColorMatching.ResponseVector
  alias ColorMatching.WeightedSquaredError

  @weights %{white: 0.5, red: 1.0, green: 1.0, blue: 0.0, lps: 1.5}

  describe "score/3" do
    test "computes weighted squared error over positive-weight light sources" do
      target = vector("#000000", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: 0.1, green: 0.4, blue: 0.0, lps: 0.3)

      # (0.5-0.8)^2 * 0.5 + (0.1-0.2)^2 * 1.0 + (0.4-0.7)^2 * 1.0 + (0.3-0.5)^2 * 1.5
      # = 0.045 + 0.01 + 0.09 + 0.06 = 0.205
      assert_in_delta WeightedSquaredError.score(candidate, target, @weights), 0.205, 1.0e-9
    end

    test "returns 0.0 for an exact match" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      assert WeightedSquaredError.score(candidate, target, @weights) == 0.0
    end

    test "ignores light sources with weight 0" do
      weights = %{white: 1.0, red: 0.0, green: 0.0, blue: 0.0, lps: 0.0}

      target = vector("#000000", white: 0.5, red: 0.0, green: 0.0, blue: 0.0, lps: 0.0)
      candidate = vector("#FFFFFF", white: 0.5, red: 1.0, green: 1.0, blue: 1.0, lps: 1.0)

      assert WeightedSquaredError.score(candidate, target, weights) == 0.0
    end

    test "ignores light sources with negative weight" do
      weights = %{white: 1.0, red: -1.0, green: 0.0, blue: 0.0, lps: 0.0}

      target = vector("#000000", white: 0.5, red: 0.0, green: 0.0, blue: 0.0, lps: 0.0)
      candidate = vector("#FFFFFF", white: 0.5, red: 1.0, green: 0.0, blue: 0.0, lps: 0.0)

      assert WeightedSquaredError.score(candidate, target, weights) == 0.0
    end

    test "excludes candidates missing any positive-weight light source" do
      target = vector("#000000", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: :missing, green: 0.4, blue: 0.0, lps: 0.3)

      assert WeightedSquaredError.score(candidate, target, @weights) == :excluded
    end

    test "does not exclude a candidate when missing only zero-weight light sources" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      candidate =
        vector("#FF0000", white: 0.5, red: 0.5, green: 0.5, blue: :missing, lps: 0.5)

      assert WeightedSquaredError.score(candidate, target, @weights) == 0.0
    end

    test "treats missing values as zero when exclude_when_missing is false" do
      target = vector("#000000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: 0.0, green: 0.5, blue: 0.5, lps: 0.5)

      # Without exclude_when_missing, red is treated as 0; (0.0-0.5)^2 * 1.0 = 0.25
      assert_in_delta(
        WeightedSquaredError.score(candidate, target, @weights, exclude_when_missing: false),
        0.25,
        1.0e-9
      )
    end

    test "falls back to zero brightness for missing values on the target when relaxed" do
      target = vector("#000000", white: 0.5, red: :missing, green: 0.5, blue: 0.5, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: 0.5, green: 0.5, blue: 0.5, lps: 0.5)

      # With exclude_when_missing disabled, missing target is treated as 0;
      # (0.5-0)^2 * 1.0 = 0.25.
      assert_in_delta(
        WeightedSquaredError.score(candidate, target, @weights, exclude_when_missing: false),
        0.25,
        1.0e-9
      )
    end

    test "is deterministic across repeated calls" do
      target = vector("#000000", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5)
      candidate = vector("#FF0000", white: 0.5, red: 0.1, green: 0.4, blue: 0.0, lps: 0.3)

      first = WeightedSquaredError.score(candidate, target, @weights)
      second = WeightedSquaredError.score(candidate, target, @weights)
      third = WeightedSquaredError.score(candidate, target, @weights)

      assert first == second
      assert second == third
    end
  end

  describe "IlluminantScoring behaviour" do
    test "implements the IlluminantScoring behaviour" do
      assert IlluminantScoring.impl?(WeightedSquaredError)
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
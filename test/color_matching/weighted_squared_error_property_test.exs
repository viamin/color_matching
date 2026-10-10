defmodule ColorMatching.WeightedSquaredErrorPropertyTest do
  @moduledoc """
  StreamData property tests for the solver invariants that the parity
  corpus pins down contractually:

    * missing measurements are excluded, never treated as zero brightness
    * earliest-wins tie-breaking is deterministic
    * channel weights scale errors as expected
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ColorMatching.IlluminantMatching
  alias ColorMatching.ResponseVector
  alias ColorMatching.WeightedSquaredError

  @light_sources ResponseVector.light_sources()

  property "candidates or targets missing a positive-weight channel are excluded" do
    check all(
            target <- response_vector_gen(),
            candidate <- response_vector_gen(),
            weights <- weights_gen(),
            source <- member_of(@light_sources),
            weight <- float(min: 0.01, max: 3.0)
          ) do
      weights = Map.put(weights, source, weight)

      candidate_missing = put_channel(candidate, source, :missing)
      target_missing = put_channel(target, source, :missing)

      assert WeightedSquaredError.score(candidate_missing, target, weights) == :excluded
      assert WeightedSquaredError.score(candidate, target_missing, weights) == :excluded
    end
  end

  property "missing measurements are never scored as zero brightness under the default policy" do
    check all(
            other_brightness <- brightness_gen(),
            candidate_brightness <- brightness_gen(),
            target_brightness <- brightness_gen(),
            source <- member_of(@light_sources),
            weight <- float(min: 0.01, max: 3.0)
          ) do
      weights = %{source => weight}

      target = full_vector("#TARGET", &{&1, target_brightness})

      candidate_missing =
        full_vector("#MISSING", fn s -> {s, other_brightness} end)
        |> put_channel(source, :missing)

      candidate_zero =
        full_vector("#MISSING", fn s -> {s, candidate_brightness} end)
        |> put_channel(source, 0.0)

      # Default policy: the missing channel excludes the candidate outright.
      assert WeightedSquaredError.score(candidate_missing, target, weights) == :excluded

      # The same vector with a measured zero is scorable, proving missing
      # is not silently coerced to 0.0.
      assert is_float(WeightedSquaredError.score(candidate_zero, target, weights))

      # Only the opt-in relaxation treats missing as zero, and then it
      # agrees bit-for-bit with the measured-zero vector.
      relaxed =
        WeightedSquaredError.score(candidate_missing, target, weights,
          exclude_when_missing: false
        )

      assert relaxed == WeightedSquaredError.score(candidate_zero, target, weights)
    end
  end

  property "best_match deterministically selects the earliest candidate with the minimum score" do
    check all(
            palette <- list_of(response_vector_gen(), min_length: 1, max_length: 15),
            target <- response_vector_gen(),
            weights <- weights_gen()
          ) do
      assert IlluminantMatching.best_match(palette, target, weights) ==
               IlluminantMatching.best_match(palette, target, weights)

      expected = earliest_minimum(palette, target, weights)
      actual = IlluminantMatching.best_match(palette, target, weights)

      case expected do
        nil ->
          assert actual == nil

        index ->
          {vector, score} = actual
          assert vector == Enum.at(palette, index)
          assert score == WeightedSquaredError.score(vector, target, weights)
      end
    end
  end

  property "a single-channel weight scales that channel's squared error exactly" do
    check all(
            candidate <- full_vector_gen(),
            target <- full_vector_gen(),
            source <- member_of(@light_sources),
            weight <- float(min: 0.01, max: 3.0)
          ) do
      diff = ResponseVector.value(candidate, source) - ResponseVector.value(target, source)

      assert WeightedSquaredError.score(candidate, target, %{source => weight}) ==
               diff * diff * weight
    end
  end

  property "doubling every weight exactly doubles the total error" do
    check all(
            candidate <- full_vector_gen(),
            target <- full_vector_gen(),
            weights <- weights_gen()
          ) do
      base = WeightedSquaredError.score(candidate, target, weights)
      doubled_weights = Map.new(weights, fn {source, weight} -> {source, 2 * weight} end)
      doubled = WeightedSquaredError.score(candidate, target, doubled_weights)

      assert doubled == 2.0 * base
    end
  end

  property "scores are non-negative floats or :excluded" do
    check all(
            candidate <- response_vector_gen(),
            target <- response_vector_gen(),
            weights <- weights_gen()
          ) do
      score = WeightedSquaredError.score(candidate, target, weights)

      assert score == :excluded or (is_float(score) and score >= 0.0)
    end
  end

  ## Helpers

  defp put_channel(vector, source, value), do: %{vector | source => value}

  ## Reference implementation of the documented selection contract

  defp earliest_minimum(palette, target, weights) do
    palette
    |> Enum.with_index()
    |> Enum.map(fn {vector, index} ->
      {index, WeightedSquaredError.score(vector, target, weights)}
    end)
    |> Enum.reject(fn {_index, score} -> score == :excluded end)
    |> Enum.min_by(fn {_index, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {index, _score} -> index
    end
  end

  ## Generators

  defp brightness_gen, do: float(min: 0.0, max: 1.0)

  defp channel_gen do
    one_of([brightness_gen(), constant(:missing)])
  end

  defp response_vector_gen(hex \\ "#000000") do
    gen all(
          white <- channel_gen(),
          red <- channel_gen(),
          green <- channel_gen(),
          blue <- channel_gen(),
          lps <- channel_gen()
        ) do
      %ResponseVector{
        hex_color: hex,
        printer_profile_id: "property-test",
        white: white,
        red: red,
        green: green,
        blue: blue,
        lps: lps
      }
    end
  end

  defp full_vector_gen do
    gen all(
          white <- brightness_gen(),
          red <- brightness_gen(),
          green <- brightness_gen(),
          blue <- brightness_gen(),
          lps <- brightness_gen()
        ) do
      %ResponseVector{
        hex_color: "#000000",
        printer_profile_id: "property-test",
        white: white,
        red: red,
        green: green,
        blue: blue,
        lps: lps
      }
    end
  end

  defp full_vector(hex, channel_fun) do
    struct!(
      ResponseVector,
      [hex_color: hex, printer_profile_id: "property-test"] ++
        Enum.map(@light_sources, channel_fun)
    )
  end

  defp weights_gen do
    gen all(
          white <- weight_value_gen(),
          red <- weight_value_gen(),
          green <- weight_value_gen(),
          blue <- weight_value_gen(),
          lps <- weight_value_gen()
        ) do
      [white: white, red: red, green: green, blue: blue, lps: lps]
      |> Enum.reject(fn {_source, weight} -> is_nil(weight) end)
      |> Map.new()
    end
  end

  defp weight_value_gen do
    one_of([
      float(min: 0.0, max: 3.0),
      float(min: 0.01, max: 3.0),
      constant(nil)
    ])
  end
end

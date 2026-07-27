defmodule ColorMatching.WeightedSquaredError do
  @moduledoc """
  Weighted squared-error illuminant scoring.

  For each light source `s` with weight `w` where `w > 0`, this scorer
  computes `(candidate.s - target.s) ** 2 * w` and sums the per-source
  contributions. Light sources with weight `0` (or absent from the weights
   map) are ignored entirely — including for the purposes of the default
   exclusion policy.

  ## Missing-data policy

  By default, a candidate is excluded (returns `:excluded`) when any light
  source with weight greater than `0` is missing a measurement. The
  exclusion policy can be relaxed by passing
  `exclude_when_missing: false` to `score/4`, in which case missing
  measurements are treated as `0.0` for that source. This relaxation should
  be used with care because it makes missing and zero-brightness
  indistinguishable.

  ## Examples

      iex> weights = %{white: 0.5, red: 1.0, green: 1.0, blue: 0.0, lps: 1.5}
      iex> target = %ColorMatching.ResponseVector{hex_color: "#000000", printer_profile_id: "p", white: 0.8, red: 0.2, green: 0.7, blue: 0.1, lps: 0.5}
      iex> candidate = %ColorMatching.ResponseVector{hex_color: "#FF0000", printer_profile_id: "p", white: 0.5, red: 0.1, green: 0.4, blue: 0.0, lps: 0.3}
      iex> ColorMatching.WeightedSquaredError.score(candidate, target, weights)
      0.205
  """

  @behaviour ColorMatching.IlluminantScoring

  alias ColorMatching.IlluminantScoring
  alias ColorMatching.ResponseVector

  @typedoc """
  Options accepted by `score/4`.
  """
  @type option :: {:exclude_when_missing, boolean()}
  @type options :: [option()]

  @impl IlluminantScoring
  def score(candidate, target, weights), do: score(candidate, target, weights, [])

  @doc """
  Computes the weighted squared error with explicit options.

  This is the underlying function used by `score/3`.
  Exposed for callers that already manage their own options.
  """
  @spec score(
          ResponseVector.t(),
          ResponseVector.t(),
          IlluminantScoring.weights(),
          options()
        ) :: IlluminantScoring.score()
  def score(candidate, target, weights, options)
      when is_map(weights) do
    exclude_when_missing = Keyword.get(options, :exclude_when_missing, true)

    case exclude_candidate(candidate, weights, exclude_when_missing) do
      :excluded ->
        :excluded

      :scorable ->
        compute_squared_error(candidate, target, weights)
    end
  end

  defp exclude_candidate(_candidate, _weights, false), do: :scorable

  defp exclude_candidate(%ResponseVector{} = candidate, weights, true) do
    if any_required_missing?(candidate, weights) do
      :excluded
    else
      :scorable
    end
  end

  defp any_required_missing?(%ResponseVector{} = candidate, weights) do
    weights
    |> Map.to_list()
    |> Enum.any?(fn {source, weight} ->
      weight > 0 and ResponseVector.value(candidate, source) == :missing
    end)
  end

  defp compute_squared_error(candidate, target, weights) do
    weights
    |> Map.to_list()
    |> Enum.reduce(0.0, fn {source, weight}, acc ->
      if weight <= 0 do
        acc
      else
        candidate_value = candidate_brightness(candidate, source)
        target_value = target_brightness(target, source)
        diff = candidate_value - target_value
        acc + diff * diff * weight
      end
    end)
  end

  defp candidate_brightness(candidate, source) do
    case ResponseVector.value(candidate, source) do
      :missing -> 0.0
      value when is_number(value) -> value * 1.0
    end
  end

  defp target_brightness(target, source) do
    case ResponseVector.value(target, source) do
      :missing -> 0.0
      value when is_number(value) -> value * 1.0
    end
  end
end
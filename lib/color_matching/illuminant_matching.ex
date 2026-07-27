defmodule ColorMatching.IlluminantMatching do
  @moduledoc """
  Find the printable color whose illuminant response vector best matches a
  target vector under a configurable scoring strategy.

  The scorer is a module that implements `ColorMatching.IlluminantScoring`.
  The default is `ColorMatching.WeightedSquaredError`, which excludes
  candidates that are missing any measurement with weight greater than `0`.
  """

  alias ColorMatching.IlluminantScoring
  alias ColorMatching.ResponseVector
  alias ColorMatching.WeightedSquaredError

  @default_scorer WeightedSquaredError

  @doc """
  Returns the response vector in `candidates` with the lowest score under
  `scoring_module`.

  Candidates whose score is `:excluded` are filtered out before selecting the
  best match. Returns `nil` when no candidates are scorable.

  Ties are broken by the candidate's position in `candidates` (earlier wins)
  so that the best match is deterministic for a given input order.
  """
  @spec best_match(
          [ResponseVector.t()],
          ResponseVector.t(),
          IlluminantScoring.weights(),
          module()
        ) :: {ResponseVector.t(), IlluminantScoring.score()} | nil
  def best_match(candidates, target, weights, scoring_module \\ @default_scorer)

  def best_match(candidates, %ResponseVector{} = target, weights, scoring_module)
      when is_list(candidates) and is_map(weights) do
    candidates
    |> score_candidates(target, weights, scoring_module)
    |> Enum.reject(fn {_vector, score} -> score == :excluded end)
    |> Enum.min_by(fn {_vector, score} -> score end, fn -> nil end)
  end

  @doc """
  Scores every candidate and returns the result alongside the scorer used.

  Useful when callers want to inspect the full ranking rather than only the
  best match.
  """
  @spec score_candidates(
          [ResponseVector.t()],
          ResponseVector.t(),
          IlluminantScoring.weights(),
          module()
        ) :: [{ResponseVector.t(), IlluminantScoring.score()}]
  def score_candidates(candidates, target, weights, scoring_module \\ @default_scorer)

  def score_candidates(candidates, %ResponseVector{} = target, weights, scoring_module)
      when is_list(candidates) and is_map(weights) do
    Enum.map(candidates, &score_candidate(&1, target, weights, scoring_module))
  end

  defp score_candidate(%ResponseVector{} = candidate, target, weights, scoring_module) do
    {candidate, scoring_module.score(candidate, target, weights)}
  end
end
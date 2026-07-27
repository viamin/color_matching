defmodule ColorMatching.IlluminantScoring do
  @moduledoc """
  Behaviour for scoring an illuminant response vector against a target vector.

  Scoring functions operate on `ColorMatching.ResponseVector` values so the
  distance metric is decoupled from how vectors are constructed. The current
  default implementation is `ColorMatching.WeightedSquaredError`, but
  alternative distance functions (e.g. cosine similarity, perceptual
  difference) can be plugged in by implementing this behaviour and passing the
  module to `ColorMatching.IlluminantMatching`.
  """

  alias ColorMatching.ResponseVector

  @typedoc """
  Light source weights.

  Atom keys are matched against `ResponseVector.light_sources/0`. Sources
  with `0.0` weight still contribute to completeness checks in the default
  scoring policy but do not influence the numeric result.
  """
  @type weights :: %{optional(ResponseVector.light_source()) => number()}

  @typedoc """
  A score is either a finite float (lower is better) or `:excluded` when the
  candidate cannot be scored under the configured policy (e.g. missing
  measurements for any weighted light source).
  """
  @type score :: float() | :excluded

  @doc """
  Computes a score for `candidate` against `target` using `weights`.

  Returns `:excluded` when the scoring policy cannot rank the candidate
  (e.g. missing measurements for any weighted light source).
  """
  @callback score(ResponseVector.t(), ResponseVector.t(), weights()) :: score()
end

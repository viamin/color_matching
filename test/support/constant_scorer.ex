defmodule ColorMatching.TestSupport.ConstantScorer do
  @moduledoc false

  @behaviour ColorMatching.IlluminantScoring

  @impl ColorMatching.IlluminantScoring
  def score(_candidate, _target, _weights), do: 0.0
end

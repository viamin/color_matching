defmodule Mix.Tasks.Parity.Generate do
  @shortdoc "Generates the solver parity golden-vector corpus"

  @moduledoc """
  Generates the solver parity golden-vector corpus at `priv/parity/v1/corpus.json`.

  Runs the Elixir solver (`ColorMatching.WeightedSquaredError` plus the
  earliest-wins selection of `ColorMatching.IlluminantMatching`) over a
  deterministic scenario set and emits JSON fixtures containing palette
  response vectors, targets, weights, per-candidate scores, the expected
  selection, expected error, and tie-break evidence. ColorMatching-macOS
  replays the same corpus to keep its mirrored scorer in parity.

  Generation is deterministic: repeated runs produce byte-identical output.

  ## Usage

      mix parity.generate          # write the corpus fixture
      mix parity.generate --check  # fail if the committed fixture drifted

  Use `--check` to verify that the committed corpus still matches a fresh
  build (catches accidental algorithm drift or nondeterminism at the source).
  """

  use Mix.Task

  alias ColorMatching.Parity.Corpus

  @requirements ["app.config"]

  @switches [check: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("mix parity.generate accepts only the --check flag")
    end

    if opts[:check], do: verify(), else: generate()
  end

  defp generate do
    path = Corpus.write()
    scenario_count = length(Corpus.scenarios())

    Mix.shell().info("""
    Generated parity corpus v#{Corpus.algorithm_version()}
      scenarios: #{scenario_count}
      output:    #{path}
    """)
  end

  defp verify do
    case Corpus.check() do
      :ok ->
        Mix.shell().info("Parity corpus is up to date (v#{Corpus.algorithm_version()}).")

      {:missing, path} ->
        Mix.raise("""
        Parity corpus #{path} does not exist.
        Run `mix parity.generate` and commit the result.
        """)

      {:stale, path} ->
        Mix.raise("""
        Parity corpus #{path} does not match a fresh deterministic build.
        The solver's behavior changed (or generation is nondeterministic).
        Run `mix parity.generate`, review the diff, and commit the result.
        """)
    end
  end
end

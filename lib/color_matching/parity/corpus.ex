defmodule ColorMatching.Parity.Corpus do
  @moduledoc """
  Golden-vector corpus for client/server solver parity.

  The macOS app (ColorMatching-macOS, `WeightedSquaredErrorScorer`) mirrors
  this server's `ColorMatching.WeightedSquaredError` solver and the
  earliest-wins selection of `ColorMatching.IlluminantMatching`. The corpus
  produced here is the shared source of truth that both test suites replay
  so silent divergence (tie-breaking, missing-measurement exclusion, or
  channel weighting) is caught.

  The corpus is fully deterministic: `build/0` always yields the same value
  and `encode/1` therefore always emits identical bytes. Regenerate the
  committed fixture with `mix parity.generate`; CI verifies the committed
  bytes with `mix parity.generate --check`.

  `algorithm_version/0` must be bumped whenever scoring semantics change so
  consumers can detect that every expectation in the corpus moved.
  """

  alias ColorMatching.IlluminantMatching
  alias ColorMatching.ResponseVector

  @algorithm_version 1
  @corpus_dir "priv/parity/v1"
  @scorer ColorMatching.WeightedSquaredError

  @doc """
  Version of the coupled scorer/selection semantics captured by the corpus.
  """
  @spec algorithm_version() :: pos_integer()
  def algorithm_version, do: @algorithm_version

  @doc """
  Path of the committed corpus fixture for the current algorithm version.
  """
  @spec output_path() :: Path.t()
  def output_path, do: Application.app_dir(:color_matching, Path.join(@corpus_dir, "corpus.json"))

  @doc """
  Deterministic scenario definitions (inputs only, no expected results).
  """
  @spec scenarios() :: [map()]
  def scenarios do
    [
      scenario(
        "distinct-errors",
        "Four fully-measured candidates with strictly distinct errors; the clear best wins outright.",
        common_weights(),
        vector("#336699", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#A0522D", white: 0.375, red: 0.5, green: 0.375, blue: 0.25, lps: 0.125),
          vector("#556B2F", white: 0.75, red: 0.125, green: 0.75, blue: 0.0, lps: 0.5),
          vector("#708090", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.5),
          vector("#FFD700", white: 0.125, red: 0.625, green: 0.25, blue: 0.5, lps: 0.75)
        ]
      ),
      scenario(
        "tie-symmetric-around-target",
        "Candidates at indices 1 and 2 sit exactly +/-0.125 from the target on white and match the target elsewhere, producing an exact tie; the earlier index wins.",
        common_weights(),
        vector("#204060", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#111111", white: 0.875, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#222222", white: 0.375, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#333333", white: 0.625, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#444444", white: 0.25, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375)
        ]
      ),
      scenario(
        "tie-duplicate-vectors",
        "Candidates at indices 1 and 3 carry identical channel values (different hex colors), an exact tie; the earlier index wins.",
        common_weights(),
        vector("#000080", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#0B0B0B", white: 0.875, red: 0.625, green: 0.25, blue: 0.5, lps: 0.75),
          vector("#ABCDEF", white: 0.375, red: 0.375, green: 0.5, blue: 0.25, lps: 0.5),
          vector("#1E90FF", white: 0.75, red: 0.375, green: 0.5, blue: 0.25, lps: 0.5),
          vector("#FEDCBA", white: 0.375, red: 0.375, green: 0.5, blue: 0.25, lps: 0.5),
          vector("#98FB98", white: 0.25, red: 0.5, green: 0.375, blue: 0.0, lps: 0.125)
        ]
      ),
      scenario(
        "tie-three-way-on-lps",
        "Only lps is weighted; three candidates sit +/-0.125 from the target on lps and tie exactly; the earliest index wins even though a later duplicate matches it bit-for-bit.",
        %{lps: 1.5},
        vector("#5A5A5A", lps: 0.5),
        [
          vector("#111111", lps: 0.75),
          vector("#222222", lps: 0.375),
          vector("#333333", lps: 0.625),
          vector("#444444", lps: 0.375),
          vector("#555555", lps: 0.125)
        ]
      ),
      scenario(
        "missing-candidate-excluded",
        "The candidate at index 0 matches the target on every measured channel but is missing lps (positive weight), so it is excluded rather than treated as zero brightness; index 1 wins.",
        common_weights(),
        vector("#C0C0C0", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.0),
        [
          vector("#DEDEDE", white: 0.5, red: 0.25, green: 0.625, blue: 0.125),
          vector("#BFAFA0", white: 0.625, red: 0.375, green: 0.5, blue: 0.25, lps: 0.125),
          vector("#AFC0BF", white: 0.75, red: 0.5, green: 0.375, blue: 0.0, lps: 0.25)
        ]
      ),
      scenario(
        "missing-target-excluded",
        "The target itself is missing white (positive weight), so every candidate is excluded and no selection exists.",
        common_weights(),
        vector("#010101", red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#111111", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#222222", white: 0.375, red: 0.125, green: 0.5, blue: 0.0, lps: 0.25),
          vector("#333333", white: 0.625, red: 0.375, green: 0.75, blue: 0.25, lps: 0.5)
        ]
      ),
      scenario(
        "zero-weight-channel-missing",
        "blue has zero weight, so a candidate missing blue and a candidate with wildly different blue tie exactly: missing data on unweighted channels neither excludes nor contributes.",
        %{white: 1.0, blue: 0.0},
        vector("#0F0F0F", white: 0.5, blue: 0.5),
        [
          vector("#111111", white: 0.75),
          vector("#222222", white: 0.75, blue: 0.9375),
          vector("#333333", white: 1.0, blue: 0.0625)
        ]
      ),
      scenario(
        "all-excluded",
        "Every candidate is missing at least one positive-weight channel; all are excluded and no selection exists.",
        common_weights(),
        vector("#242424", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#111111", red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#222222", white: 0.5, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#333333", white: 0.5, red: 0.25, blue: 0.125, lps: 0.375),
          vector("#444444", white: 0.5, red: 0.25, green: 0.625, lps: 0.375)
        ]
      ),
      scenario(
        "single-channel-lps",
        "Only lps is weighted; index 1 matches the target exactly and scores 0.0 even though every other channel is unmeasured.",
        %{lps: 1.0},
        vector("#0A0A0A", lps: 0.5),
        [
          vector("#111111", lps: 0.25),
          vector("#222222", lps: 0.5),
          vector("#333333", lps: 1.0)
        ]
      ),
      scenario(
        "exact-match-zero-error",
        "Index 0 is a channel-for-channel clone of the target and scores exactly 0.0 with no tie.",
        common_weights(),
        vector("#008080", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#008081", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#008082", white: 0.625, red: 0.375, green: 0.5, blue: 0.25, lps: 0.5)
        ]
      ),
      scenario(
        "unknown-weight-ignored",
        "The weights map carries an unknown light source (ultraviolet) that no vector can measure; it is ignored and the errors match the distinct-errors scenario verbatim.",
        Map.put(common_weights(), :ultraviolet, 3.0),
        vector("#336699", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#A0522D", white: 0.375, red: 0.5, green: 0.375, blue: 0.25, lps: 0.125),
          vector("#556B2F", white: 0.75, red: 0.125, green: 0.75, blue: 0.0, lps: 0.5),
          vector("#708090", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.5),
          vector("#FFD700", white: 0.125, red: 0.625, green: 0.25, blue: 0.5, lps: 0.75)
        ]
      ),
      scenario(
        "mixed-large-palette",
        "Eight candidates mixing exact ties, missing-measurement exclusions, and unmeasured zero-weight channels; the earliest member of the tied best trio wins.",
        common_weights(),
        vector("#100010", white: 0.5, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
        [
          vector("#210021", white: 0.375, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#220022", white: 0.625, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#230023", white: 0.5, red: 0.125, green: 0.625),
          vector("#240024", white: 0.25, red: 0.5, green: 0.375, blue: 0.0, lps: 0.125),
          vector("#250025", white: 0.625, red: 0.25, green: 0.625, blue: 0.125, lps: 0.375),
          vector("#260026", white: 0.875, red: 0.875, green: 0.875, blue: 0.875, lps: 0.875),
          vector("#270027", white: 0.0, red: 0.0, green: 0.0, blue: 0.0, lps: 0.0),
          vector("#280028", white: 0.5, red: 0.25)
        ]
      )
    ]
  end

  @doc """
  Builds the full corpus: deterministic scenarios plus solver-computed
  expected results (per-candidate scores, selection, error, tie evidence).
  """
  @spec build() :: map()
  def build do
    %{
      "algorithm_version" => @algorithm_version,
      "scorer" => inspect(@scorer),
      "selection" => "earliest-index-wins",
      "missing_policy" => "excluded-when-any-positive-weight-channel-missing",
      "light_sources" => Enum.map(ResponseVector.light_sources(), &Atom.to_string/1),
      "scenarios" => Enum.map(scenarios(), &run_scenario/1)
    }
  end

  @doc """
  Encodes a corpus as pretty-printed JSON terminated by a newline.

  Map key ordering comes from Elixir's deterministic term order, so the
  encoding is byte-identical between runs.
  """
  @spec encode(map()) :: binary()
  def encode(corpus \\ build()) do
    Jason.encode!(corpus, pretty: true) <> "\n"
  end

  @doc """
  Writes the corpus fixture to `output_path/0` and returns the path.
  """
  @spec write() :: Path.t()
  def write do
    path = output_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode())
    path
  end

  @doc """
  Compares the committed fixture against a fresh deterministic build.

  Returns `:ok` when the committed bytes match, otherwise `{:missing, path}`
  or `{:stale, path}` so callers can report deterministic next steps.
  """
  @spec check() :: :ok | {:missing, Path.t()} | {:stale, Path.t()}
  def check do
    path = output_path()

    case File.read(path) do
      {:ok, committed} ->
        if committed == encode(), do: :ok, else: {:stale, path}

      {:error, _reason} ->
        {:missing, path}
    end
  end

  defp common_weights, do: %{white: 0.5, red: 1.0, green: 1.0, blue: 0.25, lps: 1.5}

  defp scenario(id, description, weights, target, palette) do
    %{id: id, description: description, weights: weights, target: target, palette: palette}
  end

  defp vector(hex_color, channels) do
    %{hex_color: hex_color, channels: Map.new(channels)}
  end

  defp run_scenario(scenario) do
    weights = scenario.weights
    target = build_vector(scenario.target)
    vectors = Enum.map(scenario.palette, &build_vector/1)

    scored = IlluminantMatching.score_candidates(vectors, target, weights)
    best = IlluminantMatching.best_match(vectors, target, weights)

    %{
      "id" => scenario.id,
      "description" => scenario.description,
      "weights" => encode_weights(scenario.weights),
      "target" => encode_entry(scenario.target),
      "palette" => Enum.with_index(scenario.palette, &encode_entry(&1, &2)),
      "expected" => encode_expected(scored, best, vectors)
    }
  end

  defp build_vector(entry) do
    brightnesses =
      Map.new(ResponseVector.light_sources(), fn source ->
        {source, Map.get(entry.channels, source, :missing)}
      end)

    %ResponseVector{
      hex_color: entry.hex_color,
      printer_profile_id: "parity-corpus",
      missing?: Enum.any?(Map.values(brightnesses), &(&1 == :missing)),
      white: brightnesses.white,
      red: brightnesses.red,
      green: brightnesses.green,
      blue: brightnesses.blue,
      lps: brightnesses.lps
    }
  end

  defp encode_weights(weights) do
    Map.new(weights, fn {source, weight} -> {Atom.to_string(source), weight} end)
  end

  defp encode_entry(entry, index \\ nil) do
    %{
      "index" => index,
      "hex_color" => entry.hex_color,
      "channels" =>
        Map.new(entry.channels, fn {source, value} -> {Atom.to_string(source), value} end)
    }
  end

  defp encode_expected(scored, nil, _vectors) do
    %{
      "scores" => encode_scores(scored),
      "selected_index" => nil,
      "selected_hex_color" => nil,
      "error" => nil,
      "tie_broke" => nil,
      "tied_indices" => []
    }
  end

  defp encode_expected(scored, {vector, score}, vectors) do
    tied_indices = tied_indices(scored, score)

    %{
      "scores" => encode_scores(scored),
      "selected_index" => Enum.find_index(vectors, &(&1 == vector)),
      "selected_hex_color" => vector.hex_color,
      "error" => score,
      "tie_broke" => length(tied_indices) > 1,
      "tied_indices" => tied_indices
    }
  end

  defp encode_scores(scored) do
    Enum.with_index(scored, fn {_vector, score}, index ->
      %{"index" => index, "score" => encode_score(score)}
    end)
  end

  defp tied_indices(scored, min_score) do
    scored
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_vector, score}, index} ->
      if score == min_score, do: [index], else: []
    end)
  end

  defp encode_score(:excluded), do: "excluded"
  defp encode_score(score) when is_float(score), do: score
end

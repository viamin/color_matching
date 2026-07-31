defmodule ColorMatching.BrightnessReferenceScale do
  @moduledoc """
  Generates a printable black-to-white reference scale for manually scoring a
  printed swatch's apparent brightness under a selected illuminant.

  The scale mirrors the subjective 0–10 scoring model from
  `ColorMatching.Persistence.IlluminantResponse`: 0 is printed black, 10 is
  printed white, and each step in between is a single neutral gray value
  interpolated between them. The labels are derived directly from
  `IlluminantResponse.score_range/0` so they always match the scoring model.

  The printed source values are black-to-white gray only. A scorer holds the
  printed scale next to a printed color swatch under the selected illuminant
  (white, red, green, blue, or LPS) and reads off the step whose printed
  brightness best matches the swatch's apparent brightness under that light.
  The scale describes apparent brightness only; it does not claim that a color
  swatch appears neutral gray under a single-color illuminant.

  `to_png/2` renders the scale as a grayscale PNG strip suitable for printing
  and side-by-side visual comparison with printed color swatches.
  """

  alias ColorMatching.Persistence.IlluminantResponse
  alias ColorMatching.PNG

  @default_block_size 32
  @orientations [:horizontal, :vertical]

  @enforce_keys [:illuminant, :steps]
  defstruct [:illuminant, :steps]

  @type step :: %{score: non_neg_integer(), gray_value: 0..255, label: String.t()}
  @type orientation :: :horizontal | :vertical
  @type option :: {:block_size, pos_integer()} | {:orientation, orientation()}
  @type options :: [option()]
  @type t :: %__MODULE__{illuminant: String.t(), steps: [step()]}

  @doc """
  Returns the canonical reference-scale steps derived from the scoring model.

  Each step carries its `score` (0–10), the printed `gray_value` (0–255,
  linearly interpolated from black to white), and a human-readable `label`
  matching the score.
  """
  @spec steps() :: [step()]
  def steps do
    IlluminantResponse.score_range()
    |> Enum.map(&build_step/1)
  end

  @doc """
  Builds a reference scale bound to `illuminant` for scoring under that light.

  `illuminant` is normalized (trimmed and lowercased) and must be one of the
  supported illuminants (`IlluminantResponse.illuminants/0`).
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, String.t()}
  def new(illuminant) when is_binary(illuminant) do
    with {:ok, normalized} <- normalize_illuminant(illuminant) do
      {:ok, %__MODULE__{illuminant: normalized, steps: steps()}}
    end
  end

  @doc """
  Renders `scale` as a grayscale PNG strip.

  ## Options

    * `:block_size` – edge length, in pixels, of each step's square block
      (default `#{@default_block_size}`).
    * `:orientation` – `:horizontal` (steps left to right) or `:vertical`
      (steps top to bottom); default `:horizontal`.
  """
  @spec to_png(t(), options()) :: {:ok, binary()} | {:error, String.t()}
  def to_png(scale, options \\ [])

  def to_png(%__MODULE__{steps: steps}, options) do
    block_size = Keyword.get(options, :block_size, @default_block_size)
    orientation = Keyword.get(options, :orientation, :horizontal)

    with :ok <- validate_block_size(block_size),
         :ok <- validate_orientation(orientation) do
      {width, height} = dimensions(length(steps), block_size, orientation)
      pixels = build_pixels(steps, block_size, orientation)

      PNG.encode_rgb(width, height, pixels)
    end
  end

  @doc """
  Returns a compliant, illuminant-aware description of the reference scale.

  The wording describes apparent brightness and never implies that a color
  swatch appears neutral gray under a single-color illuminant.
  """
  @spec description(t()) :: String.t()
  def description(%__MODULE__{illuminant: illuminant}) do
    "Apparent brightness reference under #{illuminant_label(illuminant)} light"
  end

  defp build_step(score) do
    %{score: score, gray_value: gray_value(score), label: Integer.to_string(score)}
  end

  defp gray_value(score) do
    {min_score, max_score} = IlluminantResponse.score_range() |> Enum.min_max()
    round((score - min_score) / (max_score - min_score) * 255)
  end

  defp normalize_illuminant(illuminant) do
    normalized = illuminant |> String.trim() |> String.downcase()

    if normalized in IlluminantResponse.illuminants() do
      {:ok, normalized}
    else
      {:error, "unsupported illuminant: #{inspect(illuminant)}"}
    end
  end

  defp dimensions(step_count, block_size, :horizontal),
    do: {step_count * block_size, block_size}

  defp dimensions(step_count, block_size, :vertical),
    do: {block_size, step_count * block_size}

  defp build_pixels(steps, block_size, :horizontal) do
    for _row <- 1..block_size,
        step <- steps,
        _column <- 1..block_size,
        do: pixel(step.gray_value)
  end

  defp build_pixels(steps, block_size, :vertical) do
    for step <- steps,
        _row <- 1..block_size,
        _column <- 1..block_size,
        do: pixel(step.gray_value)
  end

  defp pixel(gray), do: {gray, gray, gray}

  defp validate_block_size(block_size)
       when is_integer(block_size) and block_size > 0,
       do: :ok

  defp validate_block_size(_block_size),
    do: {:error, "block_size must be a positive integer"}

  defp validate_orientation(orientation) when orientation in @orientations, do: :ok

  defp validate_orientation(orientation),
    do: {:error, "unsupported orientation: #{inspect(orientation)}"}

  defp illuminant_label("lps"), do: "low-pressure sodium"
  defp illuminant_label(illuminant), do: illuminant
end

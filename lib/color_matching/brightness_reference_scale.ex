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
  @max_block_size 256
  @orientations [:horizontal, :vertical]
  @label_padding 2
  @digit_patterns %{
    "0" => ["111", "101", "101", "101", "111"],
    "1" => ["010", "110", "010", "010", "111"],
    "2" => ["111", "001", "111", "100", "111"],
    "3" => ["111", "001", "111", "001", "111"],
    "4" => ["101", "101", "111", "001", "001"],
    "5" => ["111", "100", "111", "001", "111"],
    "6" => ["111", "100", "111", "101", "111"],
    "7" => ["111", "001", "001", "001", "001"],
    "8" => ["111", "101", "111", "101", "111"],
    "9" => ["111", "101", "111", "001", "111"]
  }

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

  @spec max_block_size() :: pos_integer()
  def max_block_size, do: @max_block_size

  @spec default_block_size() :: pos_integer()
  def default_block_size, do: @default_block_size

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
      layout = layout(steps, block_size, orientation)
      pixels = build_pixels(steps, layout, orientation)

      PNG.encode_rgb(layout.width, layout.height, pixels)
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

  defp layout(steps, block_size, :horizontal) do
    metrics = label_metrics(steps, block_size)

    %{
      block_size: block_size,
      cell_width: max(block_size, metrics.max_label_width + @label_padding * 2),
      height: block_size + metrics.label_height + @label_padding * 2,
      label_metrics: metrics,
      width: length(steps) * max(block_size, metrics.max_label_width + @label_padding * 2)
    }
  end

  defp layout(steps, block_size, :vertical) do
    metrics = label_metrics(steps, block_size)

    %{
      block_size: block_size,
      cell_height: max(block_size, metrics.label_height + @label_padding * 2),
      height: length(steps) * max(block_size, metrics.label_height + @label_padding * 2),
      label_metrics: metrics,
      width: block_size + metrics.max_label_width + @label_padding * 3
    }
  end

  defp build_pixels(steps, layout, :horizontal) do
    for y <- 0..(layout.height - 1),
        step <- steps_with_index(steps),
        x <- 0..(layout.cell_width - 1),
        do: horizontal_pixel(step, x, y, layout)
  end

  defp build_pixels(steps, layout, :vertical) do
    for step <- steps_with_index(steps),
        y <- 0..(layout.cell_height - 1),
        x <- 0..(layout.width - 1),
        do: vertical_pixel(step, x, y, layout)
  end

  defp pixel(:black), do: {0, 0, 0}
  defp pixel(:white), do: {255, 255, 255}
  defp pixel(gray), do: {gray, gray, gray}

  defp horizontal_pixel({step, _index}, x, y, layout) do
    block_x = div(layout.cell_width - layout.block_size, 2)

    cond do
      within_horizontal_block?(x, y, block_x, layout.block_size) ->
        pixel(step.gray_value)

      label_pixel?(
        step.label,
        x,
        y,
        horizontal_label_origin(step.label, layout),
        layout.label_metrics.scale
      ) ->
        pixel(:black)

      true ->
        pixel(:white)
    end
  end

  defp vertical_pixel({step, index}, x, y, layout) do
    step_y = index * layout.cell_height
    block_y = step_y + div(layout.cell_height - layout.block_size, 2)

    cond do
      within_vertical_block?(x, y, block_y, layout.block_size) ->
        pixel(step.gray_value)

      label_pixel?(
        step.label,
        x,
        y - step_y,
        vertical_label_origin(layout),
        layout.label_metrics.scale
      ) ->
        pixel(:black)

      true ->
        pixel(:white)
    end
  end

  defp within_horizontal_block?(x, y, block_x, block_size) do
    y < block_size and x >= block_x and x < block_x + block_size
  end

  defp within_vertical_block?(x, y, block_y, block_size) do
    x < block_size and y >= block_y and y < block_y + block_size
  end

  defp horizontal_label_origin(label, layout) do
    label_width = label_width(label, layout.label_metrics.scale)

    %{
      x: div(layout.cell_width - label_width, 2),
      y: layout.block_size + @label_padding
    }
  end

  defp vertical_label_origin(layout) do
    %{
      x: layout.block_size + @label_padding,
      y: div(layout.cell_height - layout.label_metrics.label_height, 2)
    }
  end

  defp label_pixel?(label, x, y, origin, scale) do
    x >= origin.x and y >= origin.y and glyph_pixel?(label, x - origin.x, y - origin.y, scale)
  end

  defp glyph_pixel?(label, x, y, scale) when x >= 0 and y >= 0 do
    digit_width = 3 * scale
    digit_height = 5 * scale
    gap = scale
    label_width = label_width(label, scale)

    if x < label_width and y < digit_height do
      digit_index = div(x, digit_width + gap)
      digit_x = rem(x, digit_width + gap)

      if digit_index < String.length(label) and digit_x < digit_width do
        digit = String.at(label, digit_index)
        pattern = Map.fetch!(@digit_patterns, digit)
        row = div(y, scale)
        column = div(digit_x, scale)

        Enum.at(pattern, row)
        |> String.at(column) == "1"
      else
        false
      end
    else
      false
    end
  end

  defp glyph_pixel?(_label, _x, _y, _scale), do: false

  defp label_metrics(steps, block_size) do
    scale = max(div(block_size, 16), 1)

    max_label_width =
      steps
      |> Enum.map(&label_width(&1.label, scale))
      |> Enum.max()

    %{label_height: 5 * scale, max_label_width: max_label_width, scale: scale}
  end

  defp label_width(label, scale) do
    digit_count = String.length(label)
    digit_count * 3 * scale + max(digit_count - 1, 0) * scale
  end

  defp steps_with_index(steps), do: Enum.with_index(steps)

  defp validate_block_size(block_size)
       when is_integer(block_size) and block_size > 0 and block_size <= @max_block_size,
       do: :ok

  defp validate_block_size(block_size)
       when is_integer(block_size) and block_size > @max_block_size,
       do: {:error, "block_size must be less than or equal to #{@max_block_size}"}

  defp validate_block_size(_block_size),
    do: {:error, "block_size must be a positive integer"}

  defp validate_orientation(orientation) when orientation in @orientations, do: :ok

  defp validate_orientation(orientation),
    do: {:error, "unsupported orientation: #{inspect(orientation)}"}

  defp illuminant_label("lps"), do: "low-pressure sodium"
  defp illuminant_label(illuminant), do: illuminant
end

defmodule ColorMatching.ColorFormat do
  @moduledoc """
  Conversion and validation utilities for working with a single color across
  multiple representations: HEX, RGB, HSL, and HSV/HSB.

  The canonical internal color format used throughout the application remains
  a 6-digit hex string prefixed with `#` (e.g. `"#FF6B6B"`), matching the
  format already used for palette storage and CSS. All other formats are
  converted to/from hex so palette storage does not need to change.

  Parsing functions accept user-entered strings (e.g. `"rgb(255, 107, 107)"`)
  and return `{:ok, value}` or `{:error, reason}` with a user-friendly error
  message. Values are normalized so equivalent inputs (extra whitespace,
  lowercase hex, out-of-range hue) resolve to the same internal color.
  """

  @type rgb :: {0..255, 0..255, 0..255}
  @type hsl :: {0..360, 0..100, 0..100}
  @type hsv :: {0..360, 0..100, 0..100}

  # ---------------------------------------------------------------------
  # HEX
  # ---------------------------------------------------------------------

  @doc """
  Normalizes a hex color string: trims whitespace, expands 3-digit shorthand,
  and upcases the result.

  ## Examples

      iex> ColorMatching.ColorFormat.normalize_hex("#fff")
      {:ok, "#FFFFFF"}

      iex> ColorMatching.ColorFormat.normalize_hex("#FF6B6B")
      {:ok, "#FF6B6B"}

      iex> ColorMatching.ColorFormat.normalize_hex("not-a-color")
      {:error, "Hex color must start with # followed by 3 or 6 hex digits"}
  """
  @spec normalize_hex(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_hex(color) when is_binary(color) do
    case String.trim(color) do
      "#" <> hex ->
        upcased = String.upcase(hex)

        cond do
          String.match?(upcased, ~r/^[0-9A-F]{6}$/) ->
            {:ok, "#" <> upcased}

          String.match?(upcased, ~r/^[0-9A-F]{3}$/) ->
            expanded = upcased |> String.graphemes() |> Enum.map(&(&1 <> &1)) |> Enum.join()
            {:ok, "#" <> expanded}

          true ->
            {:error, "Hex color must start with # followed by 3 or 6 hex digits"}
        end

      _ ->
        {:error, "Hex color must start with # followed by 3 or 6 hex digits"}
    end
  end

  def normalize_hex(_color), do: {:error, "Hex color must be a string"}

  @doc """
  Converts a hex color string to an `{r, g, b}` tuple with values 0-255.

  ## Examples

      iex> ColorMatching.ColorFormat.hex_to_rgb("#FF6B6B")
      {:ok, {255, 107, 107}}

      iex> ColorMatching.ColorFormat.hex_to_rgb("#FFF")
      {:ok, {255, 255, 255}}
  """
  @spec hex_to_rgb(String.t()) :: {:ok, rgb()} | {:error, String.t()}
  def hex_to_rgb(hex) do
    with {:ok, "#" <> digits} <- normalize_hex(hex) do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = digits
      {:ok, {hex_byte(r), hex_byte(g), hex_byte(b)}}
    end
  end

  @spec hex_byte(String.t()) :: non_neg_integer()
  defp hex_byte(byte) do
    {value, ""} = Integer.parse(byte, 16)
    value
  end

  @doc """
  Converts an `{r, g, b}` tuple (0-255 each) to a hex color string.

  ## Examples

      iex> ColorMatching.ColorFormat.rgb_to_hex({255, 107, 107})
      {:ok, "#FF6B6B"}
  """
  @spec rgb_to_hex(rgb()) :: {:ok, String.t()} | {:error, String.t()}
  def rgb_to_hex({r, g, b}) when r in 0..255 and g in 0..255 and b in 0..255 do
    hex =
      [r, g, b]
      |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
      |> Enum.join()
      |> String.upcase()

    {:ok, "#" <> hex}
  end

  def rgb_to_hex(_rgb), do: {:error, "RGB values must be integers between 0 and 255"}

  # ---------------------------------------------------------------------
  # RGB string parsing/formatting
  # ---------------------------------------------------------------------

  @rgb_regex ~r/^rgba?\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*[\d.]+\s*)?\)$/i

  @doc """
  Parses a user-entered RGB string such as `"rgb(255, 107, 107)"` into an
  `{r, g, b}` tuple, validating that each channel is between 0 and 255.

  ## Examples

      iex> ColorMatching.ColorFormat.parse_rgb("rgb(255, 107, 107)")
      {:ok, {255, 107, 107}}

      iex> ColorMatching.ColorFormat.parse_rgb("rgb(300, 0, 0)")
      {:error, "RGB values must be between 0 and 255"}
  """
  @spec parse_rgb(String.t()) :: {:ok, rgb()} | {:error, String.t()}
  def parse_rgb(string) when is_binary(string) do
    case Regex.run(@rgb_regex, String.trim(string)) do
      [_full, r, g, b] ->
        values = Enum.map([r, g, b], &String.to_integer/1)

        if Enum.all?(values, &(&1 in 0..255)) do
          {:ok, List.to_tuple(values)}
        else
          {:error, "RGB values must be between 0 and 255"}
        end

      nil ->
        {:error, "Invalid RGB format. Expected rgb(r, g, b) with values 0-255"}
    end
  end

  def parse_rgb(_string), do: {:error, "RGB value must be a string"}

  @doc """
  Formats an `{r, g, b}` tuple as a CSS-style RGB string.

  ## Examples

      iex> ColorMatching.ColorFormat.format_rgb({255, 107, 107})
      "rgb(255, 107, 107)"
  """
  @spec format_rgb(rgb()) :: String.t()
  def format_rgb({r, g, b}), do: "rgb(#{r}, #{g}, #{b})"

  # ---------------------------------------------------------------------
  # HSL
  # ---------------------------------------------------------------------

  @hsl_regex ~r/^hsla?\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)%\s*,\s*(-?\d+(?:\.\d+)?)%\s*(?:,\s*[\d.]+\s*)?\)$/i

  @doc """
  Converts a hex color string to an `{h, s, l}` tuple (hue 0-360, saturation
  and lightness as percentages 0-100).

  ## Examples

      iex> ColorMatching.ColorFormat.hex_to_hsl("#FF6B6B")
      {:ok, {0, 100, 71}}
  """
  @spec hex_to_hsl(String.t()) :: {:ok, hsl()} | {:error, String.t()}
  def hex_to_hsl(hex) do
    with {:ok, rgb} <- hex_to_rgb(hex) do
      rgb_to_hsl(rgb)
    end
  end

  @doc """
  Converts an `{r, g, b}` tuple to an `{h, s, l}` tuple.
  """
  @spec rgb_to_hsl(rgb()) :: {:ok, hsl()} | {:error, String.t()}
  def rgb_to_hsl({r, g, b}) when r in 0..255 and g in 0..255 and b in 0..255 do
    r1 = r / 255
    g1 = g / 255
    b1 = b / 255

    max_c = Enum.max([r1, g1, b1])
    min_c = Enum.min([r1, g1, b1])
    l = (max_c + min_c) / 2

    {h, s} =
      if max_c == min_c do
        {0.0, 0.0}
      else
        d = max_c - min_c
        s = if l > 0.5, do: d / (2 - max_c - min_c), else: d / (max_c + min_c)
        {hue_degrees(r1, g1, b1, max_c, d), s}
      end

    {:ok, {wrap_hue(h), round(s * 100), round(l * 100)}}
  end

  def rgb_to_hsl(_rgb), do: {:error, "RGB values must be integers between 0 and 255"}

  @doc """
  Converts an `{h, s, l}` tuple back to a hex color string.

  ## Examples

      iex> ColorMatching.ColorFormat.hsl_to_hex({0, 100, 71})
      {:ok, "#FF6B6B"}
  """
  @spec hsl_to_hex(hsl()) :: {:ok, String.t()} | {:error, String.t()}
  def hsl_to_hex(hsl) do
    with {:ok, rgb} <- hsl_to_rgb(hsl) do
      rgb_to_hex(rgb)
    end
  end

  @doc """
  Converts an `{h, s, l}` tuple to an `{r, g, b}` tuple.
  """
  @spec hsl_to_rgb(hsl()) :: {:ok, rgb()} | {:error, String.t()}
  def hsl_to_rgb({h, s, l}) when is_number(h) and s in 0..100 and l in 0..100 do
    h1 = normalize_hue(h)
    s1 = s / 100
    l1 = l / 100

    c = (1 - abs(2 * l1 - 1)) * s1
    x = c * (1 - abs(:math.fmod(h1 / 60, 2) - 1))
    m = l1 - c / 2

    {:ok, from_chroma(h1, c, x, m)}
  end

  def hsl_to_rgb(_hsl), do: {:error, "HSL saturation and lightness must be between 0 and 100"}

  @doc """
  Parses a user-entered HSL string such as `"hsl(0, 100%, 71%)"` into an
  `{h, s, l}` tuple. Hue is normalized (wrapped) into the 0-360 range.

  ## Examples

      iex> ColorMatching.ColorFormat.parse_hsl("hsl(0, 100%, 71%)")
      {:ok, {0, 100, 71}}

      iex> ColorMatching.ColorFormat.parse_hsl("hsl(370, 100%, 50%)")
      {:ok, {10, 100, 50}}

      iex> ColorMatching.ColorFormat.parse_hsl("hsl(0, 150%, 50%)")
      {:error, "HSL saturation and lightness must be between 0% and 100%"}
  """
  @spec parse_hsl(String.t()) :: {:ok, hsl()} | {:error, String.t()}
  def parse_hsl(string) when is_binary(string) do
    case Regex.run(@hsl_regex, String.trim(string)) do
      [_full, h, s, l] ->
        {h, s, l} =
          {String.to_float(ensure_decimal(h)), String.to_float(ensure_decimal(s)),
           String.to_float(ensure_decimal(l))}

        if percentage?(s) and percentage?(l) do
          {:ok, {wrap_hue(h), round(s), round(l)}}
        else
          {:error, "HSL saturation and lightness must be between 0% and 100%"}
        end

      nil ->
        {:error, "Invalid HSL format. Expected hsl(h, s%, l%)"}
    end
  end

  def parse_hsl(_string), do: {:error, "HSL value must be a string"}

  @doc """
  Formats an `{h, s, l}` tuple as a CSS-style HSL string.

  ## Examples

      iex> ColorMatching.ColorFormat.format_hsl({0, 100, 71})
      "hsl(0, 100%, 71%)"
  """
  @spec format_hsl(hsl()) :: String.t()
  def format_hsl({h, s, l}), do: "hsl(#{h}, #{s}%, #{l}%)"

  # ---------------------------------------------------------------------
  # HSV / HSB
  # ---------------------------------------------------------------------

  @hsv_regex ~r/^hs[vb]a?\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)%\s*,\s*(-?\d+(?:\.\d+)?)%\s*(?:,\s*[\d.]+\s*)?\)$/i

  @doc """
  Converts a hex color string to an `{h, s, v}` tuple (hue 0-360, saturation
  and value/brightness as percentages 0-100).

  ## Examples

      iex> ColorMatching.ColorFormat.hex_to_hsv("#FF6B6B")
      {:ok, {0, 58, 100}}
  """
  @spec hex_to_hsv(String.t()) :: {:ok, hsv()} | {:error, String.t()}
  def hex_to_hsv(hex) do
    with {:ok, rgb} <- hex_to_rgb(hex) do
      rgb_to_hsv(rgb)
    end
  end

  @doc """
  Converts an `{r, g, b}` tuple to an `{h, s, v}` tuple.
  """
  @spec rgb_to_hsv(rgb()) :: {:ok, hsv()} | {:error, String.t()}
  def rgb_to_hsv({r, g, b}) when r in 0..255 and g in 0..255 and b in 0..255 do
    r1 = r / 255
    g1 = g / 255
    b1 = b / 255

    max_c = Enum.max([r1, g1, b1])
    min_c = Enum.min([r1, g1, b1])
    d = max_c - min_c

    v = max_c
    s = if max_c == 0, do: 0.0, else: d / max_c
    h = if max_c == min_c, do: 0.0, else: hue_degrees(r1, g1, b1, max_c, d)

    {:ok, {wrap_hue(h), round(s * 100), round(v * 100)}}
  end

  def rgb_to_hsv(_rgb), do: {:error, "RGB values must be integers between 0 and 255"}

  @doc """
  Converts an `{h, s, v}` tuple back to a hex color string.

  ## Examples

      iex> ColorMatching.ColorFormat.hsv_to_hex({0, 58, 100})
      {:ok, "#FF6B6B"}
  """
  @spec hsv_to_hex(hsv()) :: {:ok, String.t()} | {:error, String.t()}
  def hsv_to_hex(hsv) do
    with {:ok, rgb} <- hsv_to_rgb(hsv) do
      rgb_to_hex(rgb)
    end
  end

  @doc """
  Converts an `{h, s, v}` tuple to an `{r, g, b}` tuple.
  """
  @spec hsv_to_rgb(hsv()) :: {:ok, rgb()} | {:error, String.t()}
  def hsv_to_rgb({h, s, v}) when is_number(h) and s in 0..100 and v in 0..100 do
    h1 = normalize_hue(h)
    s1 = s / 100
    v1 = v / 100

    c = v1 * s1
    x = c * (1 - abs(:math.fmod(h1 / 60, 2) - 1))
    m = v1 - c

    {:ok, from_chroma(h1, c, x, m)}
  end

  def hsv_to_rgb(_hsv), do: {:error, "HSV saturation and value must be between 0 and 100"}

  @doc """
  Parses a user-entered HSV/HSB string such as `"hsv(0, 58%, 100%)"` into an
  `{h, s, v}` tuple. Hue is normalized (wrapped) into the 0-360 range.

  ## Examples

      iex> ColorMatching.ColorFormat.parse_hsv("hsv(0, 58%, 100%)")
      {:ok, {0, 58, 100}}

      iex> ColorMatching.ColorFormat.parse_hsv("hsb(0, 58%, 100%)")
      {:ok, {0, 58, 100}}
  """
  @spec parse_hsv(String.t()) :: {:ok, hsv()} | {:error, String.t()}
  def parse_hsv(string) when is_binary(string) do
    case Regex.run(@hsv_regex, String.trim(string)) do
      [_full, h, s, v] ->
        {h, s, v} =
          {String.to_float(ensure_decimal(h)), String.to_float(ensure_decimal(s)),
           String.to_float(ensure_decimal(v))}

        if percentage?(s) and percentage?(v) do
          {:ok, {wrap_hue(h), round(s), round(v)}}
        else
          {:error, "HSV saturation and value must be between 0% and 100%"}
        end

      nil ->
        {:error, "Invalid HSV format. Expected hsv(h, s%, v%)"}
    end
  end

  def parse_hsv(_string), do: {:error, "HSV value must be a string"}

  @doc """
  Formats an `{h, s, v}` tuple as an HSV string.

  ## Examples

      iex> ColorMatching.ColorFormat.format_hsv({0, 58, 100})
      "hsv(0, 58%, 100%)"
  """
  @spec format_hsv(hsv()) :: String.t()
  def format_hsv({h, s, v}), do: "hsv(#{h}, #{s}%, #{v}%)"

  # ---------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------

  # Computes the hue in degrees for RGB channels already normalized to 0..1,
  # given the max channel value and the chroma (max - min).
  @spec hue_degrees(float(), float(), float(), float(), float()) :: float()
  defp hue_degrees(r, g, b, max_c, d) do
    h =
      cond do
        max_c == r -> :math.fmod((g - b) / d, 6)
        max_c == g -> (b - r) / d + 2
        true -> (r - g) / d + 4
      end

    h * 60
  end

  # Builds an {r, g, b} tuple (0-255) from HSL/HSV chroma intermediates.
  @spec from_chroma(float(), float(), float(), float()) :: rgb()
  defp from_chroma(h, c, x, m) do
    {r1, g1, b1} =
      cond do
        h < 60 -> {c, x, 0}
        h < 120 -> {x, c, 0}
        h < 180 -> {0, c, x}
        h < 240 -> {0, x, c}
        h < 300 -> {x, 0, c}
        true -> {c, 0, x}
      end

    {clamp_byte((r1 + m) * 255), clamp_byte((g1 + m) * 255), clamp_byte((b1 + m) * 255)}
  end

  @spec clamp_byte(number()) :: 0..255
  defp clamp_byte(value) do
    value |> round() |> max(0) |> min(255)
  end

  # Normalizes a hue value (possibly negative or >= 360) into the [0, 360)
  # range without rounding, for use in math that expects a float.
  @spec normalize_hue(number()) :: float()
  defp normalize_hue(h) do
    wrapped = :math.fmod(h, 360)
    if wrapped < 0, do: wrapped + 360, else: wrapped
  end

  # Normalizes and rounds a hue value to an integer in [0, 360), wrapping
  # 360 itself back to 0.
  @spec wrap_hue(number()) :: 0..359
  defp wrap_hue(h) do
    h |> normalize_hue() |> round() |> rem(360)
  end

  # Regex captures for whole numbers (e.g. "10") won't parse with
  # String.to_float/1, which requires a decimal point.
  @spec ensure_decimal(String.t()) :: String.t()
  defp ensure_decimal(numeric_string) do
    if String.contains?(numeric_string, "."), do: numeric_string, else: numeric_string <> ".0"
  end

  # Checks that a (possibly float) value falls within 0..100 inclusive.
  # Plain range membership (`in 0.0..100.0`) is not supported for floats.
  @spec percentage?(number()) :: boolean()
  defp percentage?(value), do: value >= 0 and value <= 100
end

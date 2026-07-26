defmodule ColorMatching.ColorSpace do
  @moduledoc """
  Color-space conversions for normalized sRGB hex colors.

  Public functions return numeric tuples so presentation code can decide how
  to label and round each representation.
  """

  alias ColorMatching.ColorFormat

  @type linear_rgb :: {float(), float(), float()}
  @type xyz :: {float(), float(), float()}
  @type lab :: {float(), float(), float()}

  @d65_x 0.95047
  @d65_y 1.0
  @d65_z 1.08883
  @epsilon 216 / 24_389
  @kappa 24_389 / 27

  @spec hex_to_linear_rgb(String.t()) :: {:ok, linear_rgb()} | {:error, String.t()}
  def hex_to_linear_rgb(hex) do
    case ColorFormat.hex_to_rgb(hex) do
      {:ok, {r, g, b}} ->
        {:ok, {srgb_channel_to_linear(r), srgb_channel_to_linear(g), srgb_channel_to_linear(b)}}

      error ->
        error
    end
  end

  @spec hex_to_xyz(String.t()) :: {:ok, xyz()} | {:error, String.t()}
  def hex_to_xyz(hex) do
    case hex_to_linear_rgb(hex) do
      {:ok, {r, g, b}} ->
        {:ok,
         {
           0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
           0.2126729 * r + 0.7151522 * g + 0.072175 * b,
           0.0193339 * r + 0.119192 * g + 0.9503041 * b
         }}

      error ->
        error
    end
  end

  @spec hex_to_lab(String.t()) :: {:ok, lab()} | {:error, String.t()}
  def hex_to_lab(hex) do
    case hex_to_xyz(hex) do
      {:ok, {x, y, z}} ->
        fx = lab_f(x / @d65_x)
        fy = lab_f(y / @d65_y)
        fz = lab_f(z / @d65_z)

        {:ok, {116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)}}

      error ->
        error
    end
  end

  @doc """
  Computes CIEDE2000 color difference between two sRGB hex colors.
  """
  @spec ciede2000(String.t(), String.t()) :: {:ok, float()} | {:error, String.t()}
  def ciede2000(first, second) do
    with {:ok, lab1} <- hex_to_lab(first),
         {:ok, lab2} <- hex_to_lab(second) do
      {:ok, ciede2000_from_lab(lab1, lab2)}
    end
  end

  @spec srgb_channel_to_linear(0..255) :: float()
  defp srgb_channel_to_linear(channel) do
    value = channel / 255

    if value <= 0.04045 do
      value / 12.92
    else
      :math.pow((value + 0.055) / 1.055, 2.4)
    end
  end

  @spec lab_f(float()) :: float()
  defp lab_f(value) when value > @epsilon, do: cube_root(value)
  defp lab_f(value), do: (@kappa * value + 16) / 116

  @spec cube_root(float()) :: float()
  defp cube_root(value), do: :math.pow(value, 1 / 3)

  @spec hue_degrees(float(), float()) :: float()
  defp hue_degrees(a, b) do
    hue = radians_to_degrees(:math.atan2(b, a))
    if hue < 0, do: hue + 360, else: hue
  end

  @spec ciede2000_from_lab(lab(), lab()) :: float()
  defp ciede2000_from_lab({l1, a1, b1}, {l2, a2, b2}) do
    c1 = :math.sqrt(a1 * a1 + b1 * b1)
    c2 = :math.sqrt(a2 * a2 + b2 * b2)
    avg_c = (c1 + c2) / 2
    g = 0.5 * (1 - :math.sqrt(:math.pow(avg_c, 7) / (:math.pow(avg_c, 7) + :math.pow(25, 7))))

    a1p = (1 + g) * a1
    a2p = (1 + g) * a2
    c1p = :math.sqrt(a1p * a1p + b1 * b1)
    c2p = :math.sqrt(a2p * a2p + b2 * b2)
    h1p = hue_degrees(a1p, b1)
    h2p = hue_degrees(a2p, b2)

    delta_lp = l2 - l1
    delta_cp = c2p - c1p
    delta_hp = delta_h_prime(c1p, c2p, h1p, h2p)
    delta_hp_term = 2 * :math.sqrt(c1p * c2p) * :math.sin(degrees_to_radians(delta_hp / 2))

    avg_lp = (l1 + l2) / 2
    avg_cp = (c1p + c2p) / 2
    avg_hp = average_h_prime(c1p, c2p, h1p, h2p)

    t =
      1 - 0.17 * :math.cos(degrees_to_radians(avg_hp - 30)) +
        0.24 * :math.cos(degrees_to_radians(2 * avg_hp)) +
        0.32 * :math.cos(degrees_to_radians(3 * avg_hp + 6)) -
        0.20 * :math.cos(degrees_to_radians(4 * avg_hp - 63))

    delta_theta = 30 * :math.exp(-:math.pow((avg_hp - 275) / 25, 2))
    rc = 2 * :math.sqrt(:math.pow(avg_cp, 7) / (:math.pow(avg_cp, 7) + :math.pow(25, 7)))
    sl = 1 + 0.015 * :math.pow(avg_lp - 50, 2) / :math.sqrt(20 + :math.pow(avg_lp - 50, 2))
    sc = 1 + 0.045 * avg_cp
    sh = 1 + 0.015 * avg_cp * t
    rt = -:math.sin(degrees_to_radians(2 * delta_theta)) * rc

    :math.sqrt(
      :math.pow(delta_lp / sl, 2) +
        :math.pow(delta_cp / sc, 2) +
        :math.pow(delta_hp_term / sh, 2) +
        rt * (delta_cp / sc) * (delta_hp_term / sh)
    )
  end

  @spec delta_h_prime(float(), float(), float(), float()) :: float()
  defp delta_h_prime(c1p, c2p, h1p, h2p) do
    cond do
      c1p * c2p == 0 -> 0
      h2p - h1p > 180 -> h2p - h1p - 360
      h2p - h1p < -180 -> h2p - h1p + 360
      true -> h2p - h1p
    end
  end

  @spec average_h_prime(float(), float(), float(), float()) :: float()
  defp average_h_prime(c1p, c2p, h1p, h2p) do
    cond do
      c1p * c2p == 0 -> h1p + h2p
      abs(h1p - h2p) <= 180 -> (h1p + h2p) / 2
      h1p + h2p < 360 -> (h1p + h2p + 360) / 2
      true -> (h1p + h2p - 360) / 2
    end
  end

  @spec degrees_to_radians(float()) :: float()
  defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180

  @spec radians_to_degrees(float()) :: float()
  defp radians_to_degrees(radians), do: radians * 180 / :math.pi()
end

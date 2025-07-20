defmodule ColorMatching.ColorUtils do
  @moduledoc """
  Utility functions for color manipulation
  """

  @doc """
  Inverts a hex color by inverting each RGB component
  
  ## Examples
  
      iex> ColorMatching.ColorUtils.invert_color("#FF0000")
      "#00FFFF"
      
      iex> ColorMatching.ColorUtils.invert_color("#000000")
      "#FFFFFF"
  """
  def invert_color("#" <> hex) when byte_size(hex) == 6 do
    {r, g, b} = parse_hex_color(hex)
    
    inverted_r = 255 - r
    inverted_g = 255 - g
    inverted_b = 255 - b
    
    r_hex = Integer.to_string(inverted_r, 16) |> String.pad_leading(2, "0") |> String.upcase()
    g_hex = Integer.to_string(inverted_g, 16) |> String.pad_leading(2, "0") |> String.upcase()
    b_hex = Integer.to_string(inverted_b, 16) |> String.pad_leading(2, "0") |> String.upcase()
    
    "#" <> r_hex <> g_hex <> b_hex
  end
  
  def invert_color("#" <> hex) when byte_size(hex) == 3 do
    # Handle 3-character hex colors by expanding them
    expanded = String.graphemes(hex) |> Enum.map(&(&1 <> &1)) |> Enum.join()
    invert_color("#" <> expanded)
  end
  
  def invert_color(color), do: color

  @doc """
  Generates a random hex color
  
  ## Examples
  
      iex> ColorMatching.ColorUtils.random_color()
      "#A3B5C7"
  """
  def random_color do
    r = :rand.uniform(256) - 1
    g = :rand.uniform(256) - 1
    b = :rand.uniform(256) - 1
    
    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0") |> String.upcase()
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0") |> String.upcase()
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0") |> String.upcase()
    
    "#" <> r_hex <> g_hex <> b_hex
  end
  
  defp parse_hex_color(hex) do
    {r, ""} = String.slice(hex, 0, 2) |> Integer.parse(16)
    {g, ""} = String.slice(hex, 2, 2) |> Integer.parse(16)
    {b, ""} = String.slice(hex, 4, 2) |> Integer.parse(16)
    {r, g, b}
  end
end
defmodule ColorMatching.PaletteStorage do
  @moduledoc """
  Handles storage and retrieval of color palettes using localStorage and provides preset palettes.
  """

  @preset_palettes %{
    "Warm" => ["#FF6B6B", "#FF8E53", "#FF6B35", "#F7931E", "#FFD23F", "#FFF07C", "#FF9F40", "#FF6B35", "#D63031", "#E84393"],
    "Cool" => ["#74B9FF", "#0984E3", "#00B894", "#00CEC9", "#6C5CE7", "#A29BFE", "#FD79A8", "#FDCB6E", "#81ECEC", "#55A3FF"],
    "Monochrome" => ["#2D3436", "#636E72", "#B2BEC3", "#DDD", "#FFF", "#F8F9FA", "#E9ECEF", "#DEE2E6", "#CED4DA", "#ADB5BD"],
    "High Contrast" => ["#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF", "#FF8000", "#8000FF"],
    "Earth Tones" => ["#8B4513", "#D2B48C", "#DEB887", "#F4A460", "#CD853F", "#A0522D", "#BC8F8F", "#F5DEB3", "#D2691E", "#B22222"],
    "Pastels" => ["#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF", "#E1BAFF", "#FFBAE1", "#C9FFBA", "#BAFFE1", "#E1FFBA"],
    "Vibrant" => ["#E74C3C", "#9B59B6", "#3498DB", "#1ABC9C", "#F1C40F", "#E67E22", "#95A5A6", "#34495E", "#F39C12", "#8E44AD"],
    "Neon" => ["#FF073A", "#39FF14", "#FF0080", "#00FFFF", "#FFFF00", "#FF8C00", "#9400D3", "#00FF7F", "#FF1493", "#00BFFF"],
    "Sodium Metamers A" => ["#FF4444", "#44AA44", "#4444FF", "#FFAA00", "#AA44AA", "#44AAAA", "#FF6666", "#66CC66", "#6666FF", "#FFCC22"],
    "Sodium Metamers B" => ["#CC6666", "#669966", "#6666CC", "#CCAA33", "#AA66AA", "#66AAAA", "#EE4444", "#44CC44", "#4444EE", "#EEAA11"]
  }

  def get_preset_palettes do
    @preset_palettes
    |> Enum.map(fn {name, colors} -> %{name: name, colors: colors, is_preset: true} end)
  end

  def get_preset_palette(name) do
    Map.get(@preset_palettes, name)
  end

  # Note: Actual localStorage operations will be handled in the LiveView 
  # using JavaScript hooks since Elixir runs server-side
  def encode_palette(name, colors) do
    %{name: name, colors: colors, is_preset: false}
    |> Jason.encode!()
  end

  def decode_palette(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"name" => name, "colors" => colors, "is_preset" => is_preset}} ->
        {:ok, %{name: name, colors: colors, is_preset: is_preset}}
      {:ok, _incomplete} ->
        {:error, "Missing required fields"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_palette_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    cond do
      trimmed == "" -> {:error, "Name cannot be empty"}
      String.length(trimmed) > 50 -> {:error, "Name too long (max 50 characters)"}
      Map.has_key?(@preset_palettes, trimmed) -> {:error, "Name conflicts with preset palette"}
      true -> {:ok, trimmed}
    end
  end

  def validate_palette_name(_), do: {:error, "Name must be a string"}
end
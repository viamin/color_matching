defmodule ColorMatching.PaletteStorage do
  @moduledoc """
  Handles storage and retrieval of color palettes using localStorage and provides preset palettes.

  ## How palette state moves between pages

  This app has no database, so palette data lives in the browser via two
  `localStorage` keys managed by the `PaletteStorage` JS hook
  (`assets/js/app.js`):

    * `color_matching_palettes` - the list of saved user palettes. This is
      the durable store for anything the user has explicitly saved, renamed,
      or duplicated. Its shape matches `ColorMatching.Palette.to_json_map/1`.
    * `color_matching_active_palette` - the single "currently selected"
      palette (name/colors/is_preset), used to hand off the in-progress
      palette between pages/reloads without requiring a server-side session.

  Every LiveView page that needs palette data mounts the same
  `PaletteStorage` hook, which loads both keys on mount and pushes them to
  the server as `palettes_updated` and `active_palette_loaded` events. Pages
  update the active palette by `push_event`-ing an `activate_palette` event,
  which the hook persists back to `localStorage` so any other page (current
  or future) picks up the same selection on its next mount.

  Saving, renaming, deleting, and duplicating palettes all go through
  `push_event`/`handleEvent` pairs with the hook (`save_palette`,
  `rename_palette`, `delete_palette`), keeping `PaletteStorage` (this
  module) as the single place that validates names and shapes data,
  while the hook is the only place that touches `localStorage` directly.
  """

  alias ColorMatching.Palette

  @preset_palettes %{
    "Warm" => [
      "#FF6B6B",
      "#FF8E53",
      "#FF6B35",
      "#F7931E",
      "#FFD23F",
      "#FFF07C",
      "#FF9F40",
      "#FF6B35",
      "#D63031",
      "#E84393"
    ],
    "Cool" => [
      "#74B9FF",
      "#0984E3",
      "#00B894",
      "#00CEC9",
      "#6C5CE7",
      "#A29BFE",
      "#FD79A8",
      "#FDCB6E",
      "#81ECEC",
      "#55A3FF"
    ],
    "Monochrome" => [
      "#2D3436",
      "#636E72",
      "#B2BEC3",
      "#DDD",
      "#FFF",
      "#F8F9FA",
      "#E9ECEF",
      "#DEE2E6",
      "#CED4DA",
      "#ADB5BD"
    ],
    "High Contrast" => [
      "#000000",
      "#FFFFFF",
      "#FF0000",
      "#00FF00",
      "#0000FF",
      "#FFFF00",
      "#FF00FF",
      "#00FFFF",
      "#FF8000",
      "#8000FF"
    ],
    "Earth Tones" => [
      "#8B4513",
      "#D2B48C",
      "#DEB887",
      "#F4A460",
      "#CD853F",
      "#A0522D",
      "#BC8F8F",
      "#F5DEB3",
      "#D2691E",
      "#B22222"
    ],
    "Pastels" => [
      "#FFB3BA",
      "#FFDFBA",
      "#FFFFBA",
      "#BAFFC9",
      "#BAE1FF",
      "#E1BAFF",
      "#FFBAE1",
      "#C9FFBA",
      "#BAFFE1",
      "#E1FFBA"
    ],
    "Vibrant" => [
      "#E74C3C",
      "#9B59B6",
      "#3498DB",
      "#1ABC9C",
      "#F1C40F",
      "#E67E22",
      "#95A5A6",
      "#34495E",
      "#F39C12",
      "#8E44AD"
    ],
    "Neon" => [
      "#FF073A",
      "#39FF14",
      "#FF0080",
      "#00FFFF",
      "#FFFF00",
      "#FF8C00",
      "#9400D3",
      "#00FF7F",
      "#FF1493",
      "#00BFFF"
    ],
    "Sodium Metamers A" => [
      "#FF4444",
      "#44AA44",
      "#4444FF",
      "#FFAA00",
      "#AA44AA",
      "#44AAAA",
      "#FF6666",
      "#66CC66",
      "#6666FF",
      "#FFCC22"
    ],
    "Sodium Metamers B" => [
      "#CC6666",
      "#669966",
      "#6666CC",
      "#CCAA33",
      "#AA66AA",
      "#66AAAA",
      "#EE4444",
      "#44CC44",
      "#4444EE",
      "#EEAA11"
    ],
    "LPS Street Light" => [
      "#D4AA00",
      "#C49C00",
      "#B48E00",
      "#FFDD33",
      "#FFE066",
      "#DDBB22",
      "#CCAA11",
      "#BB9900",
      "#AA8800",
      "#997700"
    ],
    "Sodium Industrial" => [
      "#FF9933",
      "#DD7711",
      "#BB5500",
      "#FFB844",
      "#FFCC55",
      "#EE9922",
      "#CC7700",
      "#AA5500",
      "#884400",
      "#663300"
    ],
    "Yellow Metamers" => [
      "#FFFF00",
      "#DDDD00",
      "#BBBB00",
      "#FFF033",
      "#FFE022",
      "#DDD011",
      "#CCC000",
      "#BBB000",
      "#AAA000",
      "#999000"
    ],
    "Orange Sodium" => [
      "#FF8C00",
      "#FF7F00",
      "#FF6600",
      "#FFB366",
      "#FFAA55",
      "#DD6622",
      "#CC5511",
      "#BB4400",
      "#AA3300",
      "#992200"
    ],
    "Warm Metamers" => [
      "#FFB347",
      "#FFAA33",
      "#FF9922",
      "#FFCC77",
      "#FFBB66",
      "#EE8833",
      "#DD7722",
      "#CC6611",
      "#BB5500",
      "#AA4400"
    ],
    "Sodium Variants" => [
      "#FFA500",
      "#FFB300",
      "#FFC100",
      "#FFCF00",
      "#FFDD00",
      "#FFEB00",
      "#FFF900",
      "#F0E600",
      "#E1D300",
      "#D2C000"
    ]
  }

  @spec get_preset_palettes() :: [Palette.t()]
  def get_preset_palettes do
    @preset_palettes
    |> Enum.map(fn {name, colors} ->
      Palette.new(%{name: name, colors: colors, is_preset: true})
    end)
  end

  @spec get_preset_palette(String.t()) :: [String.t()] | nil
  def get_preset_palette(name) do
    Map.get(@preset_palettes, name)
  end

  @spec preset_palette?(String.t()) :: boolean()
  def preset_palette?(name), do: Map.has_key?(@preset_palettes, name)

  # Note: Actual localStorage operations will be handled in the LiveView
  # using JavaScript hooks since Elixir runs server-side
  @spec encode_palette(String.t(), [String.t()]) :: String.t()
  def encode_palette(name, colors) do
    %{name: name, colors: colors, is_preset: false}
    |> Jason.encode!()
  end

  @spec decode_palette(String.t()) :: {:ok, Palette.t()} | {:error, String.t()}
  def decode_palette(json_string) do
    case Jason.decode(json_string) do
      {:ok, map} -> Palette.from_json_map(map)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate_palette_name(term()) :: {:ok, String.t()} | {:error, String.t()}
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

  @doc """
  Generates a unique name for duplicating `base_name` into an editable user
  palette, avoiding collisions with both preset names and any
  `existing_names` (typically the user's currently saved palettes).

  ## Examples

      iex> ColorMatching.PaletteStorage.duplicate_name("Warm", [])
      "Warm Copy"

      iex> ColorMatching.PaletteStorage.duplicate_name("Warm", ["Warm Copy"])
      "Warm Copy 2"

  """
  @spec duplicate_name(String.t(), [String.t()]) :: String.t()
  def duplicate_name(base_name, existing_names) do
    taken = MapSet.new(existing_names)

    Enum.reduce_while(1..1000, nil, fn n, _ ->
      candidate = if n == 1, do: "#{base_name} Copy", else: "#{base_name} Copy #{n}"

      if MapSet.member?(taken, candidate) or preset_palette?(candidate) do
        {:cont, nil}
      else
        {:halt, candidate}
      end
    end)
  end
end

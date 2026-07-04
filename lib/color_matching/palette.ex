defmodule ColorMatching.Palette do
  @moduledoc """
  Canonical data shape for a color palette.

  This struct is the durable representation shared by the grid page and the
  (future) palette management page. Both server-side preset palettes and
  client-side (`localStorage`) user palettes are normalized into this shape
  so the rest of the app only has to deal with one data structure.

  Fields:

    * `:name` - display name of the palette.
    * `:colors` - list of hex color strings.
    * `:is_preset` - whether this palette is a read-only, built-in preset.
      Preset palettes can never be edited or deleted, only duplicated into a
      new user palette.
    * `:created_at` - ISO-8601 timestamp string for user palettes, used as
      metadata for sorting/display. Presets do not carry a `created_at`.
  """

  @enforce_keys [:name, :colors]
  @derive Jason.Encoder
  defstruct name: nil,
            colors: [],
            is_preset: false,
            created_at: nil

  @type t :: %__MODULE__{
          name: String.t(),
          colors: [String.t()],
          is_preset: boolean(),
          created_at: String.t() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      name: fetch(attrs, :name),
      colors: fetch(attrs, :colors) || [],
      is_preset: fetch(attrs, :is_preset) || false,
      created_at: fetch(attrs, :created_at)
    }
  end

  @doc """
  Builds a palette from a JSON-decoded map (as produced by the browser's
  `localStorage` or by `Jason.decode/1`). Accepts either string or atom keys.
  """
  @spec from_json_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_json_map(map) when is_map(map) do
    name = fetch(map, :name)
    colors = fetch(map, :colors)

    if is_binary(name) and is_list(colors) do
      {:ok,
       new(%{
         name: name,
         colors: colors,
         is_preset: fetch(map, :is_preset) || false,
         created_at: fetch(map, :created_at)
       })}
    else
      {:error, "Missing required fields"}
    end
  end

  def from_json_map(_), do: {:error, "Missing required fields"}

  @doc """
  Converts a palette struct into a plain map with string keys, suitable for
  sending to the client or persisting as JSON.
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = palette) do
    %{
      "name" => palette.name,
      "colors" => palette.colors,
      "is_preset" => palette.is_preset,
      "created_at" => palette.created_at
    }
  end

  @doc """
  Builds an editable copy of a palette under a new name. Duplicates are
  always user palettes (`is_preset: false`), even when duplicating a preset,
  and are stamped with a fresh `created_at` timestamp.
  """
  @spec duplicate(t(), String.t()) :: t()
  def duplicate(%__MODULE__{} = palette, new_name) do
    %__MODULE__{
      name: new_name,
      colors: palette.colors,
      is_preset: false,
      created_at: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end

defmodule ColorMatching.ColorLabel do
  @moduledoc """
  Shared helpers for deriving the user-facing name of a color.
  """

  @spec normalize_or_hex(String.t() | nil, String.t()) :: String.t()
  def normalize_or_hex(label, hex_color) when is_binary(label) and is_binary(hex_color) do
    normalized_label = String.trim(label)

    if normalized_label == "", do: hex_color, else: normalized_label
  end

  def normalize_or_hex(_label, hex_color) when is_binary(hex_color), do: hex_color
end

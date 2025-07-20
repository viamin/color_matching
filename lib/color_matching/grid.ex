defmodule ColorMatching.Grid do
  @moduledoc """
  Handles grid generation and color matching logic.
  
  Creates a grid where:
  - Each row has the same top-left triangle color
  - Each column has the same bottom-right triangle color
  - Above the main diagonal: bottom-right triangles use inverted colors
  - Below the main diagonal: both triangles use original palette colors
  - On the main diagonal: bottom-right triangles are split (upper part inverted)
  """

  alias ColorMatching.ColorUtils

  defstruct [:colors, :size, :grid]

  def new(colors, size \\ 5) do
    %__MODULE__{
      colors: colors,
      size: size,
      grid: generate_grid(colors, size)
    }
  end

  defp generate_grid(colors, size) do
    for row <- 0..(size - 1) do
      for col <- 0..(size - 1) do
        base_color = Enum.at(colors, col)
        
        # Determine bottom-right triangle color based on position relative to main diagonal
        bottom_right_color = cond do
          # Above main diagonal: use inverted color
          row < col -> ColorUtils.invert_color(base_color)
          # Below main diagonal: use original color
          row > col -> base_color
          # On main diagonal: use original color (will be handled specially in UI for split effect)
          row == col -> base_color
        end

        %{
          row: row,
          col: col,
          top_left_color: Enum.at(colors, row),
          bottom_right_color: bottom_right_color,
          is_diagonal: row == col,
          use_inverted: row < col
        }
      end
    end
  end
end
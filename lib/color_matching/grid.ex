defmodule ColorMatching.Grid do
  @moduledoc """
  Handles grid generation and color matching logic.
  
  Creates a grid where:
  - Each row has the same top-left triangle color
  - Each column has the same bottom-right triangle color
  - Bottom-right triangles use the inverse of the selected color
  """

  alias ColorMatching.ColorUtils

  defstruct [:colors, :size, :grid, :inverse_colors]

  def new(colors, size \\ 5) do
    inverse_colors = Enum.map(colors, &ColorUtils.invert_color/1)
    
    %__MODULE__{
      colors: colors,
      size: size,
      inverse_colors: inverse_colors,
      grid: generate_grid(colors, inverse_colors, size)
    }
  end

  defp generate_grid(colors, inverse_colors, size) do
    for row <- 0..(size - 1) do
      for col <- 0..(size - 1) do
        %{
          row: row,
          col: col,
          top_left_color: Enum.at(colors, row),
          bottom_right_color: Enum.at(inverse_colors, col),
          original_bottom_right: Enum.at(colors, col)
        }
      end
    end
  end
end
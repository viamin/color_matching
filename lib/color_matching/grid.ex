defmodule ColorMatching.Grid do
  @moduledoc """
  Handles grid generation and color matching logic.
  
  Creates a grid where:
  - Each row has the same top-left triangle color
  - Each column has the same bottom-right triangle color
  - Both triangles use colors from the selected palette
  """

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
        %{
          row: row,
          col: col,
          top_left_color: Enum.at(colors, row),
          bottom_right_color: Enum.at(colors, col)
        }
      end
    end
  end
end
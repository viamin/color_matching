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

  @type cell :: %{
          row: non_neg_integer(),
          col: non_neg_integer(),
          top_left_color: String.t(),
          bottom_right_color: String.t(),
          is_diagonal: boolean(),
          use_inverted: boolean()
        }

  @type t :: %__MODULE__{
          colors: [String.t()],
          size: non_neg_integer(),
          grid: [[cell()]]
        }

  defstruct [:colors, :size, :grid]

  @spec new([String.t()], non_neg_integer()) :: t()
  def new(colors, size \\ 5) do
    %__MODULE__{
      colors: colors,
      size: size,
      grid: generate_grid(colors, size)
    }
  end

  @spec generate_grid([String.t()], non_neg_integer()) :: [[cell()]]
  defp generate_grid(colors, size) do
    for row <- 0..(size - 1) do
      for col <- 0..(size - 1) do
        base_color = Enum.at(colors, col)

        # Determine bottom-right triangle color based on position relative to main diagonal
        bottom_right_color =
          cond do
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

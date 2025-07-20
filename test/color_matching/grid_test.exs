defmodule ColorMatching.GridTest do
  use ExUnit.Case
  alias ColorMatching.Grid

  describe "new/2" do
    test "creates a grid with correct structure" do
      colors = ["#FF0000", "#00FF00", "#0000FF"]
      grid = Grid.new(colors, 3)

      assert grid.colors == colors
      assert grid.size == 3
      assert length(grid.grid) == 3
      assert length(Enum.at(grid.grid, 0)) == 3
    end

    test "uses default size of 5 when not specified" do
      colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF"]
      grid = Grid.new(colors)

      assert grid.size == 5
      assert length(grid.grid) == 5
    end

    test "uses original colors for both triangles" do
      colors = ["#FF0000", "#00FF00"]
      grid = Grid.new(colors, 2)

      # No more inverse_colors field - both triangles use original colors
      refute Map.has_key?(grid, :inverse_colors)
    end

    test "grid cells have correct structure" do
      colors = ["#FF0000", "#00FF00"]
      grid = Grid.new(colors, 2)

      cell = grid.grid |> Enum.at(0) |> Enum.at(0)
      
      assert cell.row == 0
      assert cell.col == 0
      assert cell.top_left_color == "#FF0000"
      assert cell.bottom_right_color == "#FF0000"
      refute Map.has_key?(cell, :original_bottom_right)
    end

    test "each row uses the same top-left color" do
      colors = ["#FF0000", "#00FF00", "#0000FF"]
      grid = Grid.new(colors, 3)

      # Check first row
      first_row = Enum.at(grid.grid, 0)
      assert Enum.all?(first_row, fn cell -> cell.top_left_color == "#FF0000" end)

      # Check second row
      second_row = Enum.at(grid.grid, 1)
      assert Enum.all?(second_row, fn cell -> cell.top_left_color == "#00FF00" end)
    end

    test "each column uses the same bottom-right color" do
      colors = ["#FF0000", "#00FF00", "#0000FF"]
      grid = Grid.new(colors, 3)

      # Check first column - should use first color from palette
      first_col_cells = Enum.map(grid.grid, fn row -> Enum.at(row, 0) end)
      assert Enum.all?(first_col_cells, fn cell -> cell.bottom_right_color == "#FF0000" end)

      # Check second column - should use second color from palette
      second_col_cells = Enum.map(grid.grid, fn row -> Enum.at(row, 1) end)
      assert Enum.all?(second_col_cells, fn cell -> cell.bottom_right_color == "#00FF00" end)
    end

    test "handles single color" do
      colors = ["#FF0000"]
      grid = Grid.new(colors, 1)

      assert grid.size == 1
      assert length(grid.grid) == 1
      assert length(Enum.at(grid.grid, 0)) == 1

      cell = grid.grid |> Enum.at(0) |> Enum.at(0)
      assert cell.top_left_color == "#FF0000"
      assert cell.bottom_right_color == "#FF0000"
    end

    test "handles small size" do
      colors = ["#FF0000"]
      grid = Grid.new(colors, 1)

      assert grid.colors == ["#FF0000"]
      assert grid.size == 1
      assert length(grid.grid) == 1
      assert length(Enum.at(grid.grid, 0)) == 1
    end
  end
end
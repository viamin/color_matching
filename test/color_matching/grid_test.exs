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

    test "creates diagonal split pattern correctly" do
      colors = ["#FF0000", "#00FF00"]
      grid = Grid.new(colors, 2)

      # Grid should have cells with diagonal split logic
      # Check that cells have the new fields
      cell = grid.grid |> Enum.at(0) |> Enum.at(0)
      assert Map.has_key?(cell, :is_diagonal)
      assert Map.has_key?(cell, :use_inverted)
    end

    test "grid cells have correct structure" do
      colors = ["#FF0000", "#00FF00"]
      grid = Grid.new(colors, 2)

      cell = grid.grid |> Enum.at(0) |> Enum.at(0)

      assert cell.row == 0
      assert cell.col == 0
      assert cell.top_left_color == "#FF0000"
      assert cell.bottom_right_color == "#FF0000"
      assert cell.is_diagonal == true
      assert cell.use_inverted == false
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

    test "diagonal split creates correct color patterns" do
      colors = ["#FF0000", "#00FF00", "#0000FF"]
      grid = Grid.new(colors, 3)

      # Check pattern: above diagonal should use inverted colors
      # row 0, col 1
      cell_0_1 = grid.grid |> Enum.at(0) |> Enum.at(1)
      # inverted #00FF00
      assert cell_0_1.bottom_right_color == "#FF00FF"
      assert cell_0_1.use_inverted == true

      # Check pattern: below diagonal should use original colors
      # row 1, col 0
      cell_1_0 = grid.grid |> Enum.at(1) |> Enum.at(0)
      # original
      assert cell_1_0.bottom_right_color == "#FF0000"
      assert cell_1_0.use_inverted == false

      # Check pattern: on diagonal should use original colors
      # row 1, col 1
      cell_1_1 = grid.grid |> Enum.at(1) |> Enum.at(1)
      # original
      assert cell_1_1.bottom_right_color == "#00FF00"
      assert cell_1_1.is_diagonal == true
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
      assert cell.is_diagonal == true
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

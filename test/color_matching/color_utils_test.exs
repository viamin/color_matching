defmodule ColorMatching.ColorUtilsTest do
  use ExUnit.Case
  alias ColorMatching.ColorUtils

  describe "invert_color/1" do
    test "inverts 6-character hex colors correctly" do
      assert ColorUtils.invert_color("#FF0000") == "#00FFFF"
      assert ColorUtils.invert_color("#00FF00") == "#FF00FF"
      assert ColorUtils.invert_color("#0000FF") == "#FFFF00"
      assert ColorUtils.invert_color("#FFFFFF") == "#000000"
      assert ColorUtils.invert_color("#000000") == "#FFFFFF"
    end

    test "handles lowercase hex colors" do
      assert ColorUtils.invert_color("#ff0000") == "#00FFFF"
      assert ColorUtils.invert_color("#abc123") == "#543EDC"
    end

    test "inverts 3-character hex colors by expanding them" do
      assert ColorUtils.invert_color("#F00") == "#00FFFF"
      assert ColorUtils.invert_color("#0F0") == "#FF00FF"
      assert ColorUtils.invert_color("#00F") == "#FFFF00"
      assert ColorUtils.invert_color("#FFF") == "#000000"
      assert ColorUtils.invert_color("#000") == "#FFFFFF"
    end

    test "handles mixed case 3-character hex colors" do
      assert ColorUtils.invert_color("#f0A") == "#00FF55"
    end

    test "returns unchanged color for invalid formats" do
      assert ColorUtils.invert_color("invalid") == "invalid"
      assert ColorUtils.invert_color("#FF00") == "#FF00"
      assert ColorUtils.invert_color("FF0000") == "FF0000"
      assert ColorUtils.invert_color("") == ""
    end

    test "handles edge cases with proper padding" do
      assert ColorUtils.invert_color("#010101") == "#FEFEFE"
      assert ColorUtils.invert_color("#0F0F0F") == "#F0F0F0"
    end
  end

  describe "random_color/0" do
    test "generates a valid 6-character hex color" do
      color = ColorUtils.random_color()

      assert String.starts_with?(color, "#")
      assert String.length(color) == 7

      hex_part = String.slice(color, 1, 6)
      assert String.match?(hex_part, ~r/^[0-9A-F]{6}$/)
    end

    test "generates different colors on multiple calls" do
      colors = for _ <- 1..10, do: ColorUtils.random_color()
      unique_colors = Enum.uniq(colors)

      # Should be very unlikely to get all the same color
      assert length(unique_colors) > 1
    end

    test "generated colors can be inverted" do
      color = ColorUtils.random_color()
      inverted = ColorUtils.invert_color(color)

      assert String.starts_with?(inverted, "#")
      assert String.length(inverted) == 7
      refute color == inverted
    end

    test "inversion is reversible" do
      color = ColorUtils.random_color()
      double_inverted = color |> ColorUtils.invert_color() |> ColorUtils.invert_color()

      assert color == double_inverted
    end
  end

  describe "parse_hex_color/1 (private function behavior)" do
    test "invert_color properly parses different hex values" do
      # Test edge cases that would reveal parsing issues
      assert ColorUtils.invert_color("#123456") == "#EDCBA9"
      assert ColorUtils.invert_color("#ABCDEF") == "#543210"
      assert ColorUtils.invert_color("#fedcba") == "#012345"
    end
  end
end

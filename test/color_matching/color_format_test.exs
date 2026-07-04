defmodule ColorMatching.ColorFormatTest do
  use ExUnit.Case
  alias ColorMatching.ColorFormat

  describe "normalize_hex/1" do
    test "accepts 6-digit hex colors and upcases them" do
      assert ColorFormat.normalize_hex("#ff6b6b") == {:ok, "#FF6B6B"}
      assert ColorFormat.normalize_hex("#FF6B6B") == {:ok, "#FF6B6B"}
    end

    test "expands 3-digit shorthand hex colors" do
      assert ColorFormat.normalize_hex("#fff") == {:ok, "#FFFFFF"}
      assert ColorFormat.normalize_hex("#F00") == {:ok, "#FF0000"}
    end

    test "trims surrounding whitespace" do
      assert ColorFormat.normalize_hex("  #FFF  ") == {:ok, "#FFFFFF"}
    end

    test "rejects invalid hex colors" do
      assert {:error, _} = ColorFormat.normalize_hex("invalid")
      assert {:error, _} = ColorFormat.normalize_hex("FF0000")
      assert {:error, _} = ColorFormat.normalize_hex("#FF00")
      assert {:error, _} = ColorFormat.normalize_hex("#GGGGGG")
      assert {:error, _} = ColorFormat.normalize_hex("")
    end

    test "rejects non-string input" do
      assert ColorFormat.normalize_hex(nil) == {:error, "Hex color must be a string"}
    end
  end

  describe "hex_to_rgb/1 and rgb_to_hex/1" do
    test "converts hex to rgb" do
      assert ColorFormat.hex_to_rgb("#FF6B6B") == {:ok, {255, 107, 107}}
      assert ColorFormat.hex_to_rgb("#000000") == {:ok, {0, 0, 0}}
      assert ColorFormat.hex_to_rgb("#FFFFFF") == {:ok, {255, 255, 255}}
    end

    test "expands short hex codes before converting" do
      assert ColorFormat.hex_to_rgb("#F00") == {:ok, {255, 0, 0}}
    end

    test "converts rgb back to hex" do
      assert ColorFormat.rgb_to_hex({255, 107, 107}) == {:ok, "#FF6B6B"}
      assert ColorFormat.rgb_to_hex({0, 0, 0}) == {:ok, "#000000"}
      assert ColorFormat.rgb_to_hex({255, 255, 255}) == {:ok, "#FFFFFF"}
    end

    test "round-trips hex -> rgb -> hex" do
      for hex <- ["#FF6B6B", "#4ECDC4", "#000000", "#FFFFFF", "#808080"] do
        assert {:ok, rgb} = ColorFormat.hex_to_rgb(hex)
        assert ColorFormat.rgb_to_hex(rgb) == {:ok, hex}
      end
    end

    test "rejects invalid hex input" do
      assert {:error, _} = ColorFormat.hex_to_rgb("not-a-color")
    end

    test "rejects out-of-range or non-integer rgb values" do
      assert {:error, _} = ColorFormat.rgb_to_hex({256, 0, 0})
      assert {:error, _} = ColorFormat.rgb_to_hex({-1, 0, 0})
      assert {:error, _} = ColorFormat.rgb_to_hex({1.5, 0, 0})
    end
  end

  describe "parse_rgb/1 and format_rgb/1" do
    test "parses rgb(...) strings" do
      assert ColorFormat.parse_rgb("rgb(255, 107, 107)") == {:ok, {255, 107, 107}}
      assert ColorFormat.parse_rgb("rgb(0,0,0)") == {:ok, {0, 0, 0}}
    end

    test "parses rgba(...) strings, ignoring the alpha channel" do
      assert ColorFormat.parse_rgb("rgba(255, 107, 107, 0.5)") == {:ok, {255, 107, 107}}
    end

    test "formats an rgb tuple" do
      assert ColorFormat.format_rgb({255, 107, 107}) == "rgb(255, 107, 107)"
    end

    test "rejects out-of-range channel values" do
      assert ColorFormat.parse_rgb("rgb(300, 0, 0)") ==
               {:error, "RGB values must be between 0 and 255"}

      assert ColorFormat.parse_rgb("rgb(-1, 0, 0)") ==
               {:error, "RGB values must be between 0 and 255"}
    end

    test "rejects malformed input" do
      assert {:error, _} = ColorFormat.parse_rgb("255, 107, 107")
      assert {:error, _} = ColorFormat.parse_rgb("rgb(255, 107)")
      assert {:error, _} = ColorFormat.parse_rgb("not a color")
    end
  end

  describe "hex_to_hsl/1 and hsl_to_hex/1" do
    test "converts a known color to hsl" do
      assert ColorFormat.hex_to_hsl("#FF6B6B") == {:ok, {0, 100, 71}}
    end

    test "handles black, white, and gray (zero saturation)" do
      assert ColorFormat.hex_to_hsl("#000000") == {:ok, {0, 0, 0}}
      assert ColorFormat.hex_to_hsl("#FFFFFF") == {:ok, {0, 0, 100}}
      assert ColorFormat.hex_to_hsl("#808080") == {:ok, {0, 0, 50}}
    end

    test "converts hsl back to hex" do
      assert ColorFormat.hsl_to_hex({0, 100, 71}) == {:ok, "#FF6B6B"}
      assert ColorFormat.hsl_to_hex({0, 0, 0}) == {:ok, "#000000"}
      assert ColorFormat.hsl_to_hex({0, 0, 100}) == {:ok, "#FFFFFF"}
    end

    test "round-trips hex -> hsl -> hex within rounding tolerance" do
      # HSL is displayed/edited as whole-number percentages, so converting
      # back to hex can differ from the original by a channel or two due to
      # rounding - this is expected and matches how color pickers behave.
      for hex <- ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#000000", "#FFFFFF"] do
        assert {:ok, hsl} = ColorFormat.hex_to_hsl(hex)
        assert {:ok, round_tripped} = ColorFormat.hsl_to_hex(hsl)
        assert_hex_close(round_tripped, hex)
      end
    end

    test "rejects out-of-range saturation/lightness" do
      assert {:error, _} = ColorFormat.hsl_to_rgb({0, 150, 50})
      assert {:error, _} = ColorFormat.hsl_to_rgb({0, 50, -1})
    end
  end

  describe "parse_hsl/1 and format_hsl/1" do
    test "parses hsl(...) strings" do
      assert ColorFormat.parse_hsl("hsl(0, 100%, 71%)") == {:ok, {0, 100, 71}}
    end

    test "wraps hue values outside of 0-360" do
      assert ColorFormat.parse_hsl("hsl(370, 100%, 50%)") == {:ok, {10, 100, 50}}
      assert ColorFormat.parse_hsl("hsl(-10, 100%, 50%)") == {:ok, {350, 100, 50}}
      assert ColorFormat.parse_hsl("hsl(360, 100%, 50%)") == {:ok, {0, 100, 50}}
    end

    test "formats an hsl tuple" do
      assert ColorFormat.format_hsl({0, 100, 71}) == "hsl(0, 100%, 71%)"
    end

    test "rejects saturation/lightness outside of 0%-100%" do
      assert ColorFormat.parse_hsl("hsl(0, 150%, 50%)") ==
               {:error, "HSL saturation and lightness must be between 0% and 100%"}

      assert ColorFormat.parse_hsl("hsl(0, 50%, -10%)") ==
               {:error, "HSL saturation and lightness must be between 0% and 100%"}
    end

    test "rejects malformed input" do
      assert {:error, _} = ColorFormat.parse_hsl("hsl(0, 100, 71)")
      assert {:error, _} = ColorFormat.parse_hsl("not a color")
    end
  end

  describe "hex_to_hsv/1 and hsv_to_hex/1" do
    test "converts a known color to hsv" do
      assert ColorFormat.hex_to_hsv("#FF6B6B") == {:ok, {0, 58, 100}}
    end

    test "handles black, white, and gray (zero saturation)" do
      assert ColorFormat.hex_to_hsv("#000000") == {:ok, {0, 0, 0}}
      assert ColorFormat.hex_to_hsv("#FFFFFF") == {:ok, {0, 0, 100}}
      assert ColorFormat.hex_to_hsv("#808080") == {:ok, {0, 0, 50}}
    end

    test "converts hsv back to hex" do
      assert ColorFormat.hsv_to_hex({0, 58, 100}) == {:ok, "#FF6B6B"}
      assert ColorFormat.hsv_to_hex({0, 0, 0}) == {:ok, "#000000"}
      assert ColorFormat.hsv_to_hex({0, 0, 100}) == {:ok, "#FFFFFF"}
    end

    test "round-trips hex -> hsv -> hex within rounding tolerance" do
      # See note above about whole-number percentage rounding.
      for hex <- ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#000000", "#FFFFFF"] do
        assert {:ok, hsv} = ColorFormat.hex_to_hsv(hex)
        assert {:ok, round_tripped} = ColorFormat.hsv_to_hex(hsv)
        assert_hex_close(round_tripped, hex)
      end
    end

    test "rejects out-of-range saturation/value" do
      assert {:error, _} = ColorFormat.hsv_to_rgb({0, 150, 50})
      assert {:error, _} = ColorFormat.hsv_to_rgb({0, 50, -1})
    end
  end

  describe "parse_hsv/1 and format_hsv/1" do
    test "parses hsv(...) strings" do
      assert ColorFormat.parse_hsv("hsv(0, 58%, 100%)") == {:ok, {0, 58, 100}}
    end

    test "parses hsb(...) as an alias for hsv" do
      assert ColorFormat.parse_hsv("hsb(0, 58%, 100%)") == {:ok, {0, 58, 100}}
    end

    test "wraps hue values outside of 0-360" do
      assert ColorFormat.parse_hsv("hsv(400, 58%, 100%)") == {:ok, {40, 58, 100}}
    end

    test "formats an hsv tuple" do
      assert ColorFormat.format_hsv({0, 58, 100}) == "hsv(0, 58%, 100%)"
    end

    test "rejects saturation/value outside of 0%-100%" do
      assert ColorFormat.parse_hsv("hsv(0, 150%, 50%)") ==
               {:error, "HSV saturation and value must be between 0% and 100%"}
    end

    test "rejects malformed input" do
      assert {:error, _} = ColorFormat.parse_hsv("hsv(0, 58, 100)")
      assert {:error, _} = ColorFormat.parse_hsv("not a color")
    end
  end

  describe "normalization of equivalent inputs" do
    test "different hex casings and rgb/hsl/hsv representations resolve to the same color" do
      assert {:ok, from_hex} = ColorFormat.normalize_hex("#ff6b6b")

      assert {:ok, from_rgb} =
               ColorFormat.parse_rgb("rgb(255, 107, 107)")
               |> then(fn {:ok, rgb} -> ColorFormat.rgb_to_hex(rgb) end)

      assert {:ok, from_hsl} =
               ColorFormat.parse_hsl("hsl(360, 100%, 71%)")
               |> then(fn {:ok, hsl} -> ColorFormat.hsl_to_hex(hsl) end)

      assert from_hex == from_rgb
      assert from_hex == from_hsl
    end
  end

  # Asserts that two hex colors are equal within a small per-channel
  # tolerance, to account for rounding when a color is displayed/edited as
  # whole-number HSL/HSV percentages.
  defp assert_hex_close(actual_hex, expected_hex) do
    {:ok, {ar, ag, ab}} = ColorFormat.hex_to_rgb(actual_hex)
    {:ok, {er, eg, eb}} = ColorFormat.hex_to_rgb(expected_hex)

    assert abs(ar - er) <= 2 and abs(ag - eg) <= 2 and abs(ab - eb) <= 2,
           "expected #{actual_hex} to be close to #{expected_hex}"
  end
end

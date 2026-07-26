defmodule ColorMatching.ColorSpaceTest do
  use ExUnit.Case

  alias ColorMatching.ColorSpace

  describe "color-space conversions" do
    test "converts white from sRGB to linear RGB, XYZ, Lab, and xyY" do
      assert {:ok, {1.0, 1.0, 1.0}} = ColorSpace.hex_to_linear_rgb("#FFFFFF")

      assert {:ok, {x, y, z}} = ColorSpace.hex_to_xyz("#FFFFFF")
      assert_in_delta x, 0.95047, 0.0001
      assert_in_delta y, 1.0, 0.0001
      assert_in_delta z, 1.08883, 0.0001

      assert {:ok, {l, a, b}} = ColorSpace.hex_to_lab("#FFFFFF")
      assert_in_delta l, 100.0, 0.0001
      assert_in_delta a, 0.0, 0.0001
      assert_in_delta b, 0.0, 0.0001

      assert {:ok, {xyy_x, xyy_y, xyy_y_luminance}} = ColorSpace.hex_to_xyy("#FFFFFF")
      assert_in_delta xyy_x, 0.3127, 0.0001
      assert_in_delta xyy_y, 0.3290, 0.0001
      assert_in_delta xyy_y_luminance, 1.0, 0.0001
    end

    test "computes expected perceptual coordinates for red" do
      assert {:ok, {l, a, b}} = ColorSpace.hex_to_lab("#FF0000")
      assert_in_delta l, 53.2408, 0.0001
      assert_in_delta a, 80.0925, 0.0001
      assert_in_delta b, 67.2032, 0.0001

      assert {:ok, {ok_l, ok_a, ok_b}} = ColorSpace.hex_to_oklab("#FF0000")
      assert_in_delta ok_l, 0.6280, 0.0001
      assert_in_delta ok_a, 0.2249, 0.0001
      assert_in_delta ok_b, 0.1258, 0.0001
    end
  end

  describe "ciede2000/2" do
    test "returns zero for identical colors" do
      assert {:ok, delta_e} = ColorSpace.ciede2000("#ABCDEF", "#ABCDEF")
      assert_in_delta delta_e, 0.0, 0.0001
    end

    test "computes CIEDE2000 difference between distinct colors" do
      assert {:ok, delta_e} = ColorSpace.ciede2000("#ABCDEF", "#123456")
      assert_in_delta delta_e, 59.9350, 0.0001
    end
  end
end

defmodule ColorMatchingWeb.ColorPairLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "ColorPairLive" do
    test "renders two selected colors with all supported representations", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/pair?a=%23ABCDEF&b=%23123456")

      assert html =~ "Color Pair"
      assert html =~ "#ABCDEF"
      assert html =~ "#123456"
      assert html =~ "rgb(171, 205, 239)"
      assert html =~ "hsl(210, 68%, 80%)"
      assert html =~ "hsv(210, 28%, 94%)"
      refute html =~ "hsb(210, 28%, 94%)"
      assert html =~ "Linear RGB"
      assert html =~ "R: 0.4072, G: 0.6105, B: 0.8632"
      assert html =~ "CIE XYZ"
      assert html =~ "CIE Lab"
      assert html =~ "CIE LCh"
      assert html =~ "CIE xyY"
      assert html =~ "OKLab"
      assert html =~ "OKLCh"
      assert html =~ "Relative luminance (Y)"
      assert html =~ "rgb(18, 52, 86)"
      assert html =~ "Pair Metrics"
      assert html =~ "CIEDE2000 (ΔE00)"
      assert html =~ "59.9350"
      assert html =~ "Back to grid"
    end

    test "renders a validation error for bad query params", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/pair?a=bad&b=%23123456")

      assert html =~ "Color Pair"
      assert html =~ "Hex color must start with # followed by 3 or 6 hex digits"
    end

    test "renders default printer profile and generated sheet context from profile_id", %{
      conn: conn
    } do
      {:ok, _view, html} =
        live(
          conn,
          "/pair?a=%23ABCDEF&b=%23123456&sheet_id=sheet-demo&profile_id=epson-p900-ultrapremium-luster-oem"
        )

      assert html =~ "Measurement Context"
      assert html =~ "Epson SureColor P900 on Ultra Premium Luster"
      assert html =~ "Generated sheet: sheet-demo"
    end

    test "rebuilds custom printer profile context directly from query params", %{conn: conn} do
      {:ok, _view, html} =
        live(
          conn,
          "/pair?a=%23ABCDEF&b=%23123456&sheet_id=sheet-demo&profile_id=profile-demo" <>
            "&profile_printer_make_model=Epson+SureColor+P900" <>
            "&profile_paper_type=Premium+Luster" <>
            "&profile_ink_type=OEM+pigment"
        )

      assert html =~ "Measurement Context"
      assert html =~ "Epson SureColor P900 on Premium Luster"
      assert html =~ "Generated sheet: sheet-demo"
    end
  end
end

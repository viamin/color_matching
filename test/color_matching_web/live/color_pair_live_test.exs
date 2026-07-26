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
      assert html =~ "rgb(18, 52, 86)"
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

    test "hydrates custom printer profile context from local storage payload", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/pair?a=%23ABCDEF&b=%23123456&sheet_id=sheet-demo&profile_id=profile-demo")

      html =
        render_hook(view, "printer_profiles_loaded", %{
          "profiles" => [
            %{
              "id" => "profile-demo",
              "printer_make_model" => "Epson SureColor P900",
              "paper_type" => "Premium Luster",
              "ink_type" => "OEM pigment",
              "notes" => "Private note"
            }
          ]
        })

      assert html =~ "Measurement Context"
      assert html =~ "Epson SureColor P900 on Premium Luster"
      assert html =~ "Generated sheet: sheet-demo"
    end
  end
end

defmodule ColorMatchingWeb.PrintedPairBrowserLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  alias ColorMatching.Persistence

  describe "PrintedPairBrowserLive" do
    test "renders a compact empty state when there are no classifications", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/printed-pairs")

      assert html =~ "Printed Pair Browser"
      assert html =~ "No printed pair classifications yet."
      assert html =~ "All illuminants"
      assert html =~ "All classifications"
    end

    test "renders classified pairs and a compact no-results state for filtered misses", %{
      conn: conn
    } do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_fixture()

      assert {:ok, _classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Review under sodium vapor."
               })

      {:ok, view, html} = live(conn, ~p"/printed-pairs")

      assert html =~ pair.pair_id
      assert html =~ "#112233"
      assert html =~ "#445566"
      assert html =~ "Strong metamer"
      assert html =~ "Notes available"
      assert html =~ "Review under sodium vapor."

      html =
        render_change(view, "change_filters", %{
          "filters" => %{"classification" => "contrasting", "sort" => "recent"}
        })

      assert html =~ "No results match the current filters."
      refute html =~ pair.pair_id
    end

    test "is linked from the grid page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Browse Printed Pairs"
      assert html =~ "/printed-pairs"
    end
  end

  defp printed_pair_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Browser Fixture",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"},
                 %{hex_color: "#445566", sort_order: 1, display_label: "Patch 2"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    assert {:ok, sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "BRWX-SE23",
               palette_id: palette.id,
               printer_profile_id: printer_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#112233", color_b_hex: "#445566"}
               ]
             })

    %{pair: List.first(sheet.pairs), printer_profile: printer_profile}
  end
end

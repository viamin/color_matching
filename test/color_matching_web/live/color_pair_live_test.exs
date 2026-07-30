defmodule ColorMatchingWeb.ColorPairLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  alias ColorMatching.Persistence

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
      assert html =~ "Manual Illuminant Classification"
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

    test "renders classification controls and profile context for a persisted pair", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile, sheet: sheet} = printed_pair_fixture()

      {:ok, _view, html} =
        live(
          conn,
          pair_path(pair, sheet, printer_profile)
        )

      assert html =~ "Manual Illuminant Classification"
      assert html =~ "Reproduction profile for classification"
      assert html =~ printer_profile.printer_make_model
      assert html =~ printer_profile.paper_type
      assert html =~ printer_profile.ink_type
      assert html =~ "LPS"
      assert html =~ "Red"
      assert html =~ "Green"
      assert html =~ "Blue"
      assert html =~ "Notes (optional)"
      assert html =~ "Pair Metrics"
    end

    test "saves a classification with optional notes", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile, sheet: sheet} = printed_pair_fixture()

      {:ok, view, _html} =
        live(
          conn,
          pair_path(pair, sheet, printer_profile)
        )

      html =
        render_submit(view, "save_classification", %{
          "classification" => %{
            "illuminant" => "lps",
            "classification" => "strong_metamer",
            "notes" => "Apparent brightness stays closely aligned"
          }
        })

      assert html =~ "Saved LPS classification"
      assert html =~ "Strong metamer"

      persisted =
        Persistence.get_active_printed_pair_classification(pair.id, printer_profile.id, "lps")

      assert persisted.classification == "strong_metamer"
      assert persisted.notes == "Apparent brightness stays closely aligned"
    end

    test "updates an existing classification for the same illuminant", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile, sheet: sheet} = printed_pair_fixture()

      assert {:ok, _classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "red",
                 classification: "weak_metamer",
                 notes: "Initial read"
               })

      {:ok, view, _html} =
        live(
          conn,
          pair_path(pair, sheet, printer_profile)
        )

      html =
        render_submit(view, "save_classification", %{
          "classification" => %{
            "illuminant" => "red",
            "classification" => "contrasting",
            "notes" => "Response separates immediately"
          }
        })

      assert html =~ "Saved Red classification"
      assert html =~ "Contrasting"

      active =
        Persistence.get_active_printed_pair_classification(pair.id, printer_profile.id, "red")

      history =
        Persistence.list_printed_pair_classification_history(pair.id, printer_profile.id, "red")

      assert active.classification == "contrasting"
      assert active.notes == "Response separates immediately"
      assert Enum.count(history, & &1.active) == 1
      assert length(history) == 2
    end

    test "clears an existing classification without leaving the page", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile, sheet: sheet} = printed_pair_fixture()

      assert {:ok, _classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "blue",
                 classification: "strong_metamer",
                 notes: "Before clearing"
               })

      {:ok, view, _html} =
        live(
          conn,
          pair_path(pair, sheet, printer_profile)
        )

      html = render_click(view, "clear_classification", %{"illuminant" => "blue"})

      assert html =~ "Cleared Blue classification"
      assert html =~ "Unset"

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               printer_profile.id,
               "blue"
             ) == nil

      [persisted] =
        Persistence.list_printed_pair_classification_history(pair.id, printer_profile.id, "blue")

      assert persisted.notes == "Before clearing"
      refute persisted.active
    end

    test "uses pair_id to target the correct persisted pair when sheet colors repeat", %{
      conn: conn
    } do
      %{
        first_pair: first_pair,
        second_pair: second_pair,
        printer_profile: printer_profile,
        sheet: sheet
      } = duplicate_color_pair_fixture()

      {:ok, view, _html} = live(conn, pair_path(second_pair, sheet, printer_profile))

      html =
        render_submit(view, "save_classification", %{
          "classification" => %{
            "illuminant" => "green",
            "classification" => "contrasting",
            "notes" => "Second pair only"
          }
        })

      assert html =~ "Saved Green classification"
      assert html =~ "Contrasting"

      assert Persistence.get_active_printed_pair_classification(
               first_pair.id,
               printer_profile.id,
               "green"
             ) == nil

      persisted =
        Persistence.get_active_printed_pair_classification(
          second_pair.id,
          printer_profile.id,
          "green"
        )

      assert persisted.classification == "contrasting"
      assert persisted.notes == "Second pair only"
    end

    test "ignores reproduction_profile_id in the query string and uses the sheet's own profile",
         %{conn: conn} do
      %{
        pair: pair,
        printer_profile: sheet_profile,
        other_profile,
        sheet: sheet
      } = mismatched_profile_fixture()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/pair?#{[
            a: pair.color_a_hex,
            b: pair.color_b_hex,
            sheet_id: sheet.lookup_code,
            pair_id: pair.pair_id,
            reproduction_profile_id: other_profile.id
          ]}"
        )

      html =
        render_submit(view, "save_classification", %{
          "classification" => %{
            "illuminant" => "lps",
            "classification" => "strong_metamer",
            "notes" => "Bound to the sheet's profile"
          }
        })

      assert html =~ "Saved LPS classification"

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               sheet_profile.id,
               "lps"
             ).classification == "strong_metamer"

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               other_profile.id,
               "lps"
             ) == nil
    end

    test "ignores printer_profile_id in the query string and uses the sheet's own profile",
         %{conn: conn} do
      %{
        pair: pair,
        printer_profile: sheet_profile,
        other_profile,
        sheet: sheet
      } = mismatched_profile_fixture()

      assert {:ok, _classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: sheet_profile.id,
                 illuminant: "red",
                 classification: "weak_metamer",
                 notes: "Sheet's own profile"
               })

      assert {:ok, _other_classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: other_profile.id,
                 illuminant: "red",
                 classification: "contrasting",
                 notes: "Unrelated profile"
               })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/pair?#{[
            a: pair.color_a_hex,
            b: pair.color_b_hex,
            sheet_id: sheet.lookup_code,
            pair_id: pair.pair_id,
            printer_profile_id: other_profile.id
          ]}"
        )

      html = render_click(view, "clear_classification", %{"illuminant" => "red"})

      assert html =~ "Cleared Red classification"

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               sheet_profile.id,
               "red"
             ) == nil

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               other_profile.id,
               "red"
             ).classification == "contrasting"
    end
  end

  defp pair_path(pair, sheet, printer_profile) do
    ~p"/pair?#{[a: pair.color_a_hex, b: pair.color_b_hex, sheet_id: sheet.lookup_code, pair_id: pair.pair_id, reproduction_profile_id: printer_profile.id]}"
  end

  defp printed_pair_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Pair Detail Fixture",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"},
                 %{hex_color: "#445566", sort_order: 1, display_label: "Patch 2"},
                 %{hex_color: "#778899", sort_order: 2, display_label: "Patch 3"}
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
               lookup_code: "PARK-TEST",
               palette_id: palette.id,
               printer_profile_id: printer_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#112233", color_b_hex: "#445566"},
                 %{row: 0, col: 1, color_a_hex: "#112233", color_b_hex: "#778899"}
               ]
             })

    [_, pair] = sheet.pairs

    %{pair: pair, printer_profile: printer_profile, sheet: sheet}
  end

  defp duplicate_color_pair_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Duplicate Pair Fixture",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"},
                 %{hex_color: "#445566", sort_order: 1, display_label: "Patch 2"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Canon imagePROGRAF PRO-1100",
               paper_type: "Luster",
               ink_type: "OEM Lucia PRO II"
             })

    assert {:ok, sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "DUPL-PA2R",
               palette_id: palette.id,
               printer_profile_id: printer_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#112233", color_b_hex: "#445566"},
                 %{row: 0, col: 1, color_a_hex: "#112233", color_b_hex: "#445566"}
               ]
             })

    [first_pair, second_pair] = sheet.pairs

    %{
      first_pair: first_pair,
      second_pair: second_pair,
      printer_profile: printer_profile,
      sheet: sheet
    }
  end

  defp mismatched_profile_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Mismatched Profile Fixture",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"},
                 %{hex_color: "#445566", sort_order: 1, display_label: "Patch 2"}
               ]
             })

    assert {:ok, sheet_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    assert {:ok, other_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Canon imagePROGRAF PRO-1100",
               paper_type: "Luster",
               ink_type: "OEM Lucia PRO II"
             })

    assert {:ok, sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "PRHF-G6SH",
               palette_id: palette.id,
               printer_profile_id: sheet_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#112233", color_b_hex: "#445566"}
               ]
             })

    [pair] = sheet.pairs

    %{
      pair: pair,
      printer_profile: sheet_profile,
      other_profile: other_profile,
      sheet: sheet
    }
  end
end

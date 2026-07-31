defmodule ColorMatching.PrintedPairBrowserTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.{Persistence, PrintedPairBrowser, Repo}
  alias ColorMatching.Persistence.PrintedPairClassification

  describe "list_entries/1" do
    test "filters by classification context including profile, palette, and sheet" do
      %{
        primary_pair: primary_pair,
        secondary_pair: secondary_pair,
        primary_profile: primary_profile,
        secondary_profile: secondary_profile,
        primary_sheet: primary_sheet,
        secondary_sheet: secondary_sheet,
        primary_palette: primary_palette,
        secondary_palette: secondary_palette
      } = printed_pair_browser_fixture()

      assert {:ok, matching} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: primary_pair.id,
                 reproduction_profile_id: primary_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Target row"
               })

      assert {:ok, _other_classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: primary_pair.id,
                 reproduction_profile_id: primary_profile.id,
                 illuminant: "red",
                 classification: "weak_metamer"
               })

      assert {:ok, _other_profile} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: primary_pair.id,
                 reproduction_profile_id: secondary_profile.id,
                 illuminant: "red",
                 classification: "strong_metamer"
               })

      assert {:ok, _other_palette} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: secondary_pair.id,
                 reproduction_profile_id: secondary_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      filtered =
        PrintedPairBrowser.list_entries(%{
          illuminant: "lps",
          classification: "strong_metamer",
          profile_id: primary_profile.id,
          palette_id: primary_palette.id,
          test_sheet_id: primary_sheet.id
        })

      assert Enum.map(filtered, & &1.id) == [matching.id]

      [entry] = filtered
      assert entry.profile_id == primary_profile.id
      assert entry.palette_id == primary_palette.id
      assert entry.test_sheet_id == primary_sheet.id
      assert entry.notes? == true

      assert PrintedPairBrowser.list_entries(%{
               profile_id: secondary_profile.id,
               palette_id: secondary_palette.id,
               test_sheet_id: secondary_sheet.id
             })
             |> Enum.count() == 1
    end

    test "sorts by recent, profile, pair id, and delta e" do
      %{
        primary_pair: pair_a,
        secondary_pair: pair_b,
        primary_profile: profile_a,
        secondary_profile: profile_b
      } = printed_pair_browser_fixture()

      assert {:ok, first} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair_b.id,
                 reproduction_profile_id: profile_b.id,
                 illuminant: "blue",
                 classification: "contrasting"
               })

      assert {:ok, second} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair_a.id,
                 reproduction_profile_id: profile_a.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      Repo.update_all(
        from(classification in PrintedPairClassification, where: classification.id == ^first.id),
        set: [updated_at: ~U[2026-07-28 09:00:00Z]]
      )

      Repo.update_all(
        from(classification in PrintedPairClassification, where: classification.id == ^second.id),
        set: [updated_at: ~U[2026-07-29 09:00:00Z]]
      )

      assert Enum.map(PrintedPairBrowser.list_entries(sort: "recent"), & &1.id) == [
               second.id,
               first.id
             ]

      assert Enum.map(PrintedPairBrowser.list_entries(sort: "profile"), & &1.profile_name) ==
               Enum.sort([profile_name(profile_a), profile_name(profile_b)])

      pair_id_sorted = PrintedPairBrowser.list_entries(sort: "pair_id")

      assert Enum.map(pair_id_sorted, & &1.pair_id) ==
               Enum.sort(Enum.map(pair_id_sorted, & &1.pair_id))

      delta_e_sorted = PrintedPairBrowser.list_entries(sort: "delta_e")

      assert Enum.map(delta_e_sorted, & &1.delta_e) ==
               Enum.sort(Enum.map(delta_e_sorted, & &1.delta_e))
    end
  end

  describe "filter_options/0" do
    test "returns only contexts that have active classifications" do
      %{primary_pair: pair, primary_profile: profile, primary_palette: palette} =
        printed_pair_browser_fixture()

      assert {:ok, _classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: profile.id,
                 illuminant: "green",
                 classification: "weak_metamer"
               })

      options = PrintedPairBrowser.filter_options()

      assert {"Green", "green"} in options.illuminants
      assert {"Weak metamer", "weak_metamer"} in options.classifications
      assert Enum.any?(options.profiles, fn {_label, id} -> id == profile.id end)
      assert {palette.name, palette.id} in options.palettes
      assert Enum.any?(options.test_sheets)
    end
  end

  describe "normalize_filters/1" do
    test "accepts the string-keyed form used by LiveView change_filters payloads" do
      normalized =
        PrintedPairBrowser.normalize_filters(%{
          "illuminant" => " lps ",
          "classification" => "strong_metamer",
          "profile_id" => "42",
          "palette_id" => "9",
          "test_sheet_id" => "3",
          "sort" => "pair_id"
        })

      assert normalized.illuminant == "lps"
      assert normalized.classification == "strong_metamer"
      assert normalized.profile_id == 42
      assert normalized.palette_id == 9
      assert normalized.test_sheet_id == 3
      assert normalized.sort == "pair_id"
    end

    test "falls back to the default sort when an unknown sort is supplied" do
      assert PrintedPairBrowser.normalize_filters(%{"sort" => "made-up"}).sort == "recent"
      assert PrintedPairBrowser.normalize_filters(%{sort: "made-up"}).sort == "recent"
    end

    test "does not look up profile_id from reproduction_profile_id" do
      normalized =
        PrintedPairBrowser.normalize_filters(%{
          "reproduction_profile_id" => "99",
          "unrelated" => "value"
        })

      assert normalized.profile_id == nil
    end
  end

  defp printed_pair_browser_fixture do
    assert {:ok, primary_palette} =
             Persistence.create_palette(%{
               name: "Metamer Study A",
               colors: [
                 %{hex_color: "#111111", sort_order: 0, display_label: "A1"},
                 %{hex_color: "#141414", sort_order: 1, display_label: "A2"},
                 %{hex_color: "#F8E0D0", sort_order: 2, display_label: "A3"}
               ]
             })

    assert {:ok, secondary_palette} =
             Persistence.create_palette(%{
               name: "Metamer Study B",
               colors: [
                 %{hex_color: "#225588", sort_order: 0, display_label: "B1"},
                 %{hex_color: "#EEAA44", sort_order: 1, display_label: "B2"}
               ]
             })

    assert {:ok, primary_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Canon imagePROGRAF PRO-1100",
               paper_type: "Pro Luster",
               ink_type: "OEM Lucia Pro II"
             })

    assert {:ok, secondary_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    assert {:ok, primary_sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "PARK-TST2",
               palette_id: primary_palette.id,
               printer_profile_id: primary_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#111111", color_b_hex: "#F8E0D0"}
               ]
             })

    assert {:ok, secondary_sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "PARK-ALT2",
               palette_id: secondary_palette.id,
               printer_profile_id: secondary_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#225588", color_b_hex: "#235689"}
               ]
             })

    %{
      primary_pair: List.first(primary_sheet.pairs),
      secondary_pair: List.first(secondary_sheet.pairs),
      primary_profile: primary_profile,
      secondary_profile: secondary_profile,
      primary_sheet: primary_sheet,
      secondary_sheet: secondary_sheet,
      primary_palette: primary_palette,
      secondary_palette: secondary_palette
    }
  end

  defp profile_name(profile) do
    "#{profile.printer_make_model} on #{profile.paper_type}"
  end
end

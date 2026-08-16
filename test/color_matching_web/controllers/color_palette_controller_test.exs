defmodule ColorMatchingWeb.ColorPaletteControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "GET /api/v1/printer_profiles" do
    test "lists printer profiles ordered by make/model", %{conn: conn} do
      {:ok, _zed} = profile_fixture("ZedJet", "Matte", "Dye")
      {:ok, alpha} = profile_fixture("AlphaPrint", "Glossy", "Pigment")

      body =
        conn
        |> get(~p"/api/v1/printer_profiles")
        |> json_response(200)

      names = Enum.map(body["printer_profiles"], & &1["printer_make_model"])
      assert names == ["AlphaPrint", "ZedJet"]

      alpha_entry = Enum.find(body["printer_profiles"], &(&1["id"] == alpha.id))
      assert alpha_entry["paper_type"] == "Glossy"
      assert alpha_entry["ink_type"] == "Pigment"
    end

    test "returns an empty list when there are no profiles", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles")
        |> json_response(200)

      assert body == %{"printer_profiles" => []}
    end
  end

  describe "GET /api/v1/palettes" do
    test "lists palettes with their color counts", %{conn: conn} do
      {:ok, _palette} =
        Persistence.create_palette(%{
          name: "Swatch Set",
          colors: [
            %{hex_color: "#111111", sort_order: 0, display_label: "Dark"},
            %{hex_color: "#eeeeee", sort_order: 1}
          ]
        })

      body =
        conn
        |> get(~p"/api/v1/palettes")
        |> json_response(200)

      [palette] = body["palettes"]
      assert palette["name"] == "Swatch Set"
      assert palette["color_count"] == 2
      assert palette["is_preset"] == false
    end
  end

  describe "GET /api/v1/colors" do
    test "requires printer_profile_id", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors")
        |> json_response(400)

      assert body["errors"]["detail"] == "missing required parameter: printer_profile_id"
      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 404 for an unknown printer profile on GET /api/v1/colors", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: 999_999]}")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "printer profile"
    end

    test "returns 400 for a non-integer printer_profile_id on GET /api/v1/colors",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: "abc"]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 400 for a non-positive printer_profile_id on GET /api/v1/colors",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: 0]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 400 for a blank printer_profile_id", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: "   "]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 400 for a non-positive palette_id when querying palette colors", %{conn: conn} do
      {:ok, profile} = profile_fixture("Invalid Palette Id Printer", "Matte", "Pigment")

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: 0]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "palette_id"
    end

    test "returns 400 for a blank palette_id on GET /api/v1/colors", %{conn: conn} do
      {:ok, profile} = profile_fixture("Blank Palette Id Printer", "Matte", "Pigment")

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: "   "]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "palette_id"
    end

    test "returns colors with response vectors for a palette and profile", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      assert body["printer_profile"]["id"] == profile.id
      ids = Enum.map(body["colors"], & &1["id"])
      assert ids == Enum.sort(ids)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      assert dark_color["hex"] == "#111111"
      assert dark_color["rgb"] == %{"r" => 17, "g" => 17, "b" => 17}
      assert dark_color["palette_id"] == palette.id
      assert dark_color["palette_name"] == palette.name
      assert dark_color["sort_order"] == 0
      assert dark_color["name"] == "Dark"

      assert dark_color["responses"]["white"]["brightness"] == 0.1
      assert dark_color["responses"]["white"]["source"] == "measurement"
      assert dark_color["responses"]["red"]["brightness"] == 0.9
    end

    test "omits light sources that have no measurement (missing is not zero)", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      # Only white and red were measured; green/blue/lps must be absent entirely.
      assert MapSet.new(Map.keys(dark_color["responses"])) == MapSet.new(["white", "red"])
    end

    test "returns all colors across palettes when palette_id is omitted", %{conn: conn} do
      %{palette: palette_a, printer_profile: profile} = response_fixture()

      {:ok, _palette_b} =
        Persistence.create_palette(%{
          name: "Other Palette",
          colors: [%{hex_color: "#ff8800", sort_order: 0}]
        })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id]}")
        |> json_response(200)

      assert length(body["colors"]) == length(palette_a.colors) + 1
    end

    test "falls back to the hex when a palette color has no display label", %{conn: conn} do
      {:ok, profile} = profile_fixture("Unnamed Palette API Printer", "Matte", "Pigment")

      {:ok, palette} =
        Persistence.create_palette(%{
          name: "Unnamed Palette API",
          colors: [%{hex_color: "#ABCDEF", sort_order: 0}]
        })

      [color] = Persistence.get_palette!(palette.id).colors

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      assert body["colors"] == [
               %{
                 "hex" => "#ABCDEF",
                 "id" => color.id,
                 "name" => "#ABCDEF",
                 "palette_id" => palette.id,
                 "palette_name" => palette.name,
                 "responses" => %{
                   "white" => %{
                     "apparent_brightness" => nil,
                     "brightness" => 0.5,
                     "measured_at" => nil,
                     "raw_unit" => nil,
                     "raw_value" => nil,
                     "source" => "measurement",
                     "test_run_id" => nil
                   }
                 },
                 "rgb" => %{"b" => 239, "g" => 205, "r" => 171},
                 "sort_order" => 0
               }
             ]
    end

    test "trims surrounding whitespace from palette color labels", %{conn: conn} do
      {:ok, profile} = profile_fixture("Trimmed Palette API Printer", "Matte", "Pigment")

      {:ok, palette} =
        Persistence.create_palette(%{
          name: "Trimmed Palette API",
          colors: [%{hex_color: "#ABCDEF", sort_order: 0, display_label: "  Soft Gray  "}]
        })

      [color] = Persistence.get_palette!(palette.id).colors

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      assert body["colors"] == [
               %{
                 "hex" => "#ABCDEF",
                 "id" => color.id,
                 "name" => "Soft Gray",
                 "palette_id" => palette.id,
                 "palette_name" => palette.name,
                 "responses" => %{
                   "white" => %{
                     "apparent_brightness" => nil,
                     "brightness" => 0.5,
                     "measured_at" => nil,
                     "raw_unit" => nil,
                     "raw_value" => nil,
                     "source" => "measurement",
                     "test_run_id" => nil
                   }
                 },
                 "rgb" => %{"b" => 239, "g" => 205, "r" => 171},
                 "sort_order" => 0
               }
             ]
    end

    test "human-entered response wins over instrument measurement for a light source", %{
      conn: conn
    } do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      # Add a human response for white that disagrees with the instrument value.
      assert {:ok, _} =
               Persistence.set_illuminant_response(%{
                 palette_color_id: dark.id,
                 printer_profile_id: profile.id,
                 illuminant: "white",
                 apparent_brightness: 5
               })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      # 5/10 = 0.5 (response), not the instrument's 0.1.
      assert dark_color["responses"]["white"]["brightness"] == 0.5
      assert dark_color["responses"]["white"]["source"] == "response"
      assert dark_color["responses"]["white"]["apparent_brightness"] == 5
    end

    test "exposes raw instrument values", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} =
        raw_measurement_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      assert dark_color["responses"]["green"]["raw_value"] == 42.5
      assert dark_color["responses"]["green"]["raw_unit"] == "nits"
      assert dark_color["responses"]["green"]["source"] == "measurement"
    end

    test "returns 404 for an unknown palette", %{conn: conn} do
      %{printer_profile: profile} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: 999_999]}")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "palette"
    end

    test "returns 400 for a non-integer palette_id", %{conn: conn} do
      %{printer_profile: profile} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: "abc"]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "palette_id"
    end

    test "returns 400 for a non-positive palette_id when querying measured color vectors", %{
      conn: conn
    } do
      %{printer_profile: profile} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: -1]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "palette_id"
    end

    test "returns 400 for a blank palette_id on GET /api/v1/colors measured vectors",
         %{conn: conn} do
      %{printer_profile: profile} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: "   "]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "palette_id"
    end
  end

  describe "GET /api/v1/printer_profiles/:printer_profile_id/colors" do
    test "returns 404 for an unknown printer profile on GET /api/v1/printer_profiles/:printer_profile_id/colors",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/999999/colors")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "printer profile"
    end

    test "returns 400 for a non-integer printer_profile_id on GET /api/v1/printer_profiles/:printer_profile_id/colors",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/not-an-id/colors")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 400 for a non-positive printer_profile_id on GET /api/v1/printer_profiles/:printer_profile_id/colors",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/0/colors")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns an empty working set when no colors have data for the profile", %{conn: conn} do
      {:ok, profile} = profile_fixture("Unmeasured Printer", "Matte", "Dye")

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{profile.id}/colors")
        |> json_response(200)

      assert body["printer_profile"]["id"] == profile.id
      assert body["colors"] == []
    end

    test "returns a profile-scoped working color set without palette fields", %{conn: conn} do
      %{printer_profile: profile, dark: dark, light: light} = response_fixture()

      {:ok, duplicate_palette} =
        Persistence.create_palette(%{
          name: "Duplicate API Palette",
          colors: [%{hex_color: dark.hex_color, sort_order: 0, display_label: "Duplicate Dark"}]
        })

      duplicate_dark = Persistence.get_palette!(duplicate_palette.id).colors |> List.first()

      assert {:ok, _} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: duplicate_dark.id,
                 printer_profile_id: profile.id,
                 light_source: "green",
                 normalized_brightness: 0.4
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{profile.id}/colors")
        |> json_response(200)

      assert body["printer_profile"]["id"] == profile.id
      assert length(body["colors"]) == 2

      dark_color = Enum.find(body["colors"], &(&1["hex"] == dark.hex_color))
      light_color = Enum.find(body["colors"], &(&1["hex"] == light.hex_color))

      assert Map.keys(dark_color) |> Enum.sort() == ["hex", "name", "responses", "rgb"]
      assert dark_color["name"] == "Dark"
      assert dark_color["responses"]["white"]["brightness"] == 0.1
      assert dark_color["responses"]["red"]["brightness"] == 0.9
      assert dark_color["responses"]["green"]["brightness"] == 0.4
      assert light_color["responses"]["white"]["brightness"] == 0.9
      refute Map.has_key?(dark_color, "palette_id")
      refute Map.has_key?(dark_color, "palette_name")
      refute Map.has_key?(dark_color, "sort_order")
      refute Map.has_key?(dark_color, "id")
    end

    test "includes every confirmed metamer pair hex in the working set", %{conn: conn} do
      %{palette: palette, pair: pair, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      measured_color = Persistence.get_palette!(palette.id).colors |> List.first()

      assert {:ok, _} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: measured_color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.3
               })

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      colors_body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      pairs_body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/metamer_pairs")
        |> json_response(200)

      color_hexes = colors_body["colors"] |> MapSet.new(&String.upcase(&1["hex"]))

      pair_hexes =
        pairs_body["metamer_pairs"]
        |> Enum.flat_map(&[&1["color_a_hex"], &1["color_b_hex"]])
        |> MapSet.new(&String.upcase/1)

      assert MapSet.subset?(pair_hexes, color_hexes)

      unmeasured_color = Enum.find(colors_body["colors"], &(&1["hex"] == "#445566"))
      assert unmeasured_color["name"] == "Patch 2"
      assert unmeasured_color["responses"] == %{}
    end

    test "matches confirmed pair hexes case-insensitively in the profile color API", %{
      conn: conn
    } do
      %{palette: palette, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      assert {:ok, _case_palette} =
               Persistence.create_palette(%{
                 name: "Uppercase Pair API Palette",
                 colors: [%{hex_color: "#ABCDEF", sort_order: 0, display_label: "Upper Pair"}]
               })

      assert {:ok, sheet} =
               Persistence.create_test_sheet(%{
                 lookup_code: "PWDF-TEST",
                 palette_id: palette.id,
                 printer_profile_id: printer_profile.id,
                 sheet_version: "2026-08-01",
                 pairs: [%{row: 1, col: 0, color_a_hex: "#abcdef", color_b_hex: "#FEDCBA"}]
               })

      [case_pair] = sheet.pairs

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: case_pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "weak_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      assert body["colors"] == [
               %{
                 "hex" => "#ABCDEF",
                 "name" => "Upper Pair",
                 "responses" => %{},
                 "rgb" => %{"b" => 239, "g" => 205, "r" => 171}
               },
               %{
                 "hex" => "#FEDCBA",
                 "name" => "#FEDCBA",
                 "responses" => %{},
                 "rgb" => %{"b" => 186, "g" => 220, "r" => 254}
               }
             ]
    end

    test "prefers the confirmed pair's source palette label for pair-only colors", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, _unrelated_palette} =
               Persistence.create_palette(%{
                 name: "Unrelated Pair Labels",
                 colors: [
                   %{hex_color: "#445566", sort_order: -1, display_label: "Wrong Pair Label"}
                 ]
               })

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      pair_only_color = Enum.find(body["colors"], &(&1["hex"] == "#445566"))

      assert pair_only_color["name"] == "Patch 2"
      assert pair_only_color["responses"] == %{}
    end

    test "falls back to the hex when a confirmed pair source label is blank", %{conn: conn} do
      %{palette: palette, pair: pair, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      source_pair_color =
        Enum.find(palette.colors, &(&1.hex_color == "#445566"))

      assert {:ok, _} =
               source_pair_color
               |> Ecto.Changeset.change(display_label: "   ")
               |> ColorMatching.Repo.update()

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      pair_only_color = Enum.find(body["colors"], &(&1["hex"] == "#445566"))

      assert pair_only_color["name"] == "#445566"
      assert pair_only_color["responses"] == %{}
    end

    test "ignores unrelated duplicate labels when a confirmed pair source label is blank", %{
      conn: conn
    } do
      %{palette: palette, pair: pair, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      source_pair_color =
        Enum.find(palette.colors, &(&1.hex_color == "#445566"))

      assert {:ok, _} =
               source_pair_color
               |> Ecto.Changeset.change(display_label: "   ")
               |> ColorMatching.Repo.update()

      assert {:ok, _unrelated_palette} =
               Persistence.create_palette(%{
                 name: "Unrelated Duplicate Labels",
                 colors: [
                   %{hex_color: "#445566", sort_order: -1, display_label: "Wrong Pair Label"}
                 ]
               })

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      pair_only_color = Enum.find(body["colors"], &(&1["hex"] == "#445566"))

      assert pair_only_color["name"] == "#445566"
      assert pair_only_color["responses"] == %{}
    end

    test "keeps the confirmed pair label when other classified sheets contain duplicate hexes", %{
      conn: conn
    } do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, wrong_palette} =
               Persistence.create_palette(%{
                 name: "Wrong Classified Labels",
                 colors: [
                   %{
                     hex_color: "#445566",
                     sort_order: -1,
                     display_label: "Wrong Classified Label"
                   },
                   %{hex_color: "#ABC123", sort_order: 0, display_label: "Other Patch"},
                   %{hex_color: "#DEF456", sort_order: 1, display_label: "Another Patch"}
                 ]
               })

      assert {:ok, wrong_sheet} =
               Persistence.create_test_sheet(%{
                 lookup_code: "PWDH-TEST",
                 palette_id: wrong_palette.id,
                 printer_profile_id: printer_profile.id,
                 sheet_version: "2026-08-02",
                 pairs: [%{row: 0, col: 0, color_a_hex: "#ABC123", color_b_hex: "#DEF456"}]
               })

      [wrong_pair] = wrong_sheet.pairs

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      assert {:ok, _other_metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: wrong_pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "blue",
                 classification: "weak_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      colors_by_hex = Map.new(body["colors"], &{&1["hex"], &1})

      assert colors_by_hex["#445566"]["name"] == "Patch 2"
      assert colors_by_hex["#445566"]["responses"] == %{}
      assert colors_by_hex["#ABC123"]["name"] == "Other Patch"
      assert colors_by_hex["#DEF456"]["name"] == "Another Patch"
    end

    test "names pair hexes that match no palette color after the hex itself", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      assert {:ok, sheet} =
               Persistence.create_test_sheet(%{
                 lookup_code: "PWDA-TEST",
                 palette_id: palette.id,
                 printer_profile_id: printer_profile.id,
                 sheet_version: "2026-08-01",
                 pairs: [%{row: 1, col: 0, color_a_hex: "#ABCDEF", color_b_hex: "#FEDCBA"}]
               })

      [pair] = sheet.pairs

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      assert Enum.map(body["colors"], & &1["hex"]) == ["#ABCDEF", "#FEDCBA"]

      for color <- body["colors"] do
        assert color["name"] == color["hex"]
        assert color["responses"] == %{}
        assert match?(%{"r" => _, "g" => _, "b" => _}, color["rgb"])
      end
    end

    test "falls back to the hex when a profile color has no display label", %{conn: conn} do
      {:ok, profile} = profile_fixture("Unnamed API Printer", "Matte", "Pigment")

      {:ok, palette} =
        Persistence.create_palette(%{
          name: "Unnamed API Palette",
          colors: [%{hex_color: "#ABCDEF", sort_order: 0}]
        })

      [color] = Persistence.get_palette!(palette.id).colors

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{profile.id}/colors")
        |> json_response(200)

      assert body["colors"] == [
               %{
                 "hex" => "#ABCDEF",
                 "name" => "#ABCDEF",
                 "responses" => %{
                   "white" => %{
                     "apparent_brightness" => nil,
                     "brightness" => 0.5,
                     "measured_at" => nil,
                     "raw_unit" => nil,
                     "raw_value" => nil,
                     "source" => "measurement",
                     "test_run_id" => nil
                   }
                 },
                 "rgb" => %{"b" => 239, "g" => 205, "r" => 171}
               }
             ]
    end

    test "trims surrounding whitespace from profile color labels", %{conn: conn} do
      {:ok, profile} = profile_fixture("Trimmed API Printer", "Matte", "Pigment")

      {:ok, palette} =
        Persistence.create_palette(%{
          name: "Trimmed API Palette",
          colors: [%{hex_color: "#ABCDEF", sort_order: 0, display_label: "  Soft Gray  "}]
        })

      [color] = Persistence.get_palette!(palette.id).colors

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{profile.id}/colors")
        |> json_response(200)

      assert body["colors"] == [
               %{
                 "hex" => "#ABCDEF",
                 "name" => "Soft Gray",
                 "responses" => %{
                   "white" => %{
                     "apparent_brightness" => nil,
                     "brightness" => 0.5,
                     "measured_at" => nil,
                     "raw_unit" => nil,
                     "raw_value" => nil,
                     "source" => "measurement",
                     "test_run_id" => nil
                   }
                 },
                 "rgb" => %{"b" => 239, "g" => 205, "r" => 171}
               }
             ]
    end

    test "keeps measured colors ahead of pair-only colors with unrelated fallback labels", %{
      conn: conn
    } do
      %{palette: palette, pair: pair, printer_profile: printer_profile} =
        printed_pair_classification_fixture()

      assert {:ok, _unrelated_palette} =
               Persistence.create_palette(%{
                 name: "Early Fallback Pair Labels",
                 colors: [
                   %{hex_color: "#445566", sort_order: -1, display_label: "Fallback Pair Label"}
                 ]
               })

      measured_color = Persistence.get_palette!(palette.id).colors |> List.first()

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: measured_color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.3
               })

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/colors")
        |> json_response(200)

      assert Enum.map(body["colors"], & &1["hex"]) == ["#112233", "#445566"]
      assert Enum.at(body["colors"], 1)["name"] == "Patch 2"
    end
  end

  describe "GET /api/v1/printer_profiles/:printer_profile_id/metamer_pairs" do
    test "returns 404 for an unknown printer profile on GET /api/v1/printer_profiles/:printer_profile_id/metamer_pairs",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/999999/metamer_pairs")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "printer profile"
    end

    test "returns 400 for a non-integer printer_profile_id on GET /api/v1/printer_profiles/:printer_profile_id/metamer_pairs",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/not-an-id/metamer_pairs")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 400 for a non-positive printer_profile_id on GET /api/v1/printer_profiles/:printer_profile_id/metamer_pairs",
         %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles/-5/metamer_pairs")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns active confirmed metamer pairs for the profile", %{conn: conn} do
      %{
        pair: pair,
        second_pair: second_pair,
        printer_profile: printer_profile,
        second_printer_profile: second_printer_profile
      } = printed_pair_classification_fixture()

      assert {:ok, strong_metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Confirmed under sodium."
               })

      assert {:ok, weak_metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: second_pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "blue",
                 classification: "weak_metamer"
               })

      assert {:ok, _contrasting} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "green",
                 classification: "contrasting"
               })

      assert {:ok, _other_profile} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: second_printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/metamer_pairs")
        |> json_response(200)

      assert body["printer_profile"]["id"] == printer_profile.id

      assert Enum.map(body["metamer_pairs"], & &1["pair_id"]) |> Enum.sort() ==
               Enum.sort([pair.pair_id, second_pair.pair_id])

      lps_pair = Enum.find(body["metamer_pairs"], &(&1["pair_id"] == pair.pair_id))
      blue_pair = Enum.find(body["metamer_pairs"], &(&1["pair_id"] == second_pair.pair_id))

      assert lps_pair["classification"] == strong_metamer.classification
      assert lps_pair["illuminant"] == "lps"
      assert lps_pair["notes"] == "Confirmed under sodium."
      assert lps_pair["color_a_hex"] == pair.color_a_hex
      assert lps_pair["color_b_hex"] == pair.color_b_hex

      assert {:ok, classified_at, 0} = DateTime.from_iso8601(lps_pair["classified_at"])
      assert DateTime.compare(classified_at, strong_metamer.inserted_at) == :eq
      assert blue_pair["classification"] == weak_metamer.classification
      refute Enum.any?(body["metamer_pairs"], &(&1["classification"] == "contrasting"))
    end

    test "drops pairs whose metamer classification was superseded", %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, _metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer"
               })

      assert {:ok, _} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "contrasting"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/metamer_pairs")
        |> json_response(200)

      assert body["metamer_pairs"] == []
    end

    test "returns the latest active metamer classification after metamer-to-metamer reclassification",
         %{conn: conn} do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, _first_metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Initial review"
               })

      assert {:ok, latest_metamer} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "weak_metamer",
                 notes: "Refined after second review"
               })

      body =
        conn
        |> get(~p"/api/v1/printer_profiles/#{printer_profile.id}/metamer_pairs")
        |> json_response(200)

      assert body["metamer_pairs"] == [
               %{
                 "pair_id" => pair.pair_id,
                 "color_a_hex" => pair.color_a_hex,
                 "color_b_hex" => pair.color_b_hex,
                 "illuminant" => "lps",
                 "classification" => "weak_metamer",
                 "notes" => "Refined after second review",
                 "classified_at" => DateTime.to_iso8601(latest_metamer.inserted_at)
               }
             ]
    end
  end

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp profile_fixture(make, paper, ink) do
    Persistence.create_printer_profile(%{
      printer_make_model: make,
      paper_type: paper,
      ink_type: ink
    })
  end

  defp response_fixture do
    {:ok, profile} = profile_fixture("Response Fixture Printer", "Matte", "Pigment")

    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Response Fixture",
        colors: [
          %{hex_color: "#111111", sort_order: 0, display_label: "Dark"},
          %{hex_color: "#eeeeee", sort_order: 1, display_label: "Light"}
        ]
      })

    palette = Persistence.get_palette!(palette.id)
    [dark, light] = palette.colors

    Enum.each(palette.colors, fn color ->
      Persistence.create_illuminant_measurement(%{
        palette_color_id: color.id,
        printer_profile_id: profile.id,
        light_source: "white",
        normalized_brightness: if(color.hex_color == "#111111", do: 0.1, else: 0.9)
      })

      Persistence.create_illuminant_measurement(%{
        palette_color_id: color.id,
        printer_profile_id: profile.id,
        light_source: "red",
        normalized_brightness: if(color.hex_color == "#111111", do: 0.9, else: 0.1)
      })
    end)

    %{palette: palette, printer_profile: profile, dark: dark, light: light}
  end

  defp raw_measurement_fixture do
    {:ok, profile} = profile_fixture("Raw Fixture Printer", "Matte", "Pigment")

    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Raw Fixture",
        colors: [%{hex_color: "#111111", sort_order: 0, display_label: "Dark"}]
      })

    palette = Persistence.get_palette!(palette.id)
    [dark] = palette.colors

    assert {:ok, _} =
             Persistence.create_illuminant_measurement(%{
               palette_color_id: dark.id,
               printer_profile_id: profile.id,
               light_source: "green",
               normalized_brightness: 0.3,
               raw_measured_value: 42.5,
               raw_value_unit: "nits"
             })

    %{palette: palette, printer_profile: profile, dark: dark}
  end

  defp printed_pair_classification_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Printed Pair API Palette",
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

    assert {:ok, second_printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Canon imagePROGRAF PRO-1100",
               paper_type: "Pro Luster",
               ink_type: "OEM Lucia Pro II"
             })

    assert {:ok, sheet} =
             Persistence.create_test_sheet(%{
               lookup_code: "PARE-TEST",
               palette_id: palette.id,
               printer_profile_id: printer_profile.id,
               sheet_version: "2026-07-30",
               pairs: [
                 %{row: 0, col: 0, color_a_hex: "#112233", color_b_hex: "#445566"},
                 %{row: 0, col: 1, color_a_hex: "#112233", color_b_hex: "#778899"}
               ]
             })

    [pair, second_pair] = sheet.pairs

    %{
      palette: palette,
      pair: pair,
      second_pair: second_pair,
      printer_profile: printer_profile,
      second_printer_profile: second_printer_profile
    }
  end
end

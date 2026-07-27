defmodule ColorMatching.PersistenceTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.{Palette, Persistence}

  describe "palettes" do
    test "creates and reads a palette with persisted colors" do
      assert {:ok, palette} =
               Persistence.create_palette(%{
                 name: "Measured Swatches",
                 colors: [
                   %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"},
                   %{hex_color: "#AABBCC", sort_order: 1, display_label: "Patch 2"}
                 ]
               })

      persisted = Persistence.get_palette!(palette.id)

      assert persisted.name == "Measured Swatches"
      assert persisted.is_preset == false
      assert Enum.map(persisted.colors, & &1.hex_color) == ["#112233", "#AABBCC"]
      assert Enum.map(persisted.colors, & &1.sort_order) == [0, 1]
      assert Enum.map(persisted.colors, & &1.display_label) == ["Patch 1", "Patch 2"]
    end

    test "accepts shorthand 3-digit hex colors" do
      assert {:ok, palette} =
               Persistence.create_palette(%{
                 name: "Shorthand Swatches",
                 colors: [
                   %{hex_color: "#DDD", sort_order: 0},
                   %{hex_color: "#FFF", sort_order: 1}
                 ]
               })

      persisted = Persistence.get_palette!(palette.id)
      assert Enum.map(persisted.colors, & &1.hex_color) == ["#DDD", "#FFF"]
    end

    test "returns a changeset error when colors reuse the same sort order" do
      assert {:error, changeset} =
               Persistence.create_palette(%{
                 name: "Duplicate Sort Order",
                 colors: [
                   %{hex_color: "#112233", sort_order: 0},
                   %{hex_color: "#445566", sort_order: 0}
                 ]
               })

      duplicate_color_error =
        changeset
        |> errors_on()
        |> Map.fetch!(:colors)
        |> Enum.at(1)

      assert "has already been taken" in duplicate_color_error.sort_order
    end
  end

  describe "printer profiles" do
    test "creates and reads a persisted printer profile" do
      assert {:ok, profile} =
               Persistence.create_printer_profile(%{
                 printer_make_model: "Epson SureColor P900",
                 paper_type: "Ultra Premium Luster",
                 ink_type: "OEM UltraChrome PRO10",
                 icc_profile: "SC-P900 Premium Luster",
                 calibration_date: ~D[2026-07-01]
               })

      persisted = Persistence.get_printer_profile!(profile.id)

      assert persisted.printer_make_model == "Epson SureColor P900"
      assert persisted.paper_type == "Ultra Premium Luster"
      assert persisted.ink_type == "OEM UltraChrome PRO10"
      assert persisted.icc_profile == "SC-P900 Premium Luster"
      assert persisted.calibration_date == ~D[2026-07-01]
    end
  end

  describe "illuminant measurements" do
    test "creates and reads persisted illuminant measurements" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      measured_at = ~U[2026-07-27 12:34:56.123456Z]

      assert {:ok, measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.42,
                 raw_measured_value: 108.0,
                 raw_value_unit: "cd/m2",
                 notes: "Reference white patch",
                 measured_at: measured_at,
                 measurement_method: "spot meter",
                 measurement_device: "Sekonic C-800",
                 test_run_id: "run-001"
               })

      [persisted] = Persistence.list_illuminant_measurements(color.id, printer_profile.id)

      assert persisted.id == measurement.id
      assert persisted.light_source == "white"
      assert persisted.normalized_brightness == 0.42
      assert persisted.raw_measured_value == 108.0
      assert persisted.raw_value_unit == "cd/m2"
      assert persisted.notes == "Reference white patch"
      assert persisted.measured_at == measured_at
      assert persisted.measurement_method == "spot meter"
      assert persisted.measurement_device == "Sekonic C-800"
      assert persisted.test_run_id == "run-001"
    end

    test "rejects normalized brightness outside the supported range" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:error, changeset} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: 1.01
               })

      assert %{normalized_brightness: ["must be less than or equal to 1.0"]} =
               errors_on(changeset)

      assert {:error, changeset} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "green",
                 normalized_brightness: -0.01
               })

      assert %{normalized_brightness: ["must be greater than or equal to 0.0"]} =
               errors_on(changeset)
    end

    test "preserves multiple measurements for the same light source" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:ok, first} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "blue",
                 normalized_brightness: 0.2,
                 measured_at: ~U[2026-07-27 09:00:00Z]
               })

      assert {:ok, second} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "blue",
                 normalized_brightness: 0.3,
                 measured_at: ~U[2026-07-27 10:00:00Z]
               })

      persisted = Persistence.list_illuminant_measurements(color.id, printer_profile.id)

      assert Enum.map(persisted, & &1.id) == [second.id, first.id]
      assert Enum.map(persisted, & &1.normalized_brightness) == [0.3, 0.2]
    end

    test "returns the latest measurement for each light source deterministically" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:ok, oldest_red} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: 0.15,
                 measured_at: ~U[2026-07-27 08:00:00Z]
               })

      assert {:ok, latest_red} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: 0.25,
                 measured_at: ~U[2026-07-27 11:00:00Z]
               })

      assert {:ok, first_green} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "green",
                 normalized_brightness: 0.4,
                 measured_at: ~U[2026-07-27 10:00:00Z]
               })

      assert {:ok, second_green} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "green",
                 normalized_brightness: 0.45,
                 measured_at: ~U[2026-07-27 10:00:00Z]
               })

      assert {:ok, nil_timestamp_white} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      assert {:ok, timestamped_white} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.55,
                 measured_at: ~U[2026-07-27 12:00:00Z]
               })

      latest_by_light_source =
        Persistence.latest_illuminant_measurements_by_light_source(color.id, printer_profile.id)

      assert Map.keys(latest_by_light_source) |> Enum.sort() == ["green", "red", "white"]
      assert latest_by_light_source["red"].id == latest_red.id
      assert latest_by_light_source["red"].normalized_brightness == 0.25
      assert latest_by_light_source["green"].id == second_green.id
      assert latest_by_light_source["green"].normalized_brightness == 0.45
      assert latest_by_light_source["white"].id == timestamped_white.id
      assert latest_by_light_source["white"].normalized_brightness == 0.55

      assert Persistence.get_latest_illuminant_measurement(
               color.id,
               printer_profile.id,
               "red"
             ).id == latest_red.id

      assert Persistence.get_latest_illuminant_measurement(
               color.id,
               printer_profile.id,
               "green"
             ).id == second_green.id

      assert Persistence.get_latest_illuminant_measurement(
               color.id,
               printer_profile.id,
               "white"
             ).id == timestamped_white.id

      assert Persistence.get_latest_illuminant_measurement(
               color.id,
               printer_profile.id,
               "blue"
             ) == nil

      refute latest_by_light_source["red"].id == oldest_red.id
      refute latest_by_light_source["green"].id == first_green.id
      refute latest_by_light_source["white"].id == nil_timestamp_white.id
    end

    test "returns validation errors for uncastable measurement reference ids" do
      invalid_ids = ["abc", %{"id" => 1}]

      for invalid_id <- invalid_ids do
        assert {:error, changeset} =
                 Persistence.create_illuminant_measurement(%{
                   palette_color_id: invalid_id,
                   printer_profile_id: invalid_id,
                   light_source: "red",
                   normalized_brightness: 0.5
                 })

        assert %{
                 palette_color_id: ["is invalid"],
                 printer_profile_id: ["is invalid"]
               } = errors_on(changeset)
      end
    end

    test "bulk import creates independent measurement records with shared metadata" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:ok, measurements} =
               Persistence.create_illuminant_measurements_bulk(%{
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 measured_at: ~U[2026-07-27 14:00:00Z],
                 measurement_method: "camera",
                 measurement_device: "phone-camera",
                 test_run_id: "sheet-2026-07-26-a",
                 measurements: [
                   %{
                     color_id: color.id,
                     brightness: 0.91,
                     raw_value: 184.2,
                     raw_unit: "8-bit grayscale",
                     notes: "center patch"
                   },
                   %{
                     color_id: color.id,
                     brightness: 0.87,
                     raw_value: 176.0,
                     raw_unit: "8-bit grayscale",
                     notes: "edge patch"
                   }
                 ]
               })

      assert Enum.count(measurements) == 2
      assert Enum.map(measurements, & &1.id) == Enum.uniq(Enum.map(measurements, & &1.id))
      assert Enum.all?(measurements, &(&1.printer_profile_id == printer_profile.id))
      assert Enum.all?(measurements, &(&1.palette_color_id == color.id))
      assert Enum.all?(measurements, &(&1.light_source == "red"))
      assert Enum.all?(measurements, &(&1.measurement_method == "camera"))
      assert Enum.all?(measurements, &(&1.measurement_device == "phone-camera"))
      assert Enum.all?(measurements, &(&1.test_run_id == "sheet-2026-07-26-a"))

      persisted = Persistence.list_illuminant_measurements(color.id, printer_profile.id)
      persisted_ids = persisted |> Enum.map(& &1.id) |> Enum.sort()
      measurement_ids = measurements |> Enum.map(& &1.id) |> Enum.sort()

      assert Enum.count(persisted) == 2
      assert persisted_ids == measurement_ids
    end

    test "bulk import rejects non-object rows before preparing measurements" do
      assert {:error, {:invalid_request, errors}} =
               Persistence.create_illuminant_measurements_bulk(%{measurements: [1]})

      assert errors == %{measurements: ["must contain only measurement objects"]}
    end

    test "bulk import returns indexed validation errors for uncastable reference ids" do
      assert {:error, {:invalid_rows, invalid_rows}} =
               Persistence.create_illuminant_measurements_bulk(%{
                 light_source: "green",
                 normalized_brightness: 0.5,
                 measurements: [
                   %{color_id: "abc", printer_profile_id: %{"id" => 1}}
                 ]
               })

      assert invalid_rows == [
               %{
                 index: 0,
                 color_id: "abc",
                 errors: %{
                   palette_color_id: ["is invalid"],
                   printer_profile_id: ["is invalid"]
                 }
               }
             ]
    end

    test "bulk import returns indexed row errors and rolls back the batch" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:error, {:invalid_rows, invalid_rows}} =
               Persistence.create_illuminant_measurements_bulk(%{
                 printer_profile_id: printer_profile.id,
                 light_source: "green",
                 measurements: [
                   %{color_id: color.id, brightness: 0.52},
                   %{color_id: 999_999, brightness: 0.61},
                   %{color_id: color.id, brightness: 1.5}
                 ]
               })

      assert invalid_rows == [
               %{index: 1, color_id: 999_999, errors: %{palette_color_id: ["does not exist"]}},
               %{
                 index: 2,
                 color_id: color.id,
                 errors: %{normalized_brightness: ["must be less than or equal to 1.0"]}
               }
             ]

    assert Persistence.list_illuminant_measurements(color.id, printer_profile.id) == []
    end
  end
  end

  describe "preset palette import" do
    test "imports preset palettes for persisted workflows" do
      assert {:ok, palettes} = Persistence.import_preset_palettes()

      assert length(palettes) == length(ColorMatching.PaletteStorage.get_preset_palettes())

      persisted = Persistence.list_palettes()
      warm = Enum.find(persisted, &(&1.name == "Warm"))

      assert warm
      assert warm.is_preset == true
      assert Enum.at(warm.colors, 0).hex_color == "#FF6B6B"
    end

    test "imports presets containing shorthand 3-digit hex colors" do
      assert {:ok, _palettes} = Persistence.import_preset_palettes()

      monochrome = Enum.find(Persistence.list_palettes(), &(&1.name == "Monochrome"))
      assert monochrome
      assert "#DDD" in Enum.map(monochrome.colors, & &1.hex_color)
      assert "#FFF" in Enum.map(monochrome.colors, & &1.hex_color)
    end

    test "rolls back the full import when a later preset is invalid" do
      preset_palettes = [
        Palette.new(%{name: "Valid Preset", colors: ["#112233"], is_preset: true}),
        Palette.new(%{name: "Invalid Preset", colors: ["not-a-hex"], is_preset: true})
      ]

      assert {:error, changeset} = Persistence.import_preset_palettes(preset_palettes)

      assert %{colors: [%{hex_color: ["has invalid format"]}]} = errors_on(changeset)
      assert Persistence.list_palettes() == []
    end

    test "re-import preserves existing preset color ids by hex color across reordering" do
      initial_presets = [
        Palette.new(%{
          name: "Warm",
          colors: ["#111111", "#222222", "#111111"],
          is_preset: true
        })
      ]

      reordered_presets = [
        Palette.new(%{
          name: "Warm",
          colors: ["#111111", "#444444", "#111111", "#222222"],
          is_preset: true
        })
      ]

      assert {:ok, _palettes} = Persistence.import_preset_palettes(initial_presets)

      original_warm =
        Persistence.list_palettes()
        |> Enum.find(&(&1.name == "Warm"))

      original_duplicate_ids =
        original_warm.colors
        |> Enum.filter(&(&1.hex_color == "#111111"))
        |> Enum.map(& &1.id)

      original_duplicate_inserted_ats =
        original_warm.colors
        |> Enum.filter(&(&1.hex_color == "#111111"))
        |> Enum.map(& &1.inserted_at)

      original_singleton_ids =
        original_warm.colors
        |> Enum.reject(&(&1.hex_color == "#111111"))
        |> Map.new(fn color -> {color.hex_color, color.id} end)

      assert {:ok, _palettes} = Persistence.import_preset_palettes(reordered_presets)

      reimported_warm =
        Persistence.list_palettes()
        |> Enum.find(&(&1.name == "Warm"))

      reimported_duplicate_colors =
        Enum.filter(reimported_warm.colors, &(&1.hex_color == "#111111"))

      reimported_duplicate_ids = Enum.map(reimported_duplicate_colors, & &1.id)
      reimported_duplicate_inserted_ats = Enum.map(reimported_duplicate_colors, & &1.inserted_at)

      reimported_singleton_ids =
        reimported_warm.colors
        |> Enum.reject(&(&1.hex_color == "#111111"))
        |> Map.new(fn color -> {color.hex_color, color.id} end)

      assert reimported_duplicate_ids == original_duplicate_ids
      assert reimported_duplicate_inserted_ats == original_duplicate_inserted_ats
      assert reimported_singleton_ids["#222222"] == original_singleton_ids["#222222"]

      assert reimported_singleton_ids["#444444"] not in (original_duplicate_ids ++
                                                           Map.values(original_singleton_ids))

      assert Enum.map(reimported_warm.colors, & &1.hex_color) == [
               "#111111",
               "#444444",
               "#111111",
               "#222222"
             ]

      assert Enum.map(reimported_warm.colors, & &1.sort_order) == [0, 1, 2, 3]
    end

    test "rejects preset import when a user palette name collides with a built-in preset" do
      assert {:ok, user_palette} =
               Persistence.create_palette(%{
                 name: "Warm",
                 colors: [
                   %{hex_color: "#123456", sort_order: 0, display_label: "User Swatch"}
                 ]
               })

      assert {:error, changeset} = Persistence.import_preset_palettes()

      assert %{name: [message]} = errors_on(changeset)
      assert message =~ "conflicts with an existing user palette"

      persisted = Persistence.get_palette!(user_palette.id)

      assert persisted.name == "Warm"
      assert persisted.is_preset == false
      assert Enum.map(persisted.colors, & &1.hex_color) == ["#123456"]
      assert Enum.map(persisted.colors, & &1.display_label) == ["User Swatch"]
      assert Persistence.list_palettes() |> Enum.map(& &1.id) == [user_palette.id]
    end
  end

  defp persisted_measurement_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Measured Swatches",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    color = Persistence.get_palette!(palette.id).colors |> List.first()

    %{color: color, printer_profile: printer_profile}
  end
end

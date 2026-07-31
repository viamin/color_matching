defmodule ColorMatching.PersistenceTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.{Palette, Persistence}
  alias ColorMatching.Persistence.{PaletteColor, PrintedPairClassification, PrinterProfile}

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

    test "loads a single palette color with its parent palette" do
      assert {:ok, palette} =
               Persistence.create_palette(%{
                 name: "Detail Fixture",
                 colors: [
                   %{hex_color: "#ABCDEF", sort_order: 0, display_label: "Patch A"},
                   %{hex_color: "#123456", sort_order: 1, display_label: "Patch B"}
                 ]
               })

      [first_color, second_color] = Persistence.get_palette!(palette.id).colors

      loaded_first = Persistence.get_palette_color!(first_color.id)
      loaded_second = Persistence.get_palette_color!(second_color.id)

      assert loaded_first.id == first_color.id
      assert loaded_first.hex_color == "#ABCDEF"
      assert loaded_first.display_label == "Patch A"
      assert loaded_first.palette.id == palette.id
      assert loaded_first.palette.name == "Detail Fixture"
      assert loaded_second.hex_color == "#123456"

      assert_raise Ecto.NoResultsError, fn ->
        Persistence.get_palette_color!(0)
      end
    end

    test "returns nil for get_palette_color/1 when the color id is unknown" do
      assert Persistence.get_palette_color(0) == nil
    end

    test "returns nil for get_palette/1 when the palette id is unknown" do
      assert Persistence.get_palette(0) == nil
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

    test "returns nil for get_printer_profile/1 when the printer profile id is unknown" do
      assert Persistence.get_printer_profile(0) == nil
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

    test "builds response vectors for multiple palette colors from latest measurements" do
      %{color: first_color, printer_profile: printer_profile} = persisted_measurement_fixture()

      assert {:ok, second_palette} =
               Persistence.create_palette(%{
                 name: "Second Measured Swatch",
                 colors: [%{hex_color: "#445566", sort_order: 0}]
               })

      second_color = Persistence.get_palette!(second_palette.id).colors |> List.first()

      for {color, brightness} <- [{first_color, 0.25}, {second_color, 0.75}] do
        assert {:ok, _measurement} =
                 Persistence.create_illuminant_measurement(%{
                   palette_color_id: color.id,
                   printer_profile_id: printer_profile.id,
                   light_source: "white",
                   normalized_brightness: brightness
                 })
      end

      assert [first_vector, second_vector] =
               Persistence.response_vectors([first_color, second_color], printer_profile)

      assert first_vector.hex_color == first_color.hex_color
      assert first_vector.white == 0.25
      assert second_vector.hex_color == second_color.hex_color
      assert second_vector.white == 0.75
      assert first_vector.red == :missing
      assert second_vector.red == :missing
    end

    test "raises when building a response vector for an unpersisted printer profile" do
      %{color: color} = persisted_measurement_fixture()

      assert_raise ArgumentError,
                   "response_vector/2 requires persisted palette color and printer profile",
                   fn ->
                     Persistence.response_vector(color, %PrinterProfile{
                       printer_make_model: "Fixture Printer",
                       paper_type: "Fixture Paper",
                       ink_type: "Fixture Ink"
                     })
                   end
    end

    test "raises when building response vectors for unpersisted palette colors" do
      %{printer_profile: printer_profile} = persisted_measurement_fixture()

      assert_raise ArgumentError,
                   "response_vectors/2 requires persisted palette colors with hex colors",
                   fn ->
                     Persistence.response_vectors(
                       [%PaletteColor{hex_color: "#112233", sort_order: 0}],
                       printer_profile
                     )
                   end
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

  describe "illuminant responses" do
    test "creates, updates, clears, and fetches a score per color, profile, and illuminant" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      attrs = %{
        color_id: color.id,
        printer_profile_id: printer_profile.id,
        illuminant: "red",
        apparent_brightness: 7,
        notes: "Compared with printed reference scale"
      }

      assert {:ok, response} = Persistence.set_illuminant_response(attrs)
      assert response.apparent_brightness == 7

      assert Persistence.get_illuminant_response(color.id, printer_profile.id, "red").id ==
               response.id

      assert Persistence.list_illuminant_responses(color.id, printer_profile.id)["red"].id ==
               response.id

      assert {:ok, updated} =
               Persistence.update_illuminant_response(%{attrs | apparent_brightness: 4})

      assert updated.id == response.id
      assert updated.apparent_brightness == 4

      assert {1, nil} = Persistence.clear_illuminant_response(color.id, printer_profile.id, "red")
      assert Persistence.get_illuminant_response(color.id, printer_profile.id, "red") == nil
    end

    test "validates the subjective 0 to 10 score and separates profiles and illuminants" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      for score <- [-1, 11] do
        assert {:error, changeset} =
                 Persistence.set_illuminant_response(%{
                   palette_color_id: color.id,
                   printer_profile_id: printer_profile.id,
                   illuminant: "white",
                   apparent_brightness: score
                 })

        assert %{apparent_brightness: [_]} = errors_on(changeset)
      end

      assert {:ok, _} =
               Persistence.set_illuminant_response(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 illuminant: "white",
                 apparent_brightness: 5
               })

      assert {:ok, _} =
               Persistence.set_illuminant_response(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 illuminant: "blue",
                 apparent_brightness: 6
               })

      assert Map.keys(Persistence.list_illuminant_responses(color.id, printer_profile.id)) == [
               "blue",
               "white"
             ]

      assert Persistence.list_illuminant_responses(color.id, printer_profile.id)["white"].apparent_brightness ==
               5

      assert Persistence.list_illuminant_responses(color.id, printer_profile.id)["blue"].apparent_brightness ==
               6
    end

    test "validates source_measurement_id against the response scope" do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()
      %{color: other_color} = persisted_measurement_fixture()
      %{printer_profile: other_printer_profile} = persisted_measurement_fixture()

      assert {:ok, matching_measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.42
               })

      assert {:ok, wrong_color_measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: other_color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.43
               })

      assert {:ok, wrong_profile_measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: other_printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.44
               })

      assert {:ok, wrong_illuminant_measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "blue",
                 normalized_brightness: 0.45
               })

      valid_attrs = %{
        palette_color_id: color.id,
        printer_profile_id: printer_profile.id,
        illuminant: "white",
        apparent_brightness: 5
      }

      assert {:ok, response} =
               Persistence.set_illuminant_response(
                 Map.put(valid_attrs, :source_measurement_id, matching_measurement.id)
               )

      assert response.source_measurement_id == matching_measurement.id

      for measurement <- [
            wrong_color_measurement,
            wrong_profile_measurement,
            wrong_illuminant_measurement
          ] do
        assert {:error, changeset} =
                 Persistence.set_illuminant_response(
                   Map.put(valid_attrs, :source_measurement_id, measurement.id)
                 )

        assert %{
                 source_measurement_id: [
                   "must belong to the same palette color, printer profile, and illuminant"
                 ]
               } =
                 errors_on(changeset)
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

  describe "printed pair classifications" do
    test "stores notes and fetches the active classification by pair, profile, and illuminant" do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Visible match under sodium vapor"
               })

      assert classification.active == true
      assert classification.notes == "Visible match under sodium vapor"

      persisted =
        Persistence.get_active_printed_pair_classification(pair.id, printer_profile.id, "lps")

      assert persisted.id == classification.id
      assert persisted.classification == "strong_metamer"
      assert persisted.notes == "Visible match under sodium vapor"
      assert persisted.test_sheet_pair.pair_id == pair.pair_id
      assert persisted.reproduction_profile.id == printer_profile.id
    end

    test "updates the current classification by appending history and keeping only one active row" do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, first} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "red",
                 classification: "weak_metamer",
                 notes: "First pass"
               })

      assert {:ok, second} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "red",
                 classification: "contrasting",
                 notes: "Reclassified after review"
               })

      active =
        Persistence.get_active_printed_pair_classification(pair.id, printer_profile.id, "red")

      history =
        Persistence.list_printed_pair_classification_history(pair.id, printer_profile.id, "red")

      assert active.id == second.id
      assert active.classification == "contrasting"
      assert Enum.map(history, & &1.id) == [second.id, first.id]
      assert Enum.map(history, & &1.active) == [true, false]

      assert Repo.aggregate(
               from(
                 classification in PrintedPairClassification,
                 where:
                   classification.test_sheet_pair_id == ^pair.id and
                     classification.reproduction_profile_id == ^printer_profile.id and
                     classification.illuminant == "red" and
                     classification.active == true
               ),
               :count,
               :id
             ) == 1
    end

    test "clears the current classification without deleting history" do
      %{pair: pair, printer_profile: printer_profile} = printed_pair_classification_fixture()

      assert {:ok, classification} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "blue",
                 classification: "strong_metamer"
               })

      assert {1, nil} =
               Persistence.clear_printed_pair_classification(pair.id, printer_profile.id, "blue")

      assert Persistence.get_active_printed_pair_classification(
               pair.id,
               printer_profile.id,
               "blue"
             ) ==
               nil

      [persisted] =
        Persistence.list_printed_pair_classification_history(pair.id, printer_profile.id, "blue")

      assert persisted.id == classification.id
      assert persisted.active == false
    end

    test "lists active classifications with pair, profile, and illuminant filters" do
      %{
        pair: pair,
        second_pair: second_pair,
        printer_profile: printer_profile,
        second_printer_profile: second_printer_profile
      } = printed_pair_classification_fixture()

      assert {:ok, matching} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "strong_metamer",
                 notes: "Target scope"
               })

      assert {:ok, _other_illuminant} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "green",
                 classification: "weak_metamer"
               })

      assert {:ok, _other_profile} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: pair.id,
                 reproduction_profile_id: second_printer_profile.id,
                 illuminant: "lps",
                 classification: "contrasting"
               })

      assert {:ok, _other_pair} =
               Persistence.set_printed_pair_classification(%{
                 test_sheet_pair_id: second_pair.id,
                 reproduction_profile_id: printer_profile.id,
                 illuminant: "lps",
                 classification: "weak_metamer"
               })

      filtered =
        Persistence.list_printed_pair_classifications(%{
          pair_id: pair.pair_id,
          reproduction_profile_id: printer_profile.id,
          illuminant: "lps"
        })

      assert Enum.map(filtered, & &1.id) == [matching.id]
      assert hd(filtered).notes == "Target scope"
      assert hd(filtered).test_sheet_pair.id == pair.id
      assert hd(filtered).reproduction_profile.id == printer_profile.id

      assert Persistence.list_printed_pair_classifications(%{
               classification: "strong_metamer",
               active: true
             })
             |> Enum.map(& &1.id)
             |> Enum.sort() == Enum.sort([matching.id])
    end
  end

  defp persisted_measurement_fixture do
    unique_suffix = System.unique_integer([:positive])

    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Measured Swatches #{unique_suffix}",
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

  defp printed_pair_classification_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Printed Pair Palette",
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
               lookup_code: "PARK-TEST",
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
      pair: pair,
      second_pair: second_pair,
      printer_profile: printer_profile,
      second_printer_profile: second_printer_profile
    }
  end
end

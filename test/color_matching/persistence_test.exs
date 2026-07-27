defmodule ColorMatching.PersistenceTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.Persistence

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
  end
end

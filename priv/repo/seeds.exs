alias ColorMatching.Persistence
alias ColorMatching.Persistence.TestSheet

case Persistence.import_preset_palettes() do
  {:ok, palettes} ->
    IO.puts("Imported #{length(palettes)} preset palettes")

  {:error, changeset} ->
    raise "Preset palette import failed: #{inspect(changeset.errors)}"
end

# ---------------------------------------------------------------------------
# Dev fixture: one complete test sheet usable by the iOS companion app.
#
# Lookup code "LPSM-DEV1" is intentionally hard-coded so the iOS app can
# always find this fixture without scanning a QR code.
# ---------------------------------------------------------------------------

dev_lookup_code = "LPSM-DEV1"

unless Enum.any?(Persistence.list_test_sheets(), &(&1.lookup_code == dev_lookup_code)) do
  # Use the "Sodium Metamers A" preset palette (first colour in the list).
  palette =
    case Enum.find(Persistence.list_palettes(), &(&1.name == "Sodium Metamers A")) do
      nil -> raise "Preset palette 'Sodium Metamers A' not found — run import first"
      p -> p
    end

  # Create a minimal printer profile for the dev fixture.
  {:ok, profile} =
    Persistence.create_printer_profile(%{
      printer_make_model: "Generic Inkjet",
      paper_type: "Plain",
      ink_type: "Dye",
      notes: "Dev fixture profile — not a real printer"
    })

  # Build a 3×3 grid of pairs from the first three palette colours.
  colors = palette.colors |> Enum.take(3) |> Enum.map(& &1.hex_color)
  grid = ColorMatching.Grid.new(colors, 3)

  pairs =
    for row_cells <- grid.grid, cell <- row_cells do
      %{
        pair_id: TestSheet.pair_id(dev_lookup_code, cell.row, cell.col),
        row: cell.row,
        col: cell.col,
        color_a_hex: cell.top_left_color,
        color_b_hex: cell.bottom_right_color
      }
    end

  {:ok, sheet} =
    Persistence.create_test_sheet(%{
      lookup_code: dev_lookup_code,
      palette_id: palette.id,
      printer_profile_id: profile.id,
      sheet_version: "lps-letter-grid-v1",
      page_width_mm: 215.9,
      page_height_mm: 279.4,
      page_units: "mm",
      reg_marker_layout: Jason.encode!(%{type: "corner_circles", radius_mm: 5.0}),
      patch_layout: Jason.encode!(%{grid_size: 3, cell_size_mm: 20.0, gap_mm: 2.0}),
      safe_inset_mm: 12.7,
      pairs: pairs
    })

  IO.puts("Created dev test sheet: #{sheet.lookup_code} (id=#{sheet.id})")
end

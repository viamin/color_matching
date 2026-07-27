alias ColorMatching.Persistence
alias ColorMatching.Persistence.PrinterProfile
alias ColorMatching.Persistence.TestSheet
alias ColorMatching.Repo
import Ecto.Query, only: [from: 2]

case Persistence.import_preset_palettes() do
  {:ok, palettes} ->
    IO.puts("Imported #{length(palettes)} preset palettes")

  {:error, changeset} ->
    raise "Preset palette import failed: #{inspect(changeset.errors)}"
end

# ---------------------------------------------------------------------------
# Dev fixture: one complete test sheet usable by the iOS companion app.
#
# Lookup code "LPSM-DEV2" is intentionally hard-coded so the iOS app can
# always find this fixture without scanning a QR code.
# ---------------------------------------------------------------------------

dev_lookup_code = "LPSM-DEV2"
dev_profile_notes = "Dev fixture profile for #{dev_lookup_code} — not a real printer"

case Repo.transaction(fn ->
       case Repo.get_by(ColorMatching.Persistence.TestSheet, lookup_code: dev_lookup_code) do
         %ColorMatching.Persistence.TestSheet{} = existing_sheet ->
           existing_sheet

         nil ->
           # Use the "Sodium Metamers A" preset palette (first colour in the list).
           palette =
             case Enum.find(Persistence.list_palettes(), &(&1.name == "Sodium Metamers A")) do
               nil -> Repo.rollback("Preset palette 'Sodium Metamers A' not found — run import first")
               p -> p
             end

           profile =
             case Repo.one(
                    from(profile in PrinterProfile,
                      where: profile.notes == ^dev_profile_notes,
                      order_by: [asc: profile.id],
                      limit: 1
                    )
                  ) do
               %PrinterProfile{} = existing_profile ->
                 existing_profile

               nil ->
                 case Persistence.create_printer_profile(%{
                        printer_make_model: "Generic Inkjet",
                        paper_type: "Plain",
                        ink_type: "Dye",
                        notes: dev_profile_notes
                      }) do
                   {:ok, created_profile} -> created_profile
                   {:error, changeset} -> Repo.rollback(changeset)
                 end
             end

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

           case Persistence.create_test_sheet(%{
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
                }) do
             {:ok, created_sheet} -> created_sheet
             {:error, changeset} -> Repo.rollback(changeset)
           end
       end
     end) do
  {:ok, %ColorMatching.Persistence.TestSheet{id: id, lookup_code: ^dev_lookup_code}} ->
    IO.puts("Ensured dev test sheet: #{dev_lookup_code} (id=#{id})")

  {:error, error} ->
    raise "Dev test sheet seed failed: #{inspect(error)}"
end

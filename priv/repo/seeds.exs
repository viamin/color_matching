alias ColorMatching.Persistence

case Persistence.import_preset_palettes() do
  {:ok, palettes} ->
    IO.puts("Imported #{length(palettes)} preset palettes")

  {:error, changeset} ->
    raise "Preset palette import failed: #{inspect(changeset.errors)}"
end

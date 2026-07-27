defmodule ColorMatching.Repo.Migrations.CreateTestSheets do
  use Ecto.Migration

  def change do
    create table(:test_sheets) do
      add :lookup_code, :string, null: false
      add :palette_id, references(:palettes, on_delete: :restrict), null: false
      add :printer_profile_id, references(:printer_profiles, on_delete: :restrict), null: false
      add :sheet_version, :string, null: false
      add :page_width_mm, :float
      add :page_height_mm, :float
      add :page_units, :string
      add :reg_marker_layout, :text
      add :patch_layout, :text
      add :safe_inset_mm, :float

      timestamps()
    end

    create unique_index(:test_sheets, [:lookup_code])
    create index(:test_sheets, [:palette_id])
    create index(:test_sheets, [:printer_profile_id])

    create table(:test_sheet_pairs) do
      add :test_sheet_id, references(:test_sheets, on_delete: :delete_all), null: false
      add :pair_id, :string, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :color_a_hex, :string, null: false
      add :color_b_hex, :string, null: false

      timestamps()
    end

    create index(:test_sheet_pairs, [:test_sheet_id])
    create unique_index(:test_sheet_pairs, [:pair_id])
    create unique_index(:test_sheet_pairs, [:test_sheet_id, :row, :col])
  end
end

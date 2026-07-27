defmodule ColorMatching.Repo.Migrations.CreatePalettesAndPrinterProfiles do
  use Ecto.Migration

  def change do
    create table(:palettes) do
      add :name, :string, null: false
      add :is_preset, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:palettes, [:name])

    create table(:palette_colors) do
      add :palette_id, references(:palettes, on_delete: :delete_all), null: false
      add :hex_color, :string, null: false
      add :display_label, :string
      add :sort_order, :integer, null: false

      timestamps()
    end

    create index(:palette_colors, [:palette_id])
    create unique_index(:palette_colors, [:palette_id, :sort_order])

    create table(:printer_profiles) do
      add :printer_make_model, :string, null: false
      add :paper_type, :string, null: false
      add :ink_type, :string, null: false
      add :icc_profile, :string
      add :print_settings, :string
      add :driver_name, :string
      add :driver_version, :string
      add :calibration_date, :date
      add :calibration_version, :string
      add :notes, :text

      timestamps()
    end
  end
end

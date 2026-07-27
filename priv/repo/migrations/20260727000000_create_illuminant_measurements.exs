defmodule ColorMatching.Repo.Migrations.CreateIlluminantMeasurements do
  use Ecto.Migration

  def change do
    create table(:illuminant_measurements) do
      add :palette_color_id, references(:palette_colors, on_delete: :delete_all), null: false
      add :printer_profile_id, references(:printer_profiles, on_delete: :delete_all), null: false
      add :light_source, :string, null: false
      add :normalized_brightness, :float, null: false
      add :raw_measured_value, :float
      add :raw_value_unit, :string
      add :notes, :text
      add :measured_at, :utc_datetime_usec
      add :measurement_method, :string
      add :measurement_device, :string
      add :test_run_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:illuminant_measurements, [:palette_color_id])
    create index(:illuminant_measurements, [:printer_profile_id])

    create index(:illuminant_measurements, [
             :palette_color_id,
             :printer_profile_id,
             :light_source,
             :measured_at,
             :inserted_at,
             :id
           ])
  end
end

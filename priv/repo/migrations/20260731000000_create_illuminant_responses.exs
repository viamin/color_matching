defmodule ColorMatching.Repo.Migrations.CreateIlluminantResponses do
  use Ecto.Migration

  def change do
    create table(:illuminant_responses) do
      add(:palette_color_id, references(:palette_colors, on_delete: :delete_all), null: false)
      add(:printer_profile_id, references(:printer_profiles, on_delete: :delete_all), null: false)
      add(:source_measurement_id, references(:illuminant_measurements, on_delete: :nilify_all))
      add(:illuminant, :string, null: false)
      add(:apparent_brightness, :integer, null: false)
      add(:notes, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:illuminant_responses, [:palette_color_id]))
    create(index(:illuminant_responses, [:printer_profile_id]))

    create(
      unique_index(:illuminant_responses, [
        :palette_color_id,
        :printer_profile_id,
        :illuminant
      ], name: :illuminant_responses_color_profile_illuminant_index)
    )
  end
end

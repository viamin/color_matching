defmodule ColorMatching.Repo.Migrations.CreatePairFindingsAndObservations do
  use Ecto.Migration

  def change do
    create table(:pair_findings) do
      add :test_sheet_id, references(:test_sheets, on_delete: :delete_all), null: false
      add :test_sheet_pair_id, references(:test_sheet_pairs, on_delete: :delete_all), null: false
      add :printer_profile_id, references(:printer_profiles, on_delete: :restrict), null: false
      add :pair_id, :string, null: false
      add :color_a_hex, :string, null: false
      add :color_b_hex, :string, null: false
      add :current_judgment, :string, null: false
      add :current_capture_id, references(:captures, on_delete: :restrict), null: false
      add :current_observed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:pair_findings, [:test_sheet_id])
    create index(:pair_findings, [:printer_profile_id])
    create unique_index(:pair_findings, [:test_sheet_pair_id])
    create unique_index(:pair_findings, [:pair_id])

    create table(:pair_finding_observations) do
      add :pair_finding_id, references(:pair_findings, on_delete: :delete_all), null: false
      add :capture_id, references(:captures, on_delete: :restrict), null: false
      add :test_sheet_id, references(:test_sheets, on_delete: :delete_all), null: false
      add :test_sheet_pair_id, references(:test_sheet_pairs, on_delete: :delete_all), null: false
      add :printer_profile_id, references(:printer_profiles, on_delete: :restrict), null: false
      add :pair_id, :string, null: false
      add :color_a_hex, :string, null: false
      add :color_b_hex, :string, null: false
      add :judgment, :string, null: false
      add :observed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:pair_finding_observations, [:pair_finding_id])
    create index(:pair_finding_observations, [:capture_id])
    create index(:pair_finding_observations, [:test_sheet_pair_id])
    create index(:pair_finding_observations, [:pair_id])
    create index(:pair_finding_observations, [:printer_profile_id])
  end
end

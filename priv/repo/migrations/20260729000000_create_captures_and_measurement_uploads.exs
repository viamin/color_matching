defmodule ColorMatching.Repo.Migrations.CreateCapturesAndMeasurementUploads do
  use Ecto.Migration

  def change do
    create table(:captures) do
      add :test_sheet_id, references(:test_sheets, on_delete: :delete_all), null: false
      add :device_model, :string, null: false
      add :lens, :string, null: false
      add :exposure_duration, :float
      add :iso, :integer
      add :focus_lens_position, :float
      add :white_balance_gains, :text
      add :image_width, :integer, null: false
      add :image_height, :integer, null: false
      add :app_version, :string, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :detected_marker_count, :integer
      add :blur_score, :float
      add :rejection_reasons, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:captures, [:test_sheet_id])

    create table(:capture_patch_measurements) do
      add :capture_id, references(:captures, on_delete: :delete_all), null: false
      add :patch_id, :string, null: false
      add :linear_rgb_median, :text, null: false
      add :normalized_linear_rgb_median, :text, null: false
      add :sample_count, :integer, null: false
      add :clipping_fraction, :float, null: false
      add :mean, :text, null: false
      add :standard_deviation, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:capture_patch_measurements, [:capture_id])
    create unique_index(:capture_patch_measurements, [:capture_id, :patch_id])

    create table(:capture_pair_scores) do
      add :capture_id, references(:captures, on_delete: :delete_all), null: false
      add :pair_id, :string, null: false
      add :algorithm_version, :string, null: false
      add :score, :float, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:capture_pair_scores, [:capture_id])
    create unique_index(:capture_pair_scores, [:capture_id, :pair_id, :algorithm_version])
  end
end

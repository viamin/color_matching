defmodule ColorMatching.Repo.Migrations.CreatePrintedPairClassifications do
  use Ecto.Migration

  def change do
    create table(:printed_pair_classifications) do
      add :test_sheet_pair_id, references(:test_sheet_pairs, on_delete: :delete_all), null: false
      add :printer_profile_id, references(:printer_profiles, on_delete: :restrict), null: false
      add :illuminant, :string, null: false
      add :classification, :string, null: false
      add :active, :boolean, null: false, default: true
      add :notes, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:printed_pair_classifications, [:printer_profile_id])
    create index(:printed_pair_classifications, [:test_sheet_pair_id])
    create unique_index(
      :printed_pair_classifications,
      [:test_sheet_pair_id, :printer_profile_id, :illuminant],
      where: "active = 1",
      name: :printed_pair_classifications_active_key
    )
  end
end

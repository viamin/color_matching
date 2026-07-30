defmodule ColorMatching.Persistence.PrinterProfile do
  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{
    IlluminantMeasurement,
    IlluminantResponse,
    PairFinding,
    PairFindingObservation,
    PrintedPairClassification
  }

  @type t :: %__MODULE__{
          id: integer() | nil,
          printer_make_model: String.t() | nil,
          paper_type: String.t() | nil,
          ink_type: String.t() | nil,
          icc_profile: String.t() | nil,
          print_settings: String.t() | nil,
          driver_name: String.t() | nil,
          driver_version: String.t() | nil,
          calibration_date: Date.t() | nil,
          calibration_version: String.t() | nil,
          notes: String.t() | nil,
           illuminant_measurements: [IlluminantMeasurement.t()] | Ecto.Association.NotLoaded.t(),
           illuminant_responses: [IlluminantResponse.t()] | Ecto.Association.NotLoaded.t(),

          pair_findings: [PairFinding.t()] | Ecto.Association.NotLoaded.t(),
          pair_finding_observations:
            [PairFindingObservation.t()] | Ecto.Association.NotLoaded.t(),
          printed_pair_classifications:
            [PrintedPairClassification.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "printer_profiles" do
    field(:printer_make_model, :string)
    field(:paper_type, :string)
    field(:ink_type, :string)
    field(:icc_profile, :string)
    field(:print_settings, :string)
    field(:driver_name, :string)
    field(:driver_version, :string)
    field(:calibration_date, :date)
    field(:calibration_version, :string)
    field(:notes, :string)

     has_many(:illuminant_measurements, IlluminantMeasurement)
     has_many(:illuminant_responses, IlluminantResponse)

    has_many(:pair_findings, PairFinding)
    has_many(:pair_finding_observations, PairFindingObservation)

    has_many(:printed_pair_classifications, PrintedPairClassification,
      foreign_key: :reproduction_profile_id
    )

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(printer_profile, attrs) do
    printer_profile
    |> cast(attrs, [
      :printer_make_model,
      :paper_type,
      :ink_type,
      :icc_profile,
      :print_settings,
      :driver_name,
      :driver_version,
      :calibration_date,
      :calibration_version,
      :notes
    ])
    |> validate_required([:printer_make_model, :paper_type, :ink_type])
  end
end

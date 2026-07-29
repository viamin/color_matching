defmodule ColorMatching.Persistence.PairFindingObservation do
  @moduledoc """
  Append-only observation history for iOS pair judgments.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{Capture, PairFinding, PrinterProfile, TestSheet, TestSheetPair}

  @judgments ~w[match near_match no_match]

  @type judgment :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          pair_finding_id: integer() | nil,
          pair_finding: PairFinding.t() | Ecto.Association.NotLoaded.t(),
          capture_id: integer() | nil,
          capture: Capture.t() | Ecto.Association.NotLoaded.t(),
          test_sheet_id: integer() | nil,
          test_sheet: TestSheet.t() | Ecto.Association.NotLoaded.t(),
          test_sheet_pair_id: integer() | nil,
          test_sheet_pair: TestSheetPair.t() | Ecto.Association.NotLoaded.t(),
          printer_profile_id: integer() | nil,
          printer_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          pair_id: String.t() | nil,
          color_a_hex: String.t() | nil,
          color_b_hex: String.t() | nil,
          judgment: judgment() | nil,
          observed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pair_finding_observations" do
    field(:pair_id, :string)
    field(:color_a_hex, :string)
    field(:color_b_hex, :string)
    field(:judgment, :string)
    field(:observed_at, :utc_datetime_usec)

    belongs_to(:pair_finding, PairFinding)
    belongs_to(:capture, Capture)
    belongs_to(:test_sheet, TestSheet)
    belongs_to(:test_sheet_pair, TestSheetPair)
    belongs_to(:printer_profile, PrinterProfile)

    timestamps(type: :utc_datetime_usec)
  end

  @spec judgments() :: [judgment()]
  def judgments, do: @judgments

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(observation, attrs) do
    observation
    |> cast(attrs, [
      :pair_finding_id,
      :capture_id,
      :test_sheet_id,
      :test_sheet_pair_id,
      :printer_profile_id,
      :pair_id,
      :color_a_hex,
      :color_b_hex,
      :judgment,
      :observed_at
    ])
    |> validate_required([
      :pair_finding_id,
      :capture_id,
      :test_sheet_id,
      :test_sheet_pair_id,
      :printer_profile_id,
      :pair_id,
      :color_a_hex,
      :color_b_hex,
      :judgment,
      :observed_at
    ])
    |> validate_inclusion(:judgment, @judgments)
    |> validate_format(:color_a_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> validate_format(:color_b_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> foreign_key_constraint(:pair_finding_id)
    |> foreign_key_constraint(:capture_id)
    |> foreign_key_constraint(:test_sheet_id)
    |> foreign_key_constraint(:test_sheet_pair_id)
    |> foreign_key_constraint(:printer_profile_id)
  end
end

defmodule ColorMatching.Persistence.PairFinding do
  @moduledoc """
  Derived current judgment for a printed test sheet pair.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{
    Capture,
    PairFindingObservation,
    PrinterProfile,
    TestSheet,
    TestSheetPair
  }

  @judgments ~w[match near_match no_match]

  @type judgment :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_sheet_id: integer() | nil,
          test_sheet: TestSheet.t() | Ecto.Association.NotLoaded.t(),
          test_sheet_pair_id: integer() | nil,
          test_sheet_pair: TestSheetPair.t() | Ecto.Association.NotLoaded.t(),
          printer_profile_id: integer() | nil,
          printer_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          pair_id: String.t() | nil,
          color_a_hex: String.t() | nil,
          color_b_hex: String.t() | nil,
          current_judgment: judgment() | nil,
          current_capture_id: integer() | nil,
          current_capture: Capture.t() | Ecto.Association.NotLoaded.t(),
          current_observed_at: DateTime.t() | nil,
          observations: [PairFindingObservation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pair_findings" do
    field(:pair_id, :string)
    field(:color_a_hex, :string)
    field(:color_b_hex, :string)
    field(:current_judgment, :string)
    field(:current_observed_at, :utc_datetime_usec)

    belongs_to(:test_sheet, TestSheet)
    belongs_to(:test_sheet_pair, TestSheetPair)
    belongs_to(:printer_profile, PrinterProfile)
    belongs_to(:current_capture, Capture, foreign_key: :current_capture_id)

    has_many(:observations, PairFindingObservation)

    timestamps(type: :utc_datetime_usec)
  end

  @spec judgments() :: [judgment()]
  def judgments, do: @judgments

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pair_finding, attrs) do
    pair_finding
    |> cast(attrs, [
      :test_sheet_id,
      :test_sheet_pair_id,
      :printer_profile_id,
      :pair_id,
      :color_a_hex,
      :color_b_hex,
      :current_judgment,
      :current_capture_id,
      :current_observed_at
    ])
    |> validate_required([
      :test_sheet_id,
      :test_sheet_pair_id,
      :printer_profile_id,
      :pair_id,
      :color_a_hex,
      :color_b_hex,
      :current_judgment,
      :current_capture_id,
      :current_observed_at
    ])
    |> validate_inclusion(:current_judgment, @judgments)
    |> validate_format(:color_a_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> validate_format(:color_b_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> foreign_key_constraint(:test_sheet_id)
    |> foreign_key_constraint(:test_sheet_pair_id)
    |> foreign_key_constraint(:printer_profile_id)
    |> foreign_key_constraint(:current_capture_id)
    |> unique_constraint(:test_sheet_pair_id)
    |> unique_constraint(:pair_id)
  end
end

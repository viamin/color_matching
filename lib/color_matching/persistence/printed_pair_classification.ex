defmodule ColorMatching.Persistence.PrintedPairClassification do
  @moduledoc """
  A human classification of how two printed swatches behave under an illuminant.

  Classifications are separate from capture-derived pair findings. A pair may
  have many historical classifications, but only one active classification is
  allowed for a pair, illuminant, and reproduction profile.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{PrinterProfile, TestSheetPair}

  @illuminants ~w[lps red green blue]
  @classifications ~w[strong_metamer weak_metamer contrasting]

  @type illuminant :: String.t()
  @type classification :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_sheet_pair_id: integer() | nil,
          test_sheet_pair: TestSheetPair.t() | Ecto.Association.NotLoaded.t(),
          reproduction_profile_id: integer() | nil,
          reproduction_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          illuminant: illuminant() | nil,
          classification: classification() | nil,
          active: boolean(),
          notes: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "printed_pair_classifications" do
    field(:illuminant, :string)
    field(:classification, :string)
    field(:active, :boolean, default: true)
    field(:notes, :string)

    belongs_to(:test_sheet_pair, TestSheetPair)
    belongs_to(:reproduction_profile, PrinterProfile, foreign_key: :reproduction_profile_id)

    timestamps(type: :utc_datetime_usec)
  end

  @spec illuminants() :: [illuminant()]
  def illuminants, do: @illuminants

  @spec classifications() :: [classification()]
  def classifications, do: @classifications

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(classification, attrs) do
    classification
    |> cast(attrs, [
      :test_sheet_pair_id,
      :reproduction_profile_id,
      :illuminant,
      :classification,
      :active,
      :notes
    ])
    |> validate_required([
      :test_sheet_pair_id,
      :reproduction_profile_id,
      :illuminant,
      :classification,
      :active
    ])
    |> validate_inclusion(:illuminant, @illuminants)
    |> validate_inclusion(:classification, @classifications)
    |> foreign_key_constraint(:test_sheet_pair_id)
    |> foreign_key_constraint(:reproduction_profile_id)
    |> unique_constraint([:test_sheet_pair_id, :reproduction_profile_id, :illuminant],
      name: :printed_pair_classifications_active_key
    )
  end
end

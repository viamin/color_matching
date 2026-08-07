defmodule ColorMatching.Persistence.CapturePairScore do
  @moduledoc """
  Ecto schema for an algorithmic score attached to a captured pair.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.Capture

  @type t :: %__MODULE__{
          id: integer() | nil,
          capture_id: integer() | nil,
          capture: Capture.t() | Ecto.Association.NotLoaded.t(),
          pair_id: String.t() | nil,
          algorithm_version: String.t() | nil,
          score: float() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "capture_pair_scores" do
    field(:pair_id, :string)
    field(:algorithm_version, :string)
    field(:score, :float)

    belongs_to(:capture, Capture)

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pair_score, attrs) do
    pair_score
    |> cast(attrs, [:capture_id, :pair_id, :algorithm_version, :score])
    |> validate_required([:capture_id, :pair_id, :algorithm_version, :score])
    |> validate_number(:score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:capture_id)
    |> unique_constraint(:pair_id,
      name: :capture_pair_scores_capture_id_pair_id_algorithm_version_index
    )
  end
end

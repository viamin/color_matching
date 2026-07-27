defmodule ColorMatching.Persistence.TestSheetPair do
  @moduledoc """
  Ecto schema for a single color pair printed on a test sheet.

  Each pair occupies one grid cell identified by its `(row, col)` position and
  stores the two colors printed in that cell: `color_a_hex` (top-left triangle)
  and `color_b_hex` (bottom-right triangle).

  The `pair_id` field is a globally stable identifier derived from the parent
  sheet's `lookup_code` and this pair's position. Use
  `TestSheet.pair_id/3` to compute it:

      pair_id = TestSheet.pair_id(lookup_code, row, col)

  Pair IDs are stored in the database and carry a unique constraint so that
  capture and observation records can reference a specific printed patch without
  an ambiguous join.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.TestSheet

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_sheet_id: integer() | nil,
          test_sheet: TestSheet.t() | Ecto.Association.NotLoaded.t(),
          pair_id: String.t() | nil,
          row: integer() | nil,
          col: integer() | nil,
          color_a_hex: String.t() | nil,
          color_b_hex: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "test_sheet_pairs" do
    field(:pair_id, :string)
    field(:row, :integer)
    field(:col, :integer)
    field(:color_a_hex, :string)
    field(:color_b_hex, :string)

    belongs_to(:test_sheet, TestSheet)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_sheet_pair, attrs) do
    test_sheet_pair
    |> cast(attrs, [:pair_id, :row, :col, :color_a_hex, :color_b_hex])
    |> validate_required([:pair_id, :row, :col, :color_a_hex, :color_b_hex])
    |> validate_format(:color_a_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> validate_format(:color_b_hex, ~r/^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?$/)
    |> unique_constraint(:pair_id)
    |> unique_constraint(:row, name: :test_sheet_pairs_test_sheet_id_row_col_index)
  end
end

defmodule ColorMatching.Persistence.TestSheet do
  @moduledoc """
  Ecto schema for a persisted test sheet.

  A test sheet captures a snapshot of the grid configuration used to produce a
  specific physical print. Each sheet has a stable `lookup_code` (e.g. "LPSM-7K2N")
  that the iOS companion app uses for manifest lookup, capture upload, and result
  aggregation. The sheet belongs to a persisted palette and printer profile, and
  stores enough generation metadata to reproduce the iOS manifest.

  ## Lookup code

  The `lookup_code` is a 9-character code in "XXXX-XXXX" format using an
  unambiguous uppercase alphanumeric alphabet (no 0/O/1/I). If one is not
  provided at creation time, it is auto-generated. Codes are globally unique
  via a database-level unique index.

  ## Pair IDs

  Each row/column pair printed on the sheet needs a globally-stable identifier
  for capture and observation records. Use `pair_id/3` to derive the canonical
  ID for a given pair before inserting `TestSheetPair` records:

      pair_id = TestSheet.pair_id(lookup_code, row, col)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{
    PairFindingObservation,
    Palette,
    PrinterProfile,
    TestSheetPair
  }

  @type t :: %__MODULE__{
          id: integer() | nil,
          lookup_code: String.t() | nil,
          palette_id: integer() | nil,
          palette: Palette.t() | Ecto.Association.NotLoaded.t(),
          printer_profile_id: integer() | nil,
          printer_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          sheet_version: String.t() | nil,
          page_width_mm: float() | nil,
          page_height_mm: float() | nil,
          page_units: String.t() | nil,
          reg_marker_layout: String.t() | nil,
          patch_layout: String.t() | nil,
          safe_inset_mm: float() | nil,
          pairs: [TestSheetPair.t()] | Ecto.Association.NotLoaded.t(),
          pair_finding_observations:
            [PairFindingObservation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil,
          updated_at: DateTime.t() | NaiveDateTime.t() | nil
        }

  schema "test_sheets" do
    field(:lookup_code, :string)
    field(:sheet_version, :string)
    field(:page_width_mm, :float)
    field(:page_height_mm, :float)
    field(:page_units, :string)
    field(:reg_marker_layout, :string)
    field(:patch_layout, :string)
    field(:safe_inset_mm, :float)

    belongs_to(:palette, Palette)
    belongs_to(:printer_profile, PrinterProfile)

    has_many(:pairs, TestSheetPair,
      foreign_key: :test_sheet_id,
      on_replace: :delete,
      preload_order: [asc: :row, asc: :col, asc: :id]
    )

    has_many(:pair_finding_observations, PairFindingObservation,
      foreign_key: :test_sheet_id
    )

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_sheet, attrs) do
    attrs =
      attrs
      |> put_lookup_code_if_missing()
      |> put_canonical_pair_ids()

    test_sheet
    |> cast(attrs, [
      :lookup_code,
      :palette_id,
      :printer_profile_id,
      :sheet_version,
      :page_width_mm,
      :page_height_mm,
      :page_units,
      :reg_marker_layout,
      :patch_layout,
      :safe_inset_mm
    ])
    |> validate_format(:lookup_code, ~r/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/,
      message: "must be in XXXX-XXXX format using unambiguous characters (no 0, O, 1, I)"
    )
    |> validate_required([:lookup_code, :palette_id, :printer_profile_id, :sheet_version])
    |> cast_assoc(:pairs, with: &TestSheetPair.changeset/2)
    |> validate_length(:pairs, min: 1)
    |> unique_constraint(:lookup_code)
    |> foreign_key_constraint(:palette_id)
    |> foreign_key_constraint(:printer_profile_id)
  end

  @doc """
  Derives the canonical stable pair ID for a given (row, col) position on
  a sheet identified by `lookup_code`.

  The ID is deterministic: given the same inputs it always produces the same
  output, so it can be re-derived from a printed sheet's lookup code and a
  pair's grid coordinates without a database round-trip. The value is a
  17-character string of the form `"pair-"` followed by 12 lowercase hex digits
  drawn from the SHA-256 digest of `"<lookup_code>|<row>|<col>"`.
  """
  @spec pair_id(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  def pair_id(lookup_code, row, col) do
    material = "#{lookup_code}|#{row}|#{col}"
    hash = :crypto.hash(:sha256, material)
    "pair-" <> binary_part(Base.encode16(hash, case: :lower), 0, 12)
  end

  @doc """
  Generates a random 9-character lookup code in "XXXX-XXXX" format.

  Uses an unambiguous alphabet (uppercase letters and digits, excluding 0, O,
  1, and I) to produce codes safe for manual entry and QR scanning.
  """
  @spec generate_lookup_code() :: String.t()
  def generate_lookup_code do
    # 32-character alphabet with no ambiguous chars (0, O, 1, I excluded)
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    eight =
      :crypto.strong_rand_bytes(8)
      |> :binary.bin_to_list()
      |> Enum.map(fn byte -> String.at(chars, rem(byte, 32)) end)
      |> Enum.join()

    String.slice(eight, 0, 4) <> "-" <> String.slice(eight, 4, 4)
  end

  @spec put_lookup_code_if_missing(map()) :: map()
  defp put_lookup_code_if_missing(attrs) when is_map(attrs) do
    case get_attr(attrs, :lookup_code) do
      nil -> put_attr(attrs, :lookup_code, generate_lookup_code())
      _lookup_code -> attrs
    end
  end

  @spec put_canonical_pair_ids(map()) :: map()
  defp put_canonical_pair_ids(attrs) when is_map(attrs) do
    lookup_code = get_attr(attrs, :lookup_code)

    case get_attr(attrs, :pairs) do
      pairs when is_list(pairs) and is_binary(lookup_code) ->
        canonical_pairs = Enum.map(pairs, &canonicalize_pair(&1, lookup_code))
        put_attr(attrs, :pairs, canonical_pairs)

      _ ->
        attrs
    end
  end

  @spec canonicalize_pair(map(), String.t()) :: map()
  defp canonicalize_pair(pair_attrs, lookup_code) do
    case {get_attr(pair_attrs, :row), get_attr(pair_attrs, :col)} do
      {row, col} when is_integer(row) and is_integer(col) ->
        put_attr(pair_attrs, :pair_id, pair_id(lookup_code, row, col))

      _ ->
        pair_attrs
    end
  end

  @spec get_attr(map(), atom()) :: term()
  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  @spec put_attr(map(), atom(), term()) :: map()
  defp put_attr(attrs, key, value) when is_map(attrs) and is_atom(key) do
    if Map.has_key?(attrs, Atom.to_string(key)) do
      Map.put(attrs, Atom.to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end
end

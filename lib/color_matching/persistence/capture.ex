defmodule ColorMatching.Persistence.Capture do
  @moduledoc """
  Ecto schema for an iOS capture session tied to a printed test sheet.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{
    CapturePairScore,
    CapturePatchMeasurement,
    PairFindingObservation,
    TestSheet
  }

  @type t :: %__MODULE__{
          id: integer() | nil,
          test_sheet_id: integer() | nil,
          test_sheet: TestSheet.t() | Ecto.Association.NotLoaded.t(),
          device_model: String.t() | nil,
          lens: String.t() | nil,
          exposure_duration: float() | nil,
          iso: integer() | nil,
          focus_lens_position: float() | nil,
          white_balance_gains: String.t() | nil,
          image_width: integer() | nil,
          image_height: integer() | nil,
          app_version: String.t() | nil,
          timestamp: DateTime.t() | nil,
          detected_marker_count: integer() | nil,
          blur_score: float() | nil,
          rejection_reasons: String.t() | nil,
          patch_measurements: [CapturePatchMeasurement.t()] | Ecto.Association.NotLoaded.t(),
          pair_scores: [CapturePairScore.t()] | Ecto.Association.NotLoaded.t(),
          pair_finding_observations:
            [PairFindingObservation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "captures" do
    field(:device_model, :string)
    field(:lens, :string)
    field(:exposure_duration, :float)
    field(:iso, :integer)
    field(:focus_lens_position, :float)
    field(:white_balance_gains, :string)
    field(:image_width, :integer)
    field(:image_height, :integer)
    field(:app_version, :string)
    field(:timestamp, :utc_datetime_usec)
    field(:detected_marker_count, :integer)
    field(:blur_score, :float)
    field(:rejection_reasons, :string)

    belongs_to(:test_sheet, TestSheet)

    has_many(:patch_measurements, CapturePatchMeasurement,
      foreign_key: :capture_id,
      on_replace: :delete
    )

    has_many(:pair_scores, CapturePairScore,
      foreign_key: :capture_id,
      on_replace: :delete
    )

    has_many(:pair_finding_observations, PairFindingObservation,
      foreign_key: :capture_id,
      on_replace: :delete
    )

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(capture, attrs) do
    capture
    |> cast(attrs, [
      :test_sheet_id,
      :device_model,
      :lens,
      :exposure_duration,
      :iso,
      :focus_lens_position,
      :white_balance_gains,
      :image_width,
      :image_height,
      :app_version,
      :timestamp,
      :detected_marker_count,
      :blur_score,
      :rejection_reasons
    ])
    |> validate_required([
      :test_sheet_id,
      :device_model,
      :lens,
      :image_width,
      :image_height,
      :app_version,
      :timestamp
    ])
    |> validate_number(:exposure_duration, greater_than: 0.0)
    |> validate_number(:iso, greater_than: 0)
    |> validate_number(:focus_lens_position, greater_than_or_equal_to: 0.0)
    |> validate_number(:image_width, greater_than: 0)
    |> validate_number(:image_height, greater_than: 0)
    |> validate_number(:detected_marker_count, greater_than_or_equal_to: 0)
    |> validate_number(:blur_score, greater_than_or_equal_to: 0.0)
    |> validate_json_string(:white_balance_gains)
    |> validate_json_string(:rejection_reasons)
    |> foreign_key_constraint(:test_sheet_id)
  end

  @spec validate_json_string(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_json_string(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and valid_json?(value) do
        []
      else
        [{field, "must be valid JSON"}]
      end
    end)
  end

  @spec valid_json?(String.t()) :: boolean()
  defp valid_json?(value) when is_binary(value) do
    match?({:ok, _decoded}, Jason.decode(value))
  end
end

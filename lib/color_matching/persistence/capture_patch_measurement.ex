defmodule ColorMatching.Persistence.CapturePatchMeasurement do
  @moduledoc """
  Ecto schema for a per-patch measurement uploaded for a capture session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.Capture

  @type t :: %__MODULE__{
          id: integer() | nil,
          capture_id: integer() | nil,
          capture: Capture.t() | Ecto.Association.NotLoaded.t(),
          patch_id: String.t() | nil,
          linear_rgb_median: String.t() | nil,
          normalized_linear_rgb_median: String.t() | nil,
          sample_count: integer() | nil,
          clipping_fraction: float() | nil,
          mean: String.t() | nil,
          standard_deviation: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "capture_patch_measurements" do
    field(:patch_id, :string)
    field(:linear_rgb_median, :string)
    field(:normalized_linear_rgb_median, :string)
    field(:sample_count, :integer)
    field(:clipping_fraction, :float)
    field(:mean, :string)
    field(:standard_deviation, :string)

    belongs_to(:capture, Capture)

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(patch_measurement, attrs) do
    patch_measurement
    |> cast(attrs, [
      :capture_id,
      :patch_id,
      :linear_rgb_median,
      :normalized_linear_rgb_median,
      :sample_count,
      :clipping_fraction,
      :mean,
      :standard_deviation
    ])
    |> validate_required([
      :capture_id,
      :patch_id,
      :linear_rgb_median,
      :normalized_linear_rgb_median,
      :sample_count,
      :clipping_fraction,
      :mean,
      :standard_deviation
    ])
    |> validate_number(:sample_count, greater_than_or_equal_to: 0)
    |> validate_number(:clipping_fraction,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_json_string(:linear_rgb_median)
    |> validate_json_string(:normalized_linear_rgb_median)
    |> validate_json_string(:mean)
    |> validate_json_string(:standard_deviation)
    |> foreign_key_constraint(:capture_id)
    |> unique_constraint(:patch_id, name: :capture_patch_measurements_capture_id_patch_id_index)
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

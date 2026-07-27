defmodule ColorMatching.Persistence.IlluminantMeasurement do
  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{PaletteColor, PrinterProfile}

  @light_sources ~w(white red green blue lps)

  @type t :: %__MODULE__{
          id: integer() | nil,
          light_source: String.t() | nil,
          normalized_brightness: float() | nil,
          raw_measured_value: float() | nil,
          raw_value_unit: String.t() | nil,
          notes: String.t() | nil,
          measured_at: DateTime.t() | nil,
          measurement_method: String.t() | nil,
          measurement_device: String.t() | nil,
          test_run_id: String.t() | nil,
          palette_color_id: integer() | nil,
          palette_color: PaletteColor.t() | Ecto.Association.NotLoaded.t(),
          printer_profile_id: integer() | nil,
          printer_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @supported_light_sources @light_sources

  schema "illuminant_measurements" do
    field(:light_source, :string)
    field(:normalized_brightness, :float)
    field(:raw_measured_value, :float)
    field(:raw_value_unit, :string)
    field(:notes, :string)
    field(:measured_at, :utc_datetime_usec)
    field(:measurement_method, :string)
    field(:measurement_device, :string)
    field(:test_run_id, :string)

    belongs_to(:palette_color, PaletteColor)
    belongs_to(:printer_profile, PrinterProfile)

    timestamps(type: :utc_datetime_usec)
  end

  @spec supported_light_sources() :: [String.t()]
  def supported_light_sources, do: @supported_light_sources

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(illuminant_measurement, attrs) do
    illuminant_measurement
    |> cast(attrs, [
      :light_source,
      :normalized_brightness,
      :raw_measured_value,
      :raw_value_unit,
      :notes,
      :measured_at,
      :measurement_method,
      :measurement_device,
      :test_run_id,
      :palette_color_id,
      :printer_profile_id
    ])
    |> validate_required([
      :light_source,
      :normalized_brightness,
      :palette_color_id,
      :printer_profile_id
    ])
    |> validate_inclusion(:light_source, @light_sources)
    |> validate_number(:normalized_brightness,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> foreign_key_constraint(:palette_color_id)
    |> foreign_key_constraint(:printer_profile_id)
  end
end

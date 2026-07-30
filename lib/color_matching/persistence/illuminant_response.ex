defmodule ColorMatching.Persistence.IlluminantResponse do
  @moduledoc """
  A human-entered apparent brightness score for a printed swatch under one
  illuminant and printer profile.

  Scores use a subjective 0-10 scale, where 0 is black and 10 is white on the
  printed reference scale. The score describes apparent brightness only; it is
  not a pair classification or a claim that a swatch appears neutral gray.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.{IlluminantMeasurement, PaletteColor, PrinterProfile}

  @score_range 0..10

  @type t :: %__MODULE__{
          id: integer() | nil,
          palette_color_id: integer() | nil,
          palette_color: PaletteColor.t() | Ecto.Association.NotLoaded.t(),
          printer_profile_id: integer() | nil,
          printer_profile: PrinterProfile.t() | Ecto.Association.NotLoaded.t(),
          illuminant: String.t() | nil,
          apparent_brightness: integer() | nil,
          notes: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "illuminant_responses" do
    field(:illuminant, :string)
    field(:apparent_brightness, :integer)
    field(:notes, :string)

    belongs_to(:palette_color, PaletteColor)
    belongs_to(:printer_profile, PrinterProfile)
    belongs_to(:source_measurement, IlluminantMeasurement)

    timestamps(type: :utc_datetime_usec)
  end

  @spec score_range() :: Range.t()
  def score_range, do: @score_range

  @spec illuminants() :: [String.t()]
  def illuminants, do: IlluminantMeasurement.supported_light_sources()

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :palette_color_id,
      :printer_profile_id,
      :illuminant,
      :apparent_brightness,
      :notes,
      :source_measurement_id
    ])
    |> validate_required([:palette_color_id, :printer_profile_id, :illuminant, :apparent_brightness])
    |> validate_inclusion(:illuminant, illuminants())
    |> validate_number(:apparent_brightness,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10
    )
    |> foreign_key_constraint(:palette_color_id)
    |> foreign_key_constraint(:printer_profile_id)
    |> foreign_key_constraint(:source_measurement_id)
    |> unique_constraint([:palette_color_id, :printer_profile_id, :illuminant],
      name: :illuminant_responses_color_profile_illuminant_index
    )
  end
end

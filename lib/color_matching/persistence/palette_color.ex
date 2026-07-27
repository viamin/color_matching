defmodule ColorMatching.Persistence.PaletteColor do
  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.Palette

  @type t :: %__MODULE__{
          id: integer() | nil,
          hex_color: String.t() | nil,
          display_label: String.t() | nil,
          sort_order: integer() | nil,
          palette_id: integer() | nil,
          palette: Palette.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "palette_colors" do
    field :hex_color, :string
    field :display_label, :string
    field :sort_order, :integer

    belongs_to :palette, Palette

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(palette_color, attrs) do
    palette_color
    |> cast(attrs, [:hex_color, :display_label, :sort_order])
    |> validate_required([:hex_color, :sort_order])
    |> validate_format(:hex_color, ~r/^#[0-9A-Fa-f]{6}$/)
  end
end

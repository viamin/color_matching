defmodule ColorMatching.Persistence.Palette do
  use Ecto.Schema
  import Ecto.Changeset

  alias ColorMatching.Persistence.PaletteColor

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          is_preset: boolean(),
          colors: [PaletteColor.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "palettes" do
    field(:name, :string)
    field(:is_preset, :boolean, default: false)

    has_many(:colors, PaletteColor,
      foreign_key: :palette_id,
      on_replace: :delete,
      preload_order: [asc: :sort_order, asc: :id]
    )

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(palette, attrs) do
    palette
    |> cast(attrs, [:name, :is_preset])
    |> validate_required([:name])
    |> cast_assoc(:colors, with: &PaletteColor.changeset/2)
    |> reorder_assoc(:colors)
    |> unique_constraint(:name)
  end
end

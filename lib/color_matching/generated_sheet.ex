defmodule ColorMatching.GeneratedSheet do
  @moduledoc """
  Immutable representation of a generated print sheet.

  A sheet is only meaningful relative to the printer profile that produced it.
  """

  alias ColorMatching.PrinterProfile

  @enforce_keys [:id, :colors, :grid_size, :printer_profile]
  @derive Jason.Encoder
  defstruct id: nil,
            colors: [],
            grid_size: nil,
            palette_name: nil,
            printer_profile: nil

  @type t :: %__MODULE__{
          id: String.t(),
          colors: [String.t()],
          grid_size: pos_integer(),
          palette_name: String.t() | nil,
          printer_profile: PrinterProfile.t()
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    colors = Map.get(attrs, :colors) || []
    grid_size = Map.fetch!(attrs, :grid_size)
    palette_name = Map.get(attrs, :palette_name)
    printer_profile = Map.fetch!(attrs, :printer_profile)

    id = Map.get(attrs, :id) || sheet_id(colors, grid_size, palette_name, printer_profile)

    %__MODULE__{
      id: id,
      colors: colors,
      grid_size: grid_size,
      palette_name: palette_name,
      printer_profile: printer_profile
    }
  end

  defp sheet_id(colors, grid_size, palette_name, printer_profile) do
    material =
      [
        Enum.join(colors, ","),
        Integer.to_string(grid_size),
        palette_name || "",
        printer_profile.id
      ]
      |> Enum.join("|")

    "sheet-" <> binary_part(Base.encode16(:crypto.hash(:sha256, material), case: :lower), 0, 12)
  end
end

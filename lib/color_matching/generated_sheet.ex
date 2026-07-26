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
    sheet = %__MODULE__{
      id: Map.get(attrs, :id),
      colors: Map.get(attrs, :colors) || [],
      grid_size: Map.fetch!(attrs, :grid_size),
      palette_name: Map.get(attrs, :palette_name),
      printer_profile: Map.fetch!(attrs, :printer_profile)
    }

    %{sheet | id: sheet.id || sheet_id(sheet)}
  end

  defp sheet_id(%__MODULE__{} = sheet) do
    material =
      [
        Enum.join(sheet.colors, ","),
        Integer.to_string(sheet.grid_size),
        sheet.palette_name || "",
        sheet.printer_profile.id
      ]
      |> Enum.join("|")

    "sheet-" <> binary_part(Base.encode16(:crypto.hash(:sha256, material), case: :lower), 0, 12)
  end
end

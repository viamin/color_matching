defmodule ColorMatching.MeasuredColorPair do
  @moduledoc """
  Measurement candidate for a printed color pair.

  Measurements must remain scoped to the printer profile and sheet that
  produced the printed swatch.
  """

  alias ColorMatching.PrinterProfile

  @enforce_keys [:color_a, :color_b, :printer_profile]
  defstruct color_a: nil,
            color_b: nil,
            printer_profile: nil,
            generated_sheet_id: nil

  @type t :: %__MODULE__{
          color_a: String.t(),
          color_b: String.t(),
          printer_profile: PrinterProfile.t(),
          generated_sheet_id: String.t() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      color_a: Map.fetch!(attrs, :color_a),
      color_b: Map.fetch!(attrs, :color_b),
      printer_profile: Map.fetch!(attrs, :printer_profile),
      generated_sheet_id: Map.get(attrs, :generated_sheet_id)
    }
  end
end

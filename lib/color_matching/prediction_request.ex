defmodule ColorMatching.PredictionRequest do
  @moduledoc """
  Placeholder request shape for printer-specific prediction engines.

  Future prediction backends should accept this request type (or a compatible
  equivalent) so they are always invoked with explicit printer-profile
  context.
  """

  alias ColorMatching.PrinterProfile

  @enforce_keys [:target_colors, :printer_profile]
  defstruct target_colors: [],
            printer_profile: nil,
            notes: nil

  @type t :: %__MODULE__{
          target_colors: [String.t()],
          printer_profile: PrinterProfile.t(),
          notes: String.t() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      target_colors: Map.get(attrs, :target_colors) || [],
      printer_profile: Map.fetch!(attrs, :printer_profile),
      notes: Map.get(attrs, :notes)
    }
  end
end

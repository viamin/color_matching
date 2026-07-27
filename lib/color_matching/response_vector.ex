defmodule ColorMatching.ResponseVector do
  @moduledoc """
  Latest-measurement illuminant response vector for a printable color under a
  printer profile.

  Each printable color and printer profile combination yields a vector whose
  keys are the supported light sources (`:white`, `:red`, `:green`, `:blue`,
  `:lps`). The value for a key is either the latest `normalized_brightness`
  measurement (`float()` in `0.0..1.0`) or `:missing` when no measurement
  has been recorded for that light source.

  Missing values are first-class so callers can distinguish "never measured"
  from "measured as zero brightness". Scoring functions should treat missing
  values according to their own policy (see `ColorMatching.IlluminantScoring`).
  """

  alias ColorMatching.Persistence.IlluminantMeasurement

  @light_sources ~w(white red green blue lps)a

  @enforce_keys [:hex_color, :printer_profile_id]
  defstruct [
    :hex_color,
    :printer_profile_id,
    :measured_at,
    :inserted_at,
    :missing?,
    white: :missing,
    red: :missing,
    green: :missing,
    blue: :missing,
    lps: :missing
  ]

  @type light_source :: :white | :red | :green | :blue | :lps
  @type brightness :: float() | :missing
  @type profile_id :: String.t() | integer()
  @type t :: %__MODULE__{
          hex_color: String.t(),
          printer_profile_id: profile_id(),
          measured_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          missing?: boolean(),
          white: brightness(),
          red: brightness(),
          green: brightness(),
          blue: brightness(),
          lps: brightness()
        }

  @spec light_sources() :: [light_source()]
  def light_sources, do: @light_sources

  @spec supported_light_sources() :: [light_source()]
  @doc """
  Returns the supported light sources that participate in the response vector.

  Kept as an alias for `light_sources/0` so callers can refer to the supported
  set without implying "always available".
  """
  def supported_light_sources, do: light_sources()

  @doc """
  Builds a response vector from the latest measurements for a color.

  `hex_color` is the printable color in `#RRGGBB` form. `printer_profile_id`
  identifies the printer profile the measurements were taken under.
  `latest_measurements_by_light_source` is a map keyed by `String.t()`
  light source name (matching `ColorMatching.Persistence`'s convention).
  Light sources without a measurement are stored as `:missing`.

  ## Examples

      iex> ColorMatching.ResponseVector.new("#112233", "profile-test", %{"white" => measurement})
      %ColorMatching.ResponseVector{hex_color: "#112233", white: 0.5, red: :missing}
  """
  @spec new(
          String.t(),
          profile_id(),
          %{optional(String.t()) => IlluminantMeasurement.t()}
        ) :: t()
  def new(hex_color, printer_profile_id, latest_measurements_by_light_source)
      when is_binary(hex_color) and is_map(latest_measurements_by_light_source) do
    brightnesses =
      Map.new(@light_sources, fn source ->
        {source, brightness_for(source, latest_measurements_by_light_source)}
      end)

    timestamps = timestamps_for(latest_measurements_by_light_source)

    %__MODULE__{
      hex_color: hex_color,
      printer_profile_id: printer_profile_id,
      measured_at: timestamps.measured_at,
      inserted_at: timestamps.inserted_at,
      missing?: Enum.any?(@light_sources, &(Map.get(brightnesses, &1) == :missing))
    }
    |> Map.merge(brightnesses)
  end

  @spec value(t(), light_source()) :: brightness()
  def value(%__MODULE__{} = vector, light_source) when light_source in @light_sources do
    Map.fetch!(vector, light_source)
  end

  @spec brightness_map(t()) :: %{optional(light_source()) => brightness()}
  def brightness_map(%__MODULE__{} = vector) do
    Map.take(vector, @light_sources)
  end

  defp brightness_for(source, latest_measurements_by_light_source) do
    case Map.get(latest_measurements_by_light_source, Atom.to_string(source)) do
      %IlluminantMeasurement{normalized_brightness: brightness} when is_float(brightness) ->
        brightness

      %IlluminantMeasurement{normalized_brightness: brightness} when is_integer(brightness) ->
        brightness * 1.0

      _other ->
        :missing
    end
  end

  defp timestamps_for(latest_measurements_by_light_source) do
    measurements = Map.values(latest_measurements_by_light_source)

    measured_at =
      measurements
      |> Enum.map(& &1.measured_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)

    inserted_at =
      measurements
      |> Enum.map(& &1.inserted_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)

    %{measured_at: measured_at, inserted_at: inserted_at}
  end
end
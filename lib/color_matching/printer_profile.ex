defmodule ColorMatching.PrinterProfile do
  @moduledoc """
  First-class printer profile metadata for printer-dependent color matching.

  Profiles capture the print conditions that make an RGB swatch meaningful:
  printer hardware, substrate, consumables, color-management settings, and
  calibration state. Sheets, measurements, and future predictions should all
  carry this context instead of assuming RGB values are universal.
  """

  @enforce_keys [:id, :printer_make_model, :paper_type, :ink_type]
  @derive Jason.Encoder
  defstruct id: nil,
            printer_make_model: nil,
            paper_type: nil,
            ink_type: nil,
            icc_profile: nil,
            print_settings: nil,
            driver_name: nil,
            driver_version: nil,
            calibration_date: nil,
            calibration_version: nil,
            notes: nil

  @type t :: %__MODULE__{
          id: String.t(),
          printer_make_model: String.t(),
          paper_type: String.t(),
          ink_type: String.t(),
          icc_profile: String.t() | nil,
          print_settings: String.t() | nil,
          driver_name: String.t() | nil,
          driver_version: String.t() | nil,
          calibration_date: String.t() | nil,
          calibration_version: String.t() | nil,
          notes: String.t() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    profile = %__MODULE__{
      id: fetch(attrs, :id),
      printer_make_model: fetch(attrs, :printer_make_model),
      paper_type: fetch(attrs, :paper_type),
      ink_type: fetch(attrs, :ink_type),
      icc_profile: blank_to_nil(fetch(attrs, :icc_profile)),
      print_settings: blank_to_nil(fetch(attrs, :print_settings)),
      driver_name: blank_to_nil(fetch(attrs, :driver_name)),
      driver_version: blank_to_nil(fetch(attrs, :driver_version)),
      calibration_date: blank_to_nil(fetch(attrs, :calibration_date)),
      calibration_version: blank_to_nil(fetch(attrs, :calibration_version)),
      notes: blank_to_nil(fetch(attrs, :notes))
    }

    %{profile | id: profile.id || profile_id(profile)}
  end

  @spec validate(map()) :: {:ok, t()} | {:error, String.t()}
  def validate(attrs) when is_map(attrs) do
    with {:ok, printer_make_model} <-
           validate_required(attrs, :printer_make_model, "Printer make/model"),
         {:ok, paper_type} <- validate_required(attrs, :paper_type, "Paper type"),
         {:ok, ink_type} <- validate_required(attrs, :ink_type, "Ink type") do
      {:ok,
       new(
         attrs
         |> Map.put(:printer_make_model, printer_make_model)
         |> Map.put(:paper_type, paper_type)
         |> Map.put(:ink_type, ink_type)
       )}
    end
  end

  def validate(_attrs), do: {:error, "Printer profile attributes must be a map"}

  @spec from_map(map()) :: t() | nil
  def from_map(attrs) when is_map(attrs) do
    case validate(attrs) do
      {:ok, printer_profile} -> printer_profile
      {:error, _message} -> nil
    end
  end

  def from_map(_attrs), do: nil

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{} = profile) do
    "#{profile.printer_make_model} on #{profile.paper_type}"
  end

  @spec to_query_params(t()) :: keyword(String.t())
  def to_query_params(%__MODULE__{} = profile) do
    [profile_id: profile.id]
  end

  @spec default_profiles() :: [t()]
  def default_profiles do
    [
      new(%{
        id: "epson-p900-ultrapremium-luster-oem",
        printer_make_model: "Epson SureColor P900",
        paper_type: "Ultra Premium Luster",
        ink_type: "OEM UltraChrome PRO10",
        icc_profile: "SC-P900 Premium Luster",
        print_settings: "1440 dpi, high quality, no color adjustment",
        driver_name: "Epson macOS Driver",
        driver_version: "15.4",
        calibration_date: "2026-07-01",
        calibration_version: "baseline-1",
        notes: "Reference profile for luster paper swatches"
      }),
      new(%{
        id: "canon-pro-100-matte-third-party",
        printer_make_model: "Canon PRO-100",
        paper_type: "Matte Photo Paper",
        ink_type: "Third-party dye ink",
        icc_profile: "Custom Matte ICC",
        print_settings: "High quality matte, color management by application",
        driver_name: "Canon IJ",
        driver_version: "16.10",
        calibration_date: "2026-06-18",
        calibration_version: "matte-recal-2",
        notes: "Use only for exploratory matte runs"
      })
    ]
  end

  @spec merge_with_defaults([t()]) :: [t()]
  def merge_with_defaults(printer_profiles) when is_list(printer_profiles) do
    existing_ids = MapSet.new(printer_profiles, & &1.id)

    printer_profiles ++
      Enum.reject(default_profiles(), &MapSet.member?(existing_ids, &1.id))
  end

  @spec from_query_params(map(), [t()]) :: t() | nil
  def from_query_params(params, printer_profiles \\ default_profiles())
  def from_query_params(params, printer_profiles) when is_map(params) and is_list(printer_profiles) do
    profile_id = fetch(params, :profile_id)

    if is_binary(profile_id) do
      Enum.find(printer_profiles, &(&1.id == profile_id))
    end
  end

  def from_query_params(_params, _printer_profiles), do: nil

  defp validate_required(attrs, key, label) do
    value =
      attrs
      |> fetch(key)
      |> to_string_or_nil()
      |> case do
        nil -> nil
        string -> String.trim(string)
      end

    if value in [nil, ""] do
      {:error, "#{label} is required"}
    else
      {:ok, value}
    end
  end

  defp profile_id(%__MODULE__{} = profile) do
    material =
      [
        profile.printer_make_model,
        profile.paper_type,
        profile.ink_type,
        profile.icc_profile,
        profile.print_settings,
        profile.driver_name,
        profile.driver_version,
        profile.calibration_date,
        profile.calibration_version
      ]
      |> Enum.map(&(&1 || ""))
      |> Enum.join("|")

    "profile-" <> binary_part(Base.encode16(:crypto.hash(:sha256, material), case: :lower), 0, 12)
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(value), do: to_string(value)
end

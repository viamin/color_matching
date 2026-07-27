defmodule ColorMatchingWeb.TestSheetJSON do
  @moduledoc """
  JSON rendering for the test sheet API.

  Produces responses conforming to the `lps-sheet-manifest/v1` schema for
  manifest lookups, and a lightweight list shape for recent-sheets discovery.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: ColorMatchingWeb.Endpoint,
    router: ColorMatchingWeb.Router

  require Logger

  alias ColorMatching.Persistence.TestSheet

  @doc """
  Renders a full sheet manifest.

  Response schema version: `lps-sheet-manifest/v1`
  """
  @spec manifest(map()) :: map()
  def manifest(%{sheet: sheet}) do
    %{
      schema_version: "lps-sheet-manifest/v1",
      sheet_id: sheet.lookup_code,
      sheet_version: sheet.sheet_version,
      manifest_url: manifest_url(sheet),
      created_at: NaiveDateTime.to_iso8601(sheet.inserted_at) <> "Z",
      page_geometry: %{
        width_mm: sheet.page_width_mm,
        height_mm: sheet.page_height_mm,
        units: sheet.page_units
      },
      registration_markers: decode_json_field(sheet.reg_marker_layout),
      patch_layout: decode_json_field(sheet.patch_layout),
      safe_inset_mm: sheet.safe_inset_mm,
      printer_profile: render_printer_profile(sheet.printer_profile),
      capture_profile: nil,
      patches: Enum.map(sheet.pairs, &render_pair/1)
    }
  end

  @doc """
  Renders a list of recent sheets for discovery.
  """
  @spec recent(map()) :: map()
  def recent(%{sheets: sheets}) do
    %{
      sheets: Enum.map(sheets, &render_recent_sheet/1)
    }
  end

  @spec render_recent_sheet(TestSheet.t()) :: map()
  defp render_recent_sheet(sheet) do
    %{
      sheet_id: sheet.lookup_code,
      manifest_url: manifest_url(sheet),
      title: nil
    }
  end

  @spec render_printer_profile(ColorMatching.Persistence.PrinterProfile.t() | nil) :: map() | nil
  defp render_printer_profile(nil), do: nil

  defp render_printer_profile(profile) do
    %{
      printer_make_model: profile.printer_make_model,
      paper_type: profile.paper_type,
      ink_type: profile.ink_type,
      icc_profile: profile.icc_profile,
      print_settings: profile.print_settings,
      driver_name: profile.driver_name,
      driver_version: profile.driver_version,
      calibration_date: render_date(profile.calibration_date),
      calibration_version: profile.calibration_version,
      notes: profile.notes
    }
  end

  @spec render_pair(map()) :: map()
  defp render_pair(pair) do
    %{
      pair_id: pair.pair_id,
      row: pair.row,
      col: pair.col,
      color_a_hex: pair.color_a_hex,
      color_b_hex: pair.color_b_hex
    }
  end

  @spec manifest_url(TestSheet.t()) :: String.t()
  defp manifest_url(sheet) do
    url(~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")
  end

  @spec decode_json_field(String.t() | nil) :: term()
  defp decode_json_field(nil), do: nil

  defp decode_json_field(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, value} -> value
      {:error, reason} ->
        Logger.error("TestSheetJSON: failed to decode JSON field: #{inspect(reason)}")
        nil
    end
  end

  @spec render_date(Date.t() | nil) :: String.t() | nil
  defp render_date(nil), do: nil
  defp render_date(date), do: Date.to_iso8601(date)
end

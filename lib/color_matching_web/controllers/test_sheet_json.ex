defmodule ColorMatchingWeb.TestSheetJSON do
  @moduledoc """
  JSON rendering for the test sheet API.

  Produces responses conforming to the `lps-sheet-manifest/v1` schema for
  manifest lookups, and a lightweight list shape for recent-sheets discovery.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: ColorMatchingWeb.Endpoint,
    router: ColorMatchingWeb.Router

  alias ColorMatching.Persistence.TestSheet
  alias ColorMatching.RankedResults
  alias ColorMatching.SheetGeometry

  @doc """
  Renders a full sheet manifest.

  Response schema version: `lps-sheet-manifest/v1`
  """
  @spec manifest(map()) :: map()
  def manifest(%{sheet: sheet}) do
    geometry = SheetGeometry.build(sheet)

    %{
      schema_version: "lps-sheet-manifest/v1",
      sheet_id: sheet.lookup_code,
      sheet_version: sheet.sheet_version,
      manifest_url: manifest_url(sheet),
      created_at: datetime_to_iso8601(sheet.inserted_at),
      page: %{
        units: geometry.units,
        width: geometry.page_width,
        height: geometry.page_height
      },
      registration_markers: Enum.map(geometry.markers, &render_marker/1),
      printer_profile: render_printer_profile(sheet.printer_profile),
      capture_profile: %{
        expected_illuminant: "low_pressure_sodium",
        preferred_camera: "built_in_wide_angle_rear",
        scoring_algorithm_version: "lps-distance-v1"
      },
      patches: Enum.flat_map(sheet.pairs, &render_patches(&1, geometry)),
      pairs: Enum.map(sheet.pairs, &render_pair_manifest/1)
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

  @doc """
  Renders aggregate ranked results for a test sheet.

  Response schema version: `lps-ranked-results/v1`
  """
  @spec ranked_results(map()) :: map()
  def ranked_results(%{sheet: sheet, results: results}) do
    %{
      schema_version: "lps-ranked-results/v1",
      sheet_id: sheet.lookup_code,
      printer_profile: render_printer_profile(sheet.printer_profile),
      capture_count: results.capture_count,
      latest_capture_at: datetime_to_iso8601(results.latest_capture_at),
      earliest_capture_at: datetime_to_iso8601(results.earliest_capture_at),
      scoring_algorithm_versions: results.algorithm_versions,
      results: Enum.map(results.results, &render_ranked_result/1)
    }
  end

  @spec render_ranked_result(RankedResults.Pair.t()) :: map()
  defp render_ranked_result(pair) do
    %{
      rank: pair.rank,
      pair_id: pair.pair_id,
      scoring_algorithm_version: pair.algorithm_version,
      row: pair.row,
      col: pair.col,
      source_colors: %{
        color_a_hex: pair.color_a_hex,
        color_b_hex: pair.color_b_hex
      },
      score: render_score(pair.score),
      current_judgment: pair.current_judgment,
      current_judgment_observed_at: datetime_to_iso8601(pair.current_judgment_observed_at),
      observation_count: pair.observation_count,
      latest_observation: render_latest_observation(pair.latest_observation),
      capture_count: pair.score.capture_count,
      latest_capture_at: datetime_to_iso8601(pair.latest_capture_at),
      earliest_capture_at: datetime_to_iso8601(pair.earliest_capture_at)
    }
  end

  @spec render_score(RankedResults.Score.t()) :: map()
  defp render_score(score) do
    %{
      average: score.average,
      latest: score.latest,
      minimum: score.minimum,
      maximum: score.maximum,
      capture_count: score.capture_count,
      sample_count: score.sample_count,
      algorithm_versions: score.algorithm_versions
    }
  end

  @spec render_latest_observation(RankedResults.LatestObservation.t() | nil) :: map() | nil
  defp render_latest_observation(nil), do: nil

  defp render_latest_observation(observation) do
    %{
      judgment: observation.judgment,
      observed_at: datetime_to_iso8601(observation.observed_at)
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

  @spec render_printer_profile(ColorMatching.Persistence.PrinterProfile.t()) :: map()
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

  @spec render_marker(SheetGeometry.marker()) :: map()
  defp render_marker(%{role: role, rect: rect}) do
    %{role: role, shape: "solid_square", rect: render_rect(rect)}
  end

  @spec render_patches(ColorMatching.Persistence.TestSheetPair.t(), SheetGeometry.t()) :: [
          map()
        ]
  defp render_patches(pair, geometry) do
    cell = SheetGeometry.cell_rect(geometry, pair.row, pair.col)
    [first, second] = SheetGeometry.patch_rects(cell)

    [
      render_patch(pair, "first", pair.color_a_hex, first, geometry),
      render_patch(pair, "second", pair.color_b_hex, second, geometry)
    ]
  end

  @spec render_patch(
          ColorMatching.Persistence.TestSheetPair.t(),
          String.t(),
          String.t(),
          SheetGeometry.rect(),
          SheetGeometry.t()
        ) :: map()
  defp render_patch(pair, side, source_color, rect, geometry) do
    %{
      id: patch_id(pair.pair_id, side),
      role: "pair_color",
      pair_id: pair.pair_id,
      pair_side: side,
      reference_role: nil,
      source_color: source_color,
      safe_inset_mm: geometry.patch_inset,
      rect: render_rect(rect)
    }
  end

  @spec render_pair_manifest(ColorMatching.Persistence.TestSheetPair.t()) :: map()
  defp render_pair_manifest(pair) do
    %{
      id: pair.pair_id,
      first_patch_id: patch_id(pair.pair_id, "first"),
      second_patch_id: patch_id(pair.pair_id, "second"),
      source_colors: [pair.color_a_hex, pair.color_b_hex],
      grid_row: pair.row,
      grid_col: pair.col
    }
  end

  @spec patch_id(String.t(), String.t()) :: String.t()
  defp patch_id(pair_id, side), do: "#{pair_id}##{side}"

  @spec render_rect(SheetGeometry.rect()) :: map()
  defp render_rect(%{x: x, y: y, width: width, height: height}) do
    %{x: x, y: y, width: width, height: height}
  end

  @spec manifest_url(TestSheet.t()) :: String.t()
  defp manifest_url(sheet) do
    url(~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")
  end

  @spec render_date(Date.t() | nil) :: String.t() | nil
  defp render_date(nil), do: nil
  defp render_date(date), do: Date.to_iso8601(date)

  @spec datetime_to_iso8601(DateTime.t() | NaiveDateTime.t() | nil) :: String.t() | nil
  defp datetime_to_iso8601(nil), do: nil

  defp datetime_to_iso8601(%DateTime{microsecond: {0, _}} = datetime) do
    DateTime.to_iso8601(%{datetime | microsecond: {0, 0}})
  end

  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp datetime_to_iso8601(%NaiveDateTime{} = naive_datetime) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> datetime_to_iso8601()
  end
end

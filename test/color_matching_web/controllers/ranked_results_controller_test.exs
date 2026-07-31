defmodule ColorMatchingWeb.RankedResultsControllerTest do
  # async: false mirrors TestSheetControllerTest: the TestSheetAuthControllerTest
  # mutates the shared `:api_token` env in its setup, and concurrent runs could
  # leak that token into these requests.
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet

  @algorithm_version "ios-score/v1"
  @pair_colors [{"#FF0000", "#00FFFF"}, {"#00FF00", "#FF00FF"}, {"#0000FF", "#FFFF00"}]

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_palette do
    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Ranked Results Palette",
        colors: [%{hex_color: "#FF0000", sort_order: 0}]
      })

    palette
  end

  defp create_printer_profile do
    {:ok, profile} =
      Persistence.create_printer_profile(%{
        printer_make_model: "Epson SureColor P900",
        paper_type: "Ultra Premium Luster",
        ink_type: "OEM UltraChrome PRO10"
      })

    profile
  end

  defp create_sheet(lookup_code, pair_count \\ 2) do
    palette = create_palette()
    profile = create_printer_profile()

    pairs =
      Enum.map(0..(pair_count - 1), fn index ->
        {color_a, color_b} = Enum.at(@pair_colors, index)

        %{
          pair_id: TestSheet.pair_id(lookup_code, 0, index),
          row: 0,
          col: index,
          color_a_hex: color_a,
          color_b_hex: color_b
        }
      end)

    {:ok, _sheet} =
      Persistence.create_test_sheet(%{
        lookup_code: lookup_code,
        palette_id: palette.id,
        printer_profile_id: profile.id,
        sheet_version: "lps-letter-grid-v1",
        pairs: pairs
      })

    Persistence.get_test_sheet_by_lookup_code!(lookup_code)
  end

  defp pair_at(sheet, index), do: Enum.at(sheet.pairs, index)

  defp capture_payload(timestamp) do
    %{
      device_model: "iPhone16,2",
      lens: "wide",
      exposure_duration: 0.008,
      iso: 100,
      focus_lens_position: 0.42,
      white_balance_gains: %{r: 2.1, g: 1.0, b: 1.9},
      image_width: 3024,
      image_height: 4032,
      app_version: "1.2.3",
      timestamp: timestamp,
      detected_marker_count: 4,
      blur_score: 0.03,
      rejection_reasons: ["none"]
    }
  end

  defp create_capture(conn, sheet, timestamp) do
    conn = recycle(conn)

    capture_id =
      conn
      |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload(timestamp))
      |> json_response(201)
      |> Map.fetch!("capture_id")

    {conn, capture_id}
  end

  defp upload_pair_scores(conn, capture_id, score_specs) do
    conn = recycle(conn)

    payload = %{
      pair_scores:
        Enum.map(score_specs, fn {pair_id, score} ->
          %{pair_id: pair_id, algorithm_version: @algorithm_version, score: score}
        end)
    }

    conn
    |> post(~p"/api/v1/captures/#{capture_id}/measurements", payload)
    |> json_response(200)

    conn
  end

  defp upload_judgments(conn, capture_id, judgment_specs) do
    conn = recycle(conn)

    payload = %{
      judgments:
        Enum.map(judgment_specs, fn {pair_id, judgment} ->
          %{pair_id: pair_id, judgment: judgment}
        end)
    }

    conn
    |> post(~p"/api/v1/captures/#{capture_id}/judgments", payload)
    |> json_response(200)

    conn
  end

  defp get_ranked_results(conn, sheet) do
    conn = recycle(conn)

    body =
      conn
      |> get(~p"/api/v1/test_sheets/#{sheet.lookup_code}/ranked_results")
      |> json_response(200)

    body
  end

  describe "GET /api/v1/test_sheets/:sheet_id/ranked_results" do
    test "ranks pairs by score from a single capture", %{conn: conn} do
      sheet = create_sheet("RNKD-2345")

      {conn, capture_id} = create_capture(conn, sheet, "2026-07-28T12:34:56.123456Z")

      conn =
        upload_pair_scores(conn, capture_id, [
          {pair_at(sheet, 0).pair_id, 0.91},
          {pair_at(sheet, 1).pair_id, 0.87}
        ])

      body = get_ranked_results(conn, sheet)

      assert body["schema_version"] == "lps-ranked-results/v1"
      assert body["sheet_id"] == "RNKD-2345"
      assert body["capture_count"] == 1
      assert body["scoring_algorithm_versions"] == [@algorithm_version]
      assert body["printer_profile"]["printer_make_model"] == "Epson SureColor P900"

      [first, second] = body["results"]
      assert first["rank"] == 1
      assert first["pair_id"] == pair_at(sheet, 0).pair_id
      assert_in_delta first["score"]["average"], 0.91, 0.000_001
      assert_in_delta first["score"]["latest"], 0.91, 0.000_001
      assert first["score"]["capture_count"] == 1
      assert first["score"]["sample_count"] == 1
      assert first["score"]["algorithm_versions"] == [@algorithm_version]
      assert first["source_colors"]["color_a_hex"] == "#FF0000"
      assert first["source_colors"]["color_b_hex"] == "#00FFFF"
      assert first["current_judgment"] == nil
      assert first["observation_count"] == 0
      assert first["latest_observation"] == nil

      assert second["rank"] == 2
      assert second["pair_id"] == pair_at(sheet, 1).pair_id
      assert_in_delta second["score"]["average"], 0.87, 0.000_001
    end

    test "aggregates scores across multiple captures", %{conn: conn} do
      sheet = create_sheet("RNKD-2346")

      {conn, first_capture} = create_capture(conn, sheet, "2026-07-28T12:34:56.123456Z")
      {conn, second_capture} = create_capture(conn, sheet, "2026-07-28T12:35:56.123456Z")

      conn =
        upload_pair_scores(conn, first_capture, [
          {pair_at(sheet, 0).pair_id, 0.95},
          {pair_at(sheet, 1).pair_id, 0.87}
        ])

      conn =
        upload_pair_scores(conn, second_capture, [
          {pair_at(sheet, 0).pair_id, 0.85}
        ])

      body = get_ranked_results(conn, sheet)

      assert body["capture_count"] == 2
      assert body["latest_capture_at"] == "2026-07-28T12:35:56.123456Z"
      assert body["earliest_capture_at"] == "2026-07-28T12:34:56.123456Z"

      [first, second] = body["results"]

      assert first["pair_id"] == pair_at(sheet, 0).pair_id
      assert_in_delta first["score"]["average"], 0.9, 0.000_001
      assert_in_delta first["score"]["latest"], 0.85, 0.000_001
      assert_in_delta first["score"]["minimum"], 0.85, 0.000_001
      assert_in_delta first["score"]["maximum"], 0.95, 0.000_001
      assert first["score"]["capture_count"] == 2
      assert first["score"]["sample_count"] == 2
      assert first["latest_capture_at"] == "2026-07-28T12:35:56.123456Z"
      assert first["earliest_capture_at"] == "2026-07-28T12:34:56.123456Z"

      assert second["pair_id"] == pair_at(sheet, 1).pair_id
      assert_in_delta second["score"]["average"], 0.87, 0.000_001
      assert_in_delta second["score"]["latest"], 0.87, 0.000_001
      assert second["score"]["capture_count"] == 1
    end

    test "breaks ties deterministically using a stable key", %{conn: conn} do
      sheet = create_sheet("RNKD-2347")

      {conn, capture_id} = create_capture(conn, sheet, "2026-07-28T12:34:56.123456Z")

      conn =
        upload_pair_scores(conn, capture_id, [
          {pair_at(sheet, 0).pair_id, 0.8},
          {pair_at(sheet, 1).pair_id, 0.8}
        ])

      body = get_ranked_results(conn, sheet)

      ordered_pair_ids = Enum.map(body["results"], & &1["pair_id"])
      expected_order = Enum.sort([pair_at(sheet, 0).pair_id, pair_at(sheet, 1).pair_id])

      assert ordered_pair_ids == expected_order
      assert Enum.map(body["results"], & &1["rank"]) == [1, 2]
    end

    test "includes current finding and observation history", %{conn: conn} do
      sheet = create_sheet("RNKD-2348", 1)

      {conn, first_capture} = create_capture(conn, sheet, "2026-07-28T12:34:56.123456Z")
      {conn, second_capture} = create_capture(conn, sheet, "2026-07-28T12:35:56.123456Z")

      pair = pair_at(sheet, 0)

      conn = upload_pair_scores(conn, first_capture, [{pair.pair_id, 0.9}])
      conn = upload_judgments(conn, first_capture, [{pair.pair_id, "near_match"}])
      conn = upload_pair_scores(conn, second_capture, [{pair.pair_id, 0.95}])
      conn = upload_judgments(conn, second_capture, [{pair.pair_id, "match"}])

      body = get_ranked_results(conn, sheet)

      [result] = body["results"]

      assert result["current_judgment"] == "match"
      assert result["current_judgment_observed_at"] == "2026-07-28T12:35:56.123456Z"
      assert result["observation_count"] == 2
      assert result["latest_observation"]["judgment"] == "match"
      assert result["latest_observation"]["observed_at"] == "2026-07-28T12:35:56.123456Z"
    end

    test "distinguishes unmeasured, unjudged, and no_match pairs", %{conn: conn} do
      sheet = create_sheet("RNKD-2349", 3)

      {conn, capture_id} = create_capture(conn, sheet, "2026-07-28T12:34:56.123456Z")

      measured_pair = pair_at(sheet, 0)
      scored_unjudged_pair = pair_at(sheet, 1)
      no_match_pair = pair_at(sheet, 2)

      conn =
        upload_pair_scores(conn, capture_id, [
          {scored_unjudged_pair.pair_id, 0.8},
          {no_match_pair.pair_id, 0.9}
        ])

      conn = upload_judgments(conn, capture_id, [{no_match_pair.pair_id, "no_match"}])

      body = get_ranked_results(conn, sheet)

      by_pair = Map.new(body["results"], &{&1["pair_id"], &1})

      no_match_result = by_pair[no_match_pair.pair_id]
      assert no_match_result["current_judgment"] == "no_match"
      assert no_match_result["observation_count"] == 1
      assert no_match_result["rank"] == 1

      scored_unjudged = by_pair[scored_unjudged_pair.pair_id]
      assert scored_unjudged["current_judgment"] == nil
      assert scored_unjudged["observation_count"] == 0
      assert_in_delta scored_unjudged["score"]["average"], 0.8, 0.000_001
      assert scored_unjudged["rank"] == 2

      measured = by_pair[measured_pair.pair_id]
      assert measured["current_judgment"] == nil
      assert measured["score"]["average"] == nil
      assert measured["score"]["latest"] == nil
      assert measured["score"]["capture_count"] == 0
      assert measured["score"]["sample_count"] == 0
      assert measured["rank"] == 3
    end

    test "returns ranked pairs even when no captures exist", %{conn: conn} do
      sheet = create_sheet("RNKD-2356", 2)

      body = get_ranked_results(conn, sheet)

      assert body["capture_count"] == 0
      assert body["latest_capture_at"] == nil
      assert body["earliest_capture_at"] == nil
      assert length(body["results"]) == 2

      assert Enum.all?(body["results"], fn result ->
               result["score"]["average"] == nil and result["score"]["capture_count"] == 0
             end)

      ordered_pair_ids = Enum.map(body["results"], & &1["pair_id"])
      assert ordered_pair_ids == Enum.sort(ordered_pair_ids)
    end

    test "returns structured 404 JSON for an unknown sheet", %{conn: conn} do
      conn = recycle(conn)

      body =
        conn
        |> get(~p"/api/v1/test_sheets/UNKN-2345/ranked_results")
        |> json_response(404)

      assert body == %{"errors" => %{"detail" => "Sheet not found"}}
    end
  end
end

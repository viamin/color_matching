defmodule ColorMatchingWeb.OpenApiControllerTest do
  use ColorMatchingWeb.ConnCase, async: true

  test "serves the complete OpenAPI 3 contract", %{conn: conn} do
    spec =
      conn
      |> get(~p"/api/v1/openapi.json")
      |> json_response(200)

    assert spec["openapi"] =~ "3."

    paths = MapSet.new(Map.keys(spec["paths"]))

    assert paths ==
             MapSet.new([
               "/api/v1/printer_profiles",
               "/api/v1/printer_profiles/{printer_profile_id}/colors",
               "/api/v1/printer_profiles/{printer_profile_id}/metamer_pairs",
               "/api/v1/palettes",
               "/api/v1/colors",
               "/api/v1/test_sheets/recent",
               "/api/v1/test_sheets/{sheet_id}/manifest",
               "/api/v1/test_sheets/{sheet_id}/ranked_results",
               "/api/v1/test_sheets/{sheet_id}/captures",
               "/api/v1/captures/{capture_id}/measurements",
               "/api/v1/captures/{capture_id}/judgments",
               "/api/illuminant_measurements",
               "/api/illuminant_measurements/bulk",
               "/api/multi_image_mapping"
             ])
  end
end

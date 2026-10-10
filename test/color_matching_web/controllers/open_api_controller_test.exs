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

  test "documents palette lookup errors and the required printer profile query", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    assert_error_responses(spec, "/api/v1/colors")
    assert Map.has_key?(spec["paths"]["/api/v1/colors"]["get"]["responses"], "422")

    for path <- [
          "/api/v1/printer_profiles/{printer_profile_id}/colors",
          "/api/v1/printer_profiles/{printer_profile_id}/metamer_pairs"
        ] do
      assert_error_responses(spec, path)
    end

    printer_profile_id =
      spec["paths"]["/api/v1/colors"]["get"]["parameters"]
      |> Enum.find(&(&1["name"] == "printer_profile_id"))

    assert printer_profile_id["required"]
    assert printer_profile_id["schema"] == %{"minimum" => 1, "type" => "integer"}
  end

  test "uses concrete palette response schemas", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    printer_profiles_response =
      spec["paths"]["/api/v1/printer_profiles"]["get"]["responses"]["200"]
      |> get_in(["content", "application/json", "schema", "$ref"])

    assert printer_profiles_response == "#/components/schemas/PrinterProfilesResponse"

    assert spec["components"]["schemas"]["PrinterProfilesResponse"]["required"] == [
             "printer_profiles"
           ]

    assert Enum.sort(spec["components"]["schemas"]["PrinterProfile"]["required"]) == [
             "id",
             "ink_type",
             "paper_type",
             "printer_make_model"
           ]
  end

  test "documents both controller and request-validation error shapes", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)

    error_schema = spec["components"]["schemas"]["ApiErrorResponse"]
    error_shapes = error_schema["properties"]["errors"]["oneOf"]

    assert Enum.any?(error_shapes, &(&1["type"] == "object"))

    assert Enum.any?(error_shapes, fn shape ->
             shape["type"] == "array" and
               get_in(shape, ["items", "required"]) == ["detail", "source"]
           end)
  end

  test "documents compatible pair-score fields and shared bulk metadata", %{conn: conn} do
    spec = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)
    schemas = spec["components"]["schemas"]

    assert length(schemas["CaptureRequest"]["anyOf"]) == 2
    assert Enum.sort(schemas["PairScoreRequest"]["required"]) == ["algorithm_version", "pair_id"]
    assert length(schemas["PairScoreRequest"]["anyOf"]) == 3

    assert length(schemas["RgbPayload"]["anyOf"]) == 3

    bulk_request =
      spec["paths"]["/api/illuminant_measurements/bulk"]["post"]
      |> get_in(["requestBody", "content", "application/json", "schema", "$ref"])

    assert bulk_request == "#/components/schemas/BulkIlluminantMeasurementRequest"

    assert Enum.sort(schemas["BulkIlluminantMeasurementRequest"]["required"]) == [
             "light_source",
             "measurements",
             "printer_profile_id"
           ]

    assert get_in(schemas, [
             "BulkIlluminantMeasurementRequest",
             "properties",
             "measurements",
             "items",
             "$ref"
           ]) == "#/components/schemas/BulkIlluminantMeasurementRow"
  end

  defp assert_error_responses(spec, path) do
    responses = spec["paths"][path]["get"]["responses"]

    assert Map.has_key?(responses, "400")
    assert Map.has_key?(responses, "401")
    assert Map.has_key?(responses, "404")
  end
end

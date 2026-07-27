defmodule ColorMatchingWeb.TestSheetControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_palette do
    {:ok, palette} =
      Persistence.create_palette(%{
        name: "API Test Palette",
        colors: [
          %{hex_color: "#FF0000", sort_order: 0},
          %{hex_color: "#00FF00", sort_order: 1}
        ]
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

  defp create_sheet(lookup_code \\ "ABCD-2345") do
    palette = create_palette()
    profile = create_printer_profile()

    {:ok, sheet} =
      Persistence.create_test_sheet(%{
        lookup_code: lookup_code,
        palette_id: palette.id,
        printer_profile_id: profile.id,
        sheet_version: "lps-letter-grid-v1",
        page_width_mm: 215.9,
        page_height_mm: 279.4,
        page_units: "mm",
        reg_marker_layout: Jason.encode!(%{type: "corner_circles", radius_mm: 5.0}),
        patch_layout: Jason.encode!(%{grid_size: 2, cell_size_mm: 20.0}),
        safe_inset_mm: 12.7,
        pairs: [
          %{
            pair_id: TestSheet.pair_id(lookup_code, 0, 0),
            row: 0,
            col: 0,
            color_a_hex: "#FF0000",
            color_b_hex: "#00FFFF"
          },
          %{
            pair_id: TestSheet.pair_id(lookup_code, 0, 1),
            row: 0,
            col: 1,
            color_a_hex: "#00FF00",
            color_b_hex: "#FF00FF"
          }
        ]
      })

    sheet
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/test_sheets/:sheet_id/manifest
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/test_sheets/:sheet_id/manifest" do
    test "returns manifest for a known sheet", %{conn: conn} do
      sheet = create_sheet("ABCD-2345")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      assert json_response(conn, 200)
    end

    test "manifest includes schema_version lps-sheet-manifest/v1", %{conn: conn} do
      sheet = create_sheet("ABCD-2346")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      assert body["schema_version"] == "lps-sheet-manifest/v1"
    end

    test "manifest includes required fields", %{conn: conn} do
      sheet = create_sheet("ABCD-2347")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)

      assert body["sheet_id"] == "ABCD-2347"
      assert body["sheet_version"] == "lps-letter-grid-v1"
      assert is_binary(body["manifest_url"])
      assert is_binary(body["created_at"])
      assert body["page_geometry"]["width_mm"] == 215.9
      assert body["page_geometry"]["height_mm"] == 279.4
      assert body["page_geometry"]["units"] == "mm"
      assert body["safe_inset_mm"] == 12.7
    end

    test "manifest includes decoded registration_markers", %{conn: conn} do
      sheet = create_sheet("ABCD-2348")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      assert body["registration_markers"]["type"] == "corner_circles"
      assert body["registration_markers"]["radius_mm"] == 5.0
    end

    test "manifest includes printer_profile", %{conn: conn} do
      sheet = create_sheet("ABCD-2349")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      assert body["printer_profile"]["printer_make_model"] == "Epson SureColor P900"
      assert body["printer_profile"]["paper_type"] == "Ultra Premium Luster"
      assert body["printer_profile"]["ink_type"] == "OEM UltraChrome PRO10"
    end

    test "manifest includes patches with pair_id, row, col, and colors", %{conn: conn} do
      sheet = create_sheet("ABCD-2350")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      patches = body["patches"]
      assert length(patches) == 2

      first_patch = List.first(patches)
      assert is_binary(first_patch["pair_id"])
      assert String.starts_with?(first_patch["pair_id"], "pair-")
      assert is_integer(first_patch["row"])
      assert is_integer(first_patch["col"])
      assert is_binary(first_patch["color_a_hex"])
      assert is_binary(first_patch["color_b_hex"])
    end

    test "manifest_url points to the manifest endpoint", %{conn: conn} do
      sheet = create_sheet("ABCD-2351")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      assert String.contains?(body["manifest_url"], "/api/v1/test_sheets/#{sheet.lookup_code}/manifest")
    end

    test "returns structured 404 JSON for unknown sheet_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/UNKN-2345/manifest")

      body = json_response(conn, 404)
      assert body["errors"]["detail"] == "Sheet not found"
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/test_sheets/recent
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/test_sheets/recent" do
    test "returns an empty sheets list when no sheets exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 200)
      assert body["sheets"] == []
    end

    test "returns sheets list with correct shape", %{conn: conn} do
      sheet = create_sheet("RCNT-2345")

      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 200)
      assert is_list(body["sheets"])
      entry = Enum.find(body["sheets"], &(&1["sheet_id"] == sheet.lookup_code))
      assert entry != nil
      assert is_binary(entry["manifest_url"])
      assert Map.has_key?(entry, "title")
    end

    test "title is nil for sheets without a title", %{conn: conn} do
      _sheet = create_sheet("RCNT-2346")

      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 200)
      entry = List.first(body["sheets"])
      assert is_nil(entry["title"])
    end

    test "recent sheets include manifest_url pointing to manifest endpoint", %{conn: conn} do
      sheet = create_sheet("RCNT-2347")

      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 200)
      entry = Enum.find(body["sheets"], &(&1["sheet_id"] == sheet.lookup_code))
      assert String.contains?(entry["manifest_url"], "/api/v1/test_sheets/#{sheet.lookup_code}/manifest")
    end
  end

  # ---------------------------------------------------------------------------
  # Auth behavior
  # ---------------------------------------------------------------------------

  describe "authentication" do
    setup do
      Application.put_env(:color_matching, :api_token, "test-secret-token")
      on_exit(fn -> Application.delete_env(:color_matching, :api_token) end)
      :ok
    end

    test "returns 401 when token is configured but no Authorization header provided", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end

    test "returns 401 when wrong token is provided", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> get(~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end

    test "returns 200 when correct token is provided", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> get(~p"/api/v1/test_sheets/recent")

      assert json_response(conn, 200)
    end

    test "returns 401 when manifest is accessed without token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/UNKN-2345/manifest")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end
  end
end

defmodule ColorMatchingWeb.TestSheetControllerTest do
  # async: false is required because the TestSheetAuthControllerTest mutates
  # `Application.get_env(:color_matching, :api_token)` in its setup, and the
  # api_auth plug reads that env on every request. Running the two test
  # modules concurrently would let the auth token from a sibling test leak
  # into these requests, producing spurious 401s.
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

  defp create_sheet(lookup_code) do
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
      assert body["page"]["width"] == 215.9
      assert body["page"]["height"] == 279.4
      assert body["page"]["units"] == "mm"
      assert is_list(body["registration_markers"])
      assert is_list(body["patches"])
      assert is_list(body["pairs"])
    end

    test "manifest includes decoded registration_markers", %{conn: conn} do
      sheet = create_sheet("ABCD-2348")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")
      body = json_response(conn, 200)
      markers = body["registration_markers"]
      assert length(markers) == 4

      assert Enum.map(markers, & &1["role"]) ==
               ["top_left", "top_right", "bottom_right", "bottom_left"]

      marker = List.first(markers)
      assert marker["shape"] == "solid_square"
      assert is_map(marker["rect"])
      assert marker["rect"]["width"] > 0
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
      sheet = create_sheet("ABCD-2355")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)
      patches = body["patches"]
      pairs = body["pairs"]
      # Each pair cell yields two patches (first/second color sides).
      assert length(patches) == length(pairs) * 2

      [first_patch, second_patch | _rest] = patches
      pair = List.first(pairs)

      assert first_patch["id"] == "#{pair["id"]}#first"
      assert second_patch["id"] == "#{pair["id"]}#second"
      assert first_patch["role"] == "pair_color"
      assert first_patch["pair_id"] == pair["id"]
      assert first_patch["pair_side"] == "first"
      assert second_patch["pair_side"] == "second"
      assert is_binary(first_patch["source_color"])
      assert is_number(first_patch["safe_inset_mm"])
      assert is_map(first_patch["rect"])
      assert first_patch["rect"]["width"] > 0

      assert pair["first_patch_id"] == first_patch["id"]
      assert pair["second_patch_id"] == second_patch["id"]
      assert length(pair["source_colors"]) == 2
    end

    test "manifest_url points to the manifest endpoint", %{conn: conn} do
      sheet = create_sheet("ABCD-2356")

      conn = get(conn, ~p"/api/v1/test_sheets/#{sheet.lookup_code}/manifest")

      body = json_response(conn, 200)

      assert String.contains?(
               body["manifest_url"],
               "/api/v1/test_sheets/#{sheet.lookup_code}/manifest"
             )
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

      assert String.contains?(
               entry["manifest_url"],
               "/api/v1/test_sheets/#{sheet.lookup_code}/manifest"
             )
    end
  end
end

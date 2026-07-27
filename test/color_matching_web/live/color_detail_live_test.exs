defmodule ColorMatchingWeb.ColorDetailLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  alias ColorMatching.Persistence

  describe "ColorDetailLive" do
    test "renders the persisted color with all five light sources marked missing", %{conn: conn} do
      %{palette: palette, color: color, printer_profile: printer_profile} =
        persisted_color_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      assert html =~ "Color Detail"
      assert html =~ color.hex_color
      assert html =~ "Back to palettes"
      assert html =~ "Illuminant Response Profile"

      # Every supported light source should be present and explicitly marked
      # as missing because the fixture has not recorded any measurements.
      for label <- ["White", "Red", "Green", "Blue", "LPS"] do
        assert html =~ label
      end

      # The DOM order of the light sources must stay stable across renders so
      # users (and LiveView's diff) can rely on a predictable layout.
      assert order_of_labels(html) == ["White", "Red", "Green", "Blue", "LPS"]

      assert html =~ "Missing"

      # Printer profile context is shown alongside the response profile.
      assert html =~ printer_profile.printer_make_model
      assert html =~ printer_profile.paper_type
      assert html =~ printer_profile.ink_type
    end

    test "shows the latest measured brightness and metadata per light source", %{conn: conn} do
      %{palette: palette, color: color, printer_profile: printer_profile} =
        persisted_color_fixture()

      assert {:ok, _older_red} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: 0.10,
                 measured_at: ~U[2026-07-27 09:00:00Z]
               })

      assert {:ok, _latest_red} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: 0.42,
                 measured_at: ~U[2026-07-27 12:00:00Z],
                 measurement_method: "spot meter",
                 measurement_device: "Sekonic C-800",
                 test_run_id: "run-2026-07-27-a",
                 notes: "Center patch"
               })

      assert {:ok, _white_measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.0,
                 measured_at: ~U[2026-07-27 13:00:00Z],
                 notes: "True black after printing"
               })

      {:ok, _view, html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      # Latest red measurement (0.42) is displayed, not the older 0.10.
      assert html =~ "0.420"
      refute html =~ "0.100"

      assert html =~ "spot meter"
      assert html =~ "Sekonic C-800"
      assert html =~ "run-2026-07-27-a"
      assert html =~ "Center patch"

      # Zero brightness should be rendered (not collapsed into "Missing").
      assert html =~ "0.000"
      assert html =~ "True black after printing"
    end

    test "distinguishes missing light sources from a brightness of 0.0", %{conn: conn} do
      %{palette: palette, color: color, printer_profile: printer_profile} =
        persisted_color_fixture()

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.0
               })

      {:ok, _view, html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      # White is present as 0.000 (not missing)...
      assert html =~ "0.000"
      # ...but the other four sources should still be marked Missing.
      missing_count = html |> String.split("Missing", trim: true) |> length()
      assert missing_count >= 4
    end

    test "submits an individual measurement via the form", %{conn: conn} do
      %{palette: palette, color: color, printer_profile: printer_profile} =
        persisted_color_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      html =
        render_submit(view, "submit_measurement", %{
          "light_source" => "green",
          "brightness" => "0.63"
        })

      assert html =~ "Recorded"
      assert html =~ "Green"

      [persisted] = Persistence.list_illuminant_measurements(color.id, printer_profile.id)
      assert persisted.light_source == "green"
      assert persisted.normalized_brightness == 0.63
      assert persisted.palette_color_id == color.id
      assert persisted.printer_profile_id == printer_profile.id
    end

    test "light source dropdown syncs back into the form via phx-change", %{conn: conn} do
      %{palette: palette, color: color} = persisted_color_fixture()

      {:ok, view, html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      # The dropdown ships with the default "white" option marked as selected.
      assert html =~ ~r/<option value="white"[^>]*selected/

      # Changing the dropdown to "green" must update the assigns so the
      # `selected` attribute stays in sync with the user's choice instead of
      # snapping back to "white" on the next re-render.
      html =
        render_change(view, "update_measurement_light_source", %{
          "light_source" => "green"
        })

      assert html =~ ~r/<option value="green"[^>]*selected/

      # The selection is also captured alongside a brightness update so it
      # survives the re-render triggered by typing a reading.
      html =
        render_change(view, "update_measurement_brightness", %{
          "brightness" => "0.42"
        })

      assert html =~ ~r/<option value="green"[^>]*selected/
    end

    test "shows validation errors for out-of-range brightness input", %{conn: conn} do
      %{palette: palette, color: color} = persisted_color_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      html =
        render_submit(view, "submit_measurement", %{
          "light_source" => "blue",
          "brightness" => "1.5"
        })

      assert html =~ "must be less than or equal to 1.0"
      refute html =~ "Recorded"
    end

    test "surfaces errors when the printer profile was removed while the page was open",
         %{conn: conn} do
      %{palette: palette, color: color, printer_profile: printer_profile} =
        persisted_color_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      # Bypass the persistence layer so the in-memory LiveView still references
      # the printer profile that no longer exists in the database.
      {:ok, _} = ColorMatching.Repo.delete(printer_profile)

      html =
        render_submit(view, "submit_measurement", %{
          "light_source" => "blue",
          "brightness" => "0.42"
        })

      assert html =~ "does not exist"
      refute html =~ "Recorded"
    end

    test "switching printer profile rebuilds the response vector from the new profile",
         %{conn: conn} do
      %{palette: palette, color: color, printer_profile: first_profile} =
        persisted_color_fixture()

      assert {:ok, second_profile} =
               Persistence.create_printer_profile(%{
                 printer_make_model: "HP DesignJet Z9",
                 paper_type: "Premium Matte",
                 ink_type: "OEM Lucia Pro"
               })

      assert {:ok, _measurement} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: first_profile.id,
                 light_source: "white",
                 normalized_brightness: 0.5
               })

      {:ok, view, html} =
        live(conn, ~p"/palettes/#{palette.id}/colors/#{color.id}")

      # The fixture's Epson profile sorts alphabetically before HP, so it is
      # selected by default and renders the recorded value.
      assert html =~ "0.500"

      # Switching to the HP profile re-renders with no measurements for it,
      # so every light source flips back to Missing.
      html =
        render_change(view, "select_printer_profile", %{
          "printer_profile_id" => second_profile.id
        })

      assert html =~ second_profile.printer_make_model

      # After switching profiles, white is no longer 0.500 because the
      # measurement is scoped to the original printer profile.
      refute html =~ "0.500"
      assert html =~ "Missing"
    end

    test "renders a not-found notice when the color is unknown", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/palettes/999999/colors/999999")

      assert html =~ "Color not found"
      refute html =~ "Illuminant Response Profile"
    end
  end

  defp persisted_color_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Color Detail Fixture",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    color = Persistence.get_palette!(palette.id).colors |> List.first()

    %{palette: palette, color: color, printer_profile: printer_profile}
  end

  defp order_of_labels(html) do
    heading_pattern = ~r{<h3[^>]*>([^<]+)</h3>}

    html
    |> scan_heading_labels(heading_pattern)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in ["White", "Red", "Green", "Blue", "LPS"]))
  end

  defp scan_heading_labels(html, pattern) do
    Regex.scan(pattern, html, capture: :all_but_first)
    |> List.flatten()
  end
end

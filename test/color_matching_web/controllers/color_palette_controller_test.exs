defmodule ColorMatchingWeb.ColorPaletteControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "GET /api/v1/printer_profiles" do
    test "lists printer profiles ordered by make/model", %{conn: conn} do
      {:ok, _zed} = profile_fixture("ZedJet", "Matte", "Dye")
      {:ok, alpha} = profile_fixture("AlphaPrint", "Glossy", "Pigment")

      body =
        conn
        |> get(~p"/api/v1/printer_profiles")
        |> json_response(200)

      names = Enum.map(body["printer_profiles"], & &1["printer_make_model"])
      assert names == ["AlphaPrint", "ZedJet"]

      alpha_entry = Enum.find(body["printer_profiles"], &(&1["id"] == alpha.id))
      assert alpha_entry["paper_type"] == "Glossy"
      assert alpha_entry["ink_type"] == "Pigment"
    end

    test "returns an empty list when there are no profiles", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/printer_profiles")
        |> json_response(200)

      assert body == %{"printer_profiles" => []}
    end
  end

  describe "GET /api/v1/palettes" do
    test "lists palettes with their color counts", %{conn: conn} do
      {:ok, _palette} =
        Persistence.create_palette(%{
          name: "Swatch Set",
          colors: [
            %{hex_color: "#111111", sort_order: 0, display_label: "Dark"},
            %{hex_color: "#eeeeee", sort_order: 1}
          ]
        })

      body =
        conn
        |> get(~p"/api/v1/palettes")
        |> json_response(200)

      [palette] = body["palettes"]
      assert palette["name"] == "Swatch Set"
      assert palette["color_count"] == 2
      assert palette["is_preset"] == false
    end
  end

  describe "GET /api/v1/colors" do
    test "requires printer_profile_id", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns 404 for an unknown printer profile", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: 999_999]}")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "printer profile"
    end

    test "returns 400 for a non-integer printer_profile_id", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: "abc"]}")
        |> json_response(400)

      assert body["errors"]["detail"] =~ "printer_profile_id"
    end

    test "returns colors with response vectors for a palette and profile", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      assert body["printer_profile"]["id"] == profile.id
      ids = Enum.map(body["colors"], & &1["id"])
      assert ids == Enum.sort(ids)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      assert dark_color["hex"] == "#111111"
      assert dark_color["rgb"] == %{"r" => 17, "g" => 17, "b" => 17}
      assert dark_color["palette_id"] == palette.id
      assert dark_color["palette_name"] == palette.name
      assert dark_color["sort_order"] == 0
      assert dark_color["name"] == "Dark"

      assert dark_color["responses"]["white"]["brightness"] == 0.1
      assert dark_color["responses"]["white"]["source"] == "measurement"
      assert dark_color["responses"]["red"]["brightness"] == 0.9
    end

    test "omits light sources that have no measurement (missing is not zero)", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      # Only white and red were measured; green/blue/lps must be absent entirely.
      assert MapSet.new(Map.keys(dark_color["responses"])) == MapSet.new(["white", "red"])
    end

    test "returns all colors across palettes when palette_id is omitted", %{conn: conn} do
      %{palette: palette_a, printer_profile: profile} = response_fixture()

      {:ok, _palette_b} =
        Persistence.create_palette(%{
          name: "Other Palette",
          colors: [%{hex_color: "#ff8800", sort_order: 0}]
        })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id]}")
        |> json_response(200)

      assert length(body["colors"]) == length(palette_a.colors) + 1
    end

    test "human-entered response wins over instrument measurement for a light source", %{
      conn: conn
    } do
      %{palette: palette, printer_profile: profile, dark: dark} = response_fixture()

      # Add a human response for white that disagrees with the instrument value.
      assert {:ok, _} =
               Persistence.set_illuminant_response(%{
                 palette_color_id: dark.id,
                 printer_profile_id: profile.id,
                 illuminant: "white",
                 apparent_brightness: 5
               })

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      # 5/10 = 0.5 (response), not the instrument's 0.1.
      assert dark_color["responses"]["white"]["brightness"] == 0.5
      assert dark_color["responses"]["white"]["source"] == "response"
      assert dark_color["responses"]["white"]["apparent_brightness"] == 5
    end

    test "exposes raw instrument values", %{conn: conn} do
      %{palette: palette, printer_profile: profile, dark: dark} =
        raw_measurement_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: palette.id]}")
        |> json_response(200)

      dark_color = Enum.find(body["colors"], &(&1["id"] == dark.id))

      assert dark_color["responses"]["green"]["raw_value"] == 42.5
      assert dark_color["responses"]["green"]["raw_unit"] == "nits"
      assert dark_color["responses"]["green"]["source"] == "measurement"
    end

    test "returns 404 for an unknown palette", %{conn: conn} do
      %{printer_profile: profile} = response_fixture()

      body =
        conn
        |> get(~p"/api/v1/colors?#{[printer_profile_id: profile.id, palette_id: 999_999]}")
        |> json_response(404)

      assert body["errors"]["detail"] =~ "palette"
    end
  end

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp profile_fixture(make, paper, ink) do
    Persistence.create_printer_profile(%{
      printer_make_model: make,
      paper_type: paper,
      ink_type: ink
    })
  end

  defp response_fixture do
    {:ok, profile} = profile_fixture("Response Fixture Printer", "Matte", "Pigment")

    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Response Fixture",
        colors: [
          %{hex_color: "#111111", sort_order: 0, display_label: "Dark"},
          %{hex_color: "#eeeeee", sort_order: 1, display_label: "Light"}
        ]
      })

    palette = Persistence.get_palette!(palette.id)
    [dark, light] = palette.colors

    Enum.each(palette.colors, fn color ->
      Persistence.create_illuminant_measurement(%{
        palette_color_id: color.id,
        printer_profile_id: profile.id,
        light_source: "white",
        normalized_brightness: if(color.hex_color == "#111111", do: 0.1, else: 0.9)
      })

      Persistence.create_illuminant_measurement(%{
        palette_color_id: color.id,
        printer_profile_id: profile.id,
        light_source: "red",
        normalized_brightness: if(color.hex_color == "#111111", do: 0.9, else: 0.1)
      })
    end)

    %{palette: palette, printer_profile: profile, dark: dark, light: light}
  end

  defp raw_measurement_fixture do
    {:ok, profile} = profile_fixture("Raw Fixture Printer", "Matte", "Pigment")

    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Raw Fixture",
        colors: [%{hex_color: "#111111", sort_order: 0, display_label: "Dark"}]
      })

    palette = Persistence.get_palette!(palette.id)
    [dark] = palette.colors

    assert {:ok, _} =
             Persistence.create_illuminant_measurement(%{
               palette_color_id: dark.id,
               printer_profile_id: profile.id,
               light_source: "green",
               normalized_brightness: 0.3,
               raw_measured_value: 42.5,
               raw_value_unit: "nits"
             })

    %{palette: palette, printer_profile: profile, dark: dark}
  end
end

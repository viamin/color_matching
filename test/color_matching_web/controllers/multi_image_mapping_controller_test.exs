defmodule ColorMatchingWeb.MultiImageMappingControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.{Persistence, PNG}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "POST /api/multi_image_mapping" do
    test "returns a mapped PNG on success", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      # 2×1 image: left pixel nearly-dark, right pixel nearly-bright
      white_png = grayscale_png!(2, 1, [10, 245])
      red_png = grayscale_png!(2, 1, [245, 10])

      response =
        conn
        |> put_req_header("accept", "image/png")
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0, red: 1.0},
          images: %{
            white: Base.encode64(white_png),
            red: Base.encode64(red_png)
          }
        })

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]

      assert {:ok, %{width: 2, height: 1, pixels: [_left, _right]}} =
               PNG.decode_rgb(response.resp_body)
    end

    test "returns 422 for invalid (non-numeric) weights", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: "not_a_number"},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "finite number"
    end

    test "returns 422 when all weights are zero", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 0.0, red: 0.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "at least one light source weight must be greater than 0"
    end

    test "returns 422 when no colors have eligible measurements", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      # Palette has colors but no measurements — all will be excluded by the scorer
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "no eligible palette color"
    end

    test "returns 422 for mismatched source image dimensions", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      white_png = grayscale_png!(2, 1, [10, 245])
      red_png = grayscale_png!(1, 2, [128, 64])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0, red: 1.0},
          images: %{
            white: Base.encode64(white_png),
            red: Base.encode64(red_png)
          }
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "same dimensions"
    end

    test "returns 404 when palette does not exist", %{conn: conn} do
      %{printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: 999_999,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(404)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "palette not found"
    end

    test "returns 404 when printer profile does not exist", %{conn: conn} do
      %{palette: palette} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: 999_999,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(404)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "printer profile not found"
    end

    test "returns 422 when palette_id is missing", %{conn: conn} do
      %{printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["palette_id is required"]}} = response
    end

    test "returns 422 when printer_profile_id is missing", %{conn: conn} do
      %{palette: palette} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["printer_profile_id is required"]}} = response
    end

    test "returns 422 when weights are missing", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["weights is required"]}} = response
    end

    test "returns 422 when images are missing", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["images is required"]}} = response
    end

    test "returns 422 when images contain invalid base64", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: "not-valid-base64!!!"}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "not valid base64"
    end

    test "returns 422 for unsupported light source in weights", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{ultraviolet: 1.0},
          images: %{ultraviolet: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "unsupported light source"
    end
  end

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp palette_and_profile_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "Mapping Test Swatches",
               colors: [
                 %{hex_color: "#111111", sort_order: 0, display_label: "Dark"},
                 %{hex_color: "#eeeeee", sort_order: 1, display_label: "Light"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Test Printer",
               paper_type: "Matte",
               ink_type: "Pigment"
             })

    %{palette: Persistence.get_palette!(palette.id), printer_profile: printer_profile}
  end

  defp full_mapping_fixture do
    %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

    for color <- palette.colors do
      assert {:ok, _} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "white",
                 normalized_brightness: if(color.hex_color == "#111111", do: 0.1, else: 0.9)
               })

      assert {:ok, _} =
               Persistence.create_illuminant_measurement(%{
                 palette_color_id: color.id,
                 printer_profile_id: printer_profile.id,
                 light_source: "red",
                 normalized_brightness: if(color.hex_color == "#111111", do: 0.9, else: 0.1)
               })
    end

    %{palette: palette, printer_profile: printer_profile}
  end

  defp grayscale_png!(width, height, pixels) do
    {:ok, png} = PNG.encode_grayscale(width, height, pixels)
    png
  end
end

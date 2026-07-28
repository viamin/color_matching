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

    test "accepts string ids in the request body", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      white_png = grayscale_png!(1, 1, [10])
      red_png = grayscale_png!(1, 1, [245])

      response =
        conn
        |> put_req_header("accept", "image/png")
        |> post(~p"/api/multi_image_mapping", %{
          "palette_id" => Integer.to_string(palette.id),
          "printer_profile_id" => Integer.to_string(printer_profile.id),
          "weights" => %{"white" => 1.0, "red" => 1.0},
          "images" => %{
            "white" => Base.encode64(white_png),
            "red" => Base.encode64(red_png)
          }
        })

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]
    end

    test "accepts unpadded base64 image payloads", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      white_png = grayscale_png!(1, 1, [10])
      red_png = grayscale_png!(1, 1, [245])

      response =
        conn
        |> put_req_header("accept", "image/png")
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0, red: 1.0},
          images: %{
            white: Base.encode64(white_png, padding: false),
            red: Base.encode64(red_png, padding: false)
          }
        })

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]
    end

    test "accepts image light-source keys with surrounding whitespace and mixed case", %{
      conn: conn
    } do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      white_png = grayscale_png!(1, 1, [10])
      red_png = grayscale_png!(1, 1, [245])

      response =
        conn
        |> put_req_header("accept", "image/png")
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0, red: 1.0},
          images: %{
            " White " => Base.encode64(white_png),
            "rEd" => Base.encode64(red_png)
          }
        })

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]
    end

    test "accepts weight light-source keys with surrounding whitespace and mixed case", %{
      conn: conn
    } do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()

      white_png = grayscale_png!(1, 1, [10])
      red_png = grayscale_png!(1, 1, [245])

      response =
        conn
        |> put_req_header("accept", "image/png")
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{" White " => 1.0, "rEd" => 1.0},
          images: %{
            white: Base.encode64(white_png),
            red: Base.encode64(red_png)
          }
        })

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]
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

    test "returns 422 when palette_id is not an integer", %{conn: conn} do
      %{printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: "not-an-integer",
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["palette_id must be an integer"]}} = response
    end

    test "returns 422 when printer_profile_id is not an integer", %{conn: conn} do
      %{palette: palette} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: "not-an-integer",
          weights: %{white: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["printer_profile_id must be an integer"]}} = response
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

    test "returns 422 when weights is not a JSON object", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: ["white"],
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["weights must be a JSON object"]}} = response
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

    test "returns 422 when images is not a JSON object", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: ["white"]
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["images must be a JSON object"]}} = response
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

    test "returns 422 when an image value is not a base64 string", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: 123}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["images[white] must be a base64-encoded string"]}} =
               response
    end

    test "returns 422 when an image is not a PNG", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64("not-a-png")}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => ["images[white] not a valid PNG"]}} = response
    end

    test "returns 422 when an encoded image exceeds the upload size limit", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      oversized_base64 = String.duplicate("A", 8_000_001)

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: oversized_base64}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "maximum allowed upload size"
    end

    test "returns 422 when an image exceeds the maximum allowed area", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      oversized_png = png_with_dimensions_header(2_001, 2_000)

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(oversized_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "maximum allowed image area"
    end

    test "returns 422 when a PNG expands beyond its declared dimensions", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()

      oversized_inflate_png = png_with_oversized_inflate(1, 1)

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{white: Base.encode64(oversized_inflate_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "exceeds expected size"
    end

    test "returns 422 when weighted light sources are missing images", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = full_mapping_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0, red: 1.0},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "missing source images"
      assert message =~ "red"
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

    test "returns 422 for unsupported light source in images before decoding", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      oversized_base64 = String.duplicate("A", 8_000_001)

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{ultraviolet: oversized_base64}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "unsupported light source"
    end

    test "returns 422 for duplicate normalized light sources in weights", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{"white" => 1.0, " White " => 0.5},
          images: %{white: Base.encode64(white_png)}
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "duplicate light source"
      assert message =~ "white"
    end

    test "returns 422 for duplicate normalized light sources in images", %{conn: conn} do
      %{palette: palette, printer_profile: printer_profile} = palette_and_profile_fixture()
      white_png = grayscale_png!(1, 1, [128])

      response =
        conn
        |> post(~p"/api/multi_image_mapping", %{
          palette_id: palette.id,
          printer_profile_id: printer_profile.id,
          weights: %{white: 1.0},
          images: %{
            "white" => Base.encode64(white_png),
            " White " => Base.encode64(white_png)
          }
        })
        |> json_response(422)

      assert %{"errors" => %{"base" => [message]}} = response
      assert message =~ "duplicate light source"
      assert message =~ "white"
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

    Enum.each(palette.colors, fn color ->
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
    end)

    %{palette: palette, printer_profile: printer_profile}
  end

  defp grayscale_png!(width, height, pixels) do
    {:ok, png} = PNG.encode_grayscale(width, height, pixels)
    png
  end

  defp png_with_dimensions_header(width, height) do
    <<137, 80, 78, 71, 13, 10, 26, 10, 13::big-unsigned-integer-size(32), "IHDR",
      width::big-unsigned-integer-size(32), height::big-unsigned-integer-size(32), 8, 0, 0, 0, 0>>
  end

  defp png_with_oversized_inflate(width, height) do
    compressed = :zlib.compress(:binary.copy(<<0>>, 8_192))
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<width::32, height::32, 8, 0, 0, 0, 0>>

    signature <>
      png_chunk("IHDR", ihdr) <>
      png_chunk("IDAT", compressed) <>
      png_chunk("IEND", <<>>)
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32, type::binary-size(4), data::binary, crc::32>>
  end
end

defmodule ColorMatching.MultiImagePaletteMapperTest do
  use ExUnit.Case, async: true

  alias ColorMatching.{MultiImagePaletteMapper, PNG, ResponseVector}
  alias ColorMatching.Persistence.{PaletteColor, PrinterProfile}

  describe "map_to_png/5" do
    test "uses a batch response-vector builder by default" do
      source_images = %{white: grayscale_fixture!(1, 1, [0])}
      palette_colors = [palette_color(1, "#111111"), palette_color(2, "#222222")]
      parent = self()

      batch_builder = fn colors, _printer_profile ->
        send(parent, {:batch, Enum.map(colors, & &1.id)})
        Enum.map(colors, &vector(&1.hex_color, white: 0.0))
      end

      assert {:ok, _png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0},
                 response_vector_batch_builder: batch_builder
               )

      assert_receive {:batch, [1, 2]}
    end

    test "maps multiple grayscale fixtures into palette colors deterministically" do
      source_images = %{
        white: grayscale_fixture!(2, 1, [0, 255]),
        red: grayscale_fixture!(2, 1, [255, 0])
      }

      palette_colors = [
        palette_color(1, "#111111"),
        palette_color(2, "#222222"),
        palette_color(3, "#333333")
      ]

      vectors = %{
        "#111111" => vector("#111111", white: 0.0, red: 0.0),
        "#222222" => vector("#222222", white: 1.0, red: 0.0),
        "#333333" => vector("#333333", white: 0.0, red: 1.0)
      }

      assert {:ok, png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0, red: 1.0},
                 response_vector_builder: response_vector_builder(vectors)
               )

      assert {:ok, %{width: 2, height: 1, pixels: [{51, 51, 51}, {34, 34, 34}]}} =
               PNG.decode_rgb(png)
    end

    test "uses ordinary gamma-encoded grayscale bytes as target brightness values" do
      middle_gray = 128 / 255

      source_images = %{
        white: grayscale_fixture!(1, 1, [128])
      }

      palette_colors = [
        palette_color(1, "#101010"),
        palette_color(2, "#202020")
      ]

      vectors = %{
        "#101010" => vector("#101010", white: middle_gray),
        "#202020" => vector("#202020", white: 0.21586050011389926)
      }

      assert {:ok, png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0},
                 response_vector_builder: response_vector_builder(vectors)
               )

      assert {:ok, %{pixels: [{16, 16, 16}]}} = PNG.decode_rgb(png)
    end

    test "excludes palette colors missing measurements for positive-weight light sources" do
      source_images = %{
        white: grayscale_fixture!(1, 1, [128]),
        red: grayscale_fixture!(1, 1, [255])
      }

      palette_colors = [
        palette_color(1, "#AA0000"),
        palette_color(2, "#00AA00")
      ]

      vectors = %{
        "#AA0000" => vector("#AA0000", white: 128 / 255, red: :missing),
        "#00AA00" => vector("#00AA00", white: 0.45, red: 1.0)
      }

      assert {:ok, png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0, red: 1.0},
                 response_vector_builder: response_vector_builder(vectors)
               )

      assert {:ok, %{pixels: [{0, 170, 0}]}} = PNG.decode_rgb(png)
    end

    test "ignores missing measurements for zero-weight light sources" do
      source_images = %{
        white: grayscale_fixture!(1, 1, [255]),
        blue: grayscale_fixture!(1, 1, [0])
      }

      palette_colors = [
        palette_color(1, "#ABCDEF"),
        palette_color(2, "#123456")
      ]

      vectors = %{
        "#ABCDEF" => vector("#ABCDEF", white: 1.0, blue: :missing),
        "#123456" => vector("#123456", white: 0.6, blue: 0.0)
      }

      assert {:ok, png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0, blue: 0.0},
                 response_vector_builder: response_vector_builder(vectors)
               )

      assert {:ok, %{pixels: [{171, 205, 239}]}} = PNG.decode_rgb(png)
    end

    test "rejects source images with mismatched dimensions" do
      source_images = %{
        white: grayscale_fixture!(1, 1, [0]),
        red: grayscale_fixture!(2, 1, [0, 255])
      }

      assert {:error, message} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 [palette_color(1, "#FFFFFF")],
                 printer_profile(),
                 %{white: 1.0, red: 1.0},
                 response_vector_builder:
                   response_vector_builder(%{
                     "#FFFFFF" => vector("#FFFFFF", white: 1.0, red: 1.0)
                   })
               )

      assert message ==
               "source images must all have the same dimensions; red is 2x1 but white is 1x1"
    end

    test "maps larger images without relying on linear-time pixel indexing" do
      pixels = Enum.to_list(0..255)

      source_images = %{
        white: grayscale_fixture!(256, 1, pixels)
      }

      palette_colors = [
        palette_color(1, "#000000"),
        palette_color(2, "#FFFFFF")
      ]

      vectors = %{
        "#000000" => vector("#000000", white: 0.0),
        "#FFFFFF" => vector("#FFFFFF", white: 1.0)
      }

      assert {:ok, png} =
               MultiImagePaletteMapper.map_to_png(
                 source_images,
                 palette_colors,
                 printer_profile(),
                 %{white: 1.0},
                 response_vector_builder: response_vector_builder(vectors)
               )

      assert {:ok, %{width: 256, height: 1, pixels: mapped_pixels}} = PNG.decode_rgb(png)
      assert hd(mapped_pixels) == {0, 0, 0}
      assert List.last(mapped_pixels) == {255, 255, 255}
    end
  end

  defp grayscale_fixture!(width, height, pixels) do
    {:ok, png} = PNG.encode_grayscale(width, height, pixels)
    png
  end

  defp palette_color(id, hex_color) do
    %PaletteColor{id: id, hex_color: hex_color, sort_order: id}
  end

  defp printer_profile do
    %PrinterProfile{
      id: 1,
      printer_make_model: "Fixture Printer",
      paper_type: "Fixture Paper",
      ink_type: "Fixture Ink"
    }
  end

  defp response_vector_builder(vectors) do
    fn palette_color, _printer_profile ->
      Map.fetch!(vectors, palette_color.hex_color)
    end
  end

  defp vector(hex_color, brightnesses) do
    %ResponseVector{
      hex_color: hex_color,
      printer_profile_id: 1,
      measured_at: nil,
      inserted_at: nil,
      missing?: false,
      white: Keyword.get(brightnesses, :white, :missing),
      red: Keyword.get(brightnesses, :red, :missing),
      green: Keyword.get(brightnesses, :green, :missing),
      blue: Keyword.get(brightnesses, :blue, :missing),
      lps: Keyword.get(brightnesses, :lps, :missing)
    }
  end
end

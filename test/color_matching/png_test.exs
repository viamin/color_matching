defmodule ColorMatching.PNGTest do
  use ExUnit.Case, async: true

  alias ColorMatching.PNG

  describe "decode_grayscale/1" do
    test "returns grayscale pixels in an indexable binary" do
      assert {:ok, png} = PNG.encode_grayscale(2, 2, [0, 64, 128, 255])
      assert {:ok, %{width: 2, height: 2, pixels: pixels}} = PNG.decode_grayscale(png)

      assert is_binary(pixels)
      assert pixels == <<0, 64, 128, 255>>
    end

    test "rejects chunks with invalid CRCs" do
      assert {:ok, png} = PNG.encode_grayscale(1, 1, [128])

      corrupted_png =
        png
        |> :binary.bin_to_list()
        |> List.update_at(29, &Bitwise.bxor(&1, 0x01))
        |> :erlang.list_to_binary()

      assert {:error, "PNG chunk CRC mismatch for IHDR"} = PNG.decode_grayscale(corrupted_png)
    end

    test "decodes sub-filtered grayscale rows" do
      png = grayscale_png(5, 1, [<<1, 10, 10, 10, 10, 10>>])

      assert {:ok, %{width: 5, height: 1, pixels: <<10, 20, 30, 40, 50>>}} =
               PNG.decode_grayscale(png)
    end

    test "decodes grayscale PNGs whose IDAT payload is split across chunks" do
      png =
        grayscale_png(3, 1, [<<0, 10, 20, 30>>], fn compressed ->
          midpoint = div(byte_size(compressed), 2)

          [
            binary_part(compressed, 0, midpoint),
            binary_part(compressed, midpoint, byte_size(compressed) - midpoint)
          ]
        end)

      assert {:ok, %{width: 3, height: 1, pixels: <<10, 20, 30>>}} =
               PNG.decode_grayscale(png)
    end

    test "rejects grayscale PNGs whose decompressed data exceeds IHDR dimensions" do
      png = grayscale_png(1, 1, [:binary.copy(<<0>>, 8_192)])

      assert {:error, "PNG image data exceeds expected size"} = PNG.decode_grayscale(png)
    end
  end

  describe "inspect_header/2" do
    test "extracts width and height from a valid PNG header" do
      assert {:ok, png} = PNG.encode_grayscale(3, 2, [0, 64, 128, 192, 200, 250])

      assert {:ok, %{width: 3, height: 2}} = PNG.inspect_header(png)
    end

    test "rejects inputs that do not start with the PNG signature" do
      assert {:error, "not a valid PNG"} = PNG.inspect_header(<<0, 1, 2, 3>>)
    end

    test "rejects PNGs whose IHDR chunk is malformed" do
      truncated_ihdr =
        <<137, 80, 78, 71, 13, 10, 26, 10, 13::big-unsigned-integer-size(32), "JUNK",
          1::big-unsigned-integer-size(32), 2::big-unsigned-integer-size(32)>>

      assert {:error, "invalid PNG header"} = PNG.inspect_header(truncated_ihdr)
    end

    test "rejects PNGs that exceed the configured pixel area" do
      oversized = png_with_dimensions_header(2_001, 2_000)

      assert {:error, "exceeds the maximum allowed image area"} =
               PNG.inspect_header(oversized, max_pixels: 4_000_000)
    end
  end

  describe "valid_image_area?/3" do
    test "returns true when width * height is within the limit" do
      assert PNG.valid_image_area?(100, 100, 4_000_000)
    end

    test "returns false when width * height exceeds the limit" do
      refute PNG.valid_image_area?(2_001, 2_000, 4_000_000)
    end

    test "returns true when either dimension is zero" do
      assert PNG.valid_image_area?(0, 1_000, 4_000_000)
      assert PNG.valid_image_area?(1_000, 0, 4_000_000)
    end
  end

  defp grayscale_png(width, height, rows, chunk_splitter \\ fn compressed -> [compressed] end) do
    compressed =
      rows
      |> IO.iodata_to_binary()
      |> :zlib.compress()

    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<width::32, height::32, 8, 0, 0, 0, 0>>

    idat_chunks =
      compressed
      |> chunk_splitter.()
      |> Enum.map(&chunk("IDAT", &1))
      |> IO.iodata_to_binary()

    signature <> chunk("IHDR", ihdr) <> idat_chunks <> chunk("IEND", <<>>)
  end

  defp png_with_dimensions_header(width, height) do
    <<137, 80, 78, 71, 13, 10, 26, 10, 13::big-unsigned-integer-size(32), "IHDR",
      width::big-unsigned-integer-size(32), height::big-unsigned-integer-size(32), 8, 0, 0, 0, 0>>
  end

  defp chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32, type::binary-size(4), data::binary, crc::32>>
  end
end

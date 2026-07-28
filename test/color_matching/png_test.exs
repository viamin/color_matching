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
  end

  defp grayscale_png(width, height, rows) do
    compressed =
      rows
      |> IO.iodata_to_binary()
      |> :zlib.compress()

    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<width::32, height::32, 8, 0, 0, 0, 0>>

    signature <> chunk("IHDR", ihdr) <> chunk("IDAT", compressed) <> chunk("IEND", <<>>)
  end

  defp chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32, type::binary-size(4), data::binary, crc::32>>
  end
end

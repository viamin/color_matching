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
  end
end

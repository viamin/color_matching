defmodule ColorMatching.PNG do
  @moduledoc """
  Narrow PNG reader/writer for the mapper service.

  Supported input decoding:

  - 8-bit grayscale (`color_type` 0)
  - 8-bit grayscale+alpha (`color_type` 4, alpha ignored)
  - 8-bit RGB (`color_type` 2)
  - 8-bit RGBA (`color_type` 6, alpha ignored)

  Supported output encoding:

  - 8-bit grayscale
  - 8-bit RGB

  This module intentionally supports only the subset needed by the test
  fixtures and the first palette-mapping service.
  """

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @ihdr "IHDR"
  @idat "IDAT"
  @iend "IEND"

  @type grayscale_image :: %{width: pos_integer(), height: pos_integer(), pixels: binary()}
  @type rgb_image :: %{
          width: pos_integer(),
          height: pos_integer(),
          pixels: [{0..255, 0..255, 0..255}]
        }

  @spec decode_grayscale(binary()) :: {:ok, grayscale_image()} | {:error, String.t()}
  def decode_grayscale(png_binary) when is_binary(png_binary) do
    with {:ok, png} <- decode_png(png_binary),
         :ok <- validate_bit_depth(png.bit_depth),
         {:ok, pixels} <- grayscale_pixels(png) do
      {:ok, %{width: png.width, height: png.height, pixels: pixels}}
    end
  end

  @spec decode_rgb(binary()) :: {:ok, rgb_image()} | {:error, String.t()}
  def decode_rgb(png_binary) when is_binary(png_binary) do
    with {:ok, png} <- decode_png(png_binary),
         :ok <- validate_bit_depth(png.bit_depth),
         {:ok, pixels} <- rgb_pixels(png) do
      {:ok, %{width: png.width, height: png.height, pixels: pixels}}
    end
  end

  @spec encode_grayscale(pos_integer(), pos_integer(), [0..255]) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_grayscale(width, height, pixels)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 and
             is_list(pixels) do
    if length(pixels) == width * height and Enum.all?(pixels, &byte_value?/1) do
      scanlines =
        pixels
        |> Enum.chunk_every(width)
        |> Enum.map(fn row -> [<<0>>, row] end)

      {:ok, encode_png(width, height, 8, 0, scanlines)}
    else
      {:error, "grayscale pixel data does not match the image dimensions"}
    end
  end

  def encode_grayscale(_width, _height, _pixels) do
    {:error, "grayscale pixel data does not match the image dimensions"}
  end

  @spec encode_rgb(pos_integer(), pos_integer(), [{0..255, 0..255, 0..255}]) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_rgb(width, height, pixels)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 and
             is_list(pixels) do
    if length(pixels) == width * height and Enum.all?(pixels, &rgb_tuple?/1) do
      scanlines =
        pixels
        |> Enum.chunk_every(width)
        |> Enum.map(&rgb_scanline/1)

      {:ok, encode_png(width, height, 8, 2, scanlines)}
    else
      {:error, "RGB pixel data does not match the image dimensions"}
    end
  end

  def encode_rgb(_width, _height, _pixels) do
    {:error, "RGB pixel data does not match the image dimensions"}
  end

  defp decode_png(<<@png_signature, rest::binary>>) do
    with {:ok, chunks} <- parse_chunks(rest, []),
         {:ok, ihdr} <- fetch_chunk(chunks, @ihdr),
         {:ok, header} <- parse_ihdr(ihdr),
         :ok <- validate_header(header),
         {:ok, idat_chunks} <- fetch_chunks(chunks, @idat),
         {:ok, decompressed} <- inflate(idat_chunks),
         {:ok, rows} <-
           unfilter_scanlines(decompressed, header.width, header.height, header.color_type) do
      {:ok, Map.put(header, :rows, rows)}
    end
  end

  defp decode_png(_other), do: {:error, "invalid PNG signature"}

  defp parse_chunks(<<>>, _chunks), do: {:error, "missing IEND chunk"}

  defp parse_chunks(
         <<length::big-unsigned-integer-size(32), type::binary-size(4), data::binary-size(length),
           crc::big-unsigned-integer-size(32), rest::binary>>,
         chunks
       ) do
    case validate_chunk_crc(type, data, crc) do
      :ok ->
        updated_chunks = [{type, data} | chunks]

        if type == @iend do
          {:ok, Enum.reverse(updated_chunks)}
        else
          parse_chunks(rest, updated_chunks)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp parse_chunks(_truncated, _chunks), do: {:error, "truncated PNG chunk stream"}

  defp fetch_chunk(chunks, type) do
    case Enum.find(chunks, fn {chunk_type, _data} -> chunk_type == type end) do
      {^type, data} -> {:ok, data}
      nil -> {:error, "missing #{type} chunk"}
    end
  end

  defp fetch_chunks(chunks, type) do
    matching =
      chunks
      |> Enum.filter(fn {chunk_type, _data} -> chunk_type == type end)
      |> Enum.map(fn {_chunk_type, data} -> data end)

    if matching == [] do
      {:error, "missing #{type} chunk"}
    else
      {:ok, matching}
    end
  end

  defp parse_ihdr(
         <<width::big-unsigned-integer-size(32), height::big-unsigned-integer-size(32), bit_depth,
           color_type, compression_method, filter_method, interlace_method>>
       ) do
    {:ok,
     %{
       width: width,
       height: height,
       bit_depth: bit_depth,
       color_type: color_type,
       compression_method: compression_method,
       filter_method: filter_method,
       interlace_method: interlace_method
     }}
  end

  defp parse_ihdr(_other), do: {:error, "invalid IHDR payload"}

  defp validate_header(%{width: width, height: height}) when width <= 0 or height <= 0 do
    {:error, "PNG width and height must be positive"}
  end

  defp validate_header(%{compression_method: 0, filter_method: 0, interlace_method: 0}), do: :ok

  defp validate_header(%{compression_method: compression_method}) when compression_method != 0 do
    {:error, "unsupported PNG compression method"}
  end

  defp validate_header(%{filter_method: filter_method}) when filter_method != 0 do
    {:error, "unsupported PNG filter method"}
  end

  defp validate_header(%{interlace_method: interlace_method}) when interlace_method != 0 do
    {:error, "interlaced PNGs are not supported"}
  end

  defp validate_bit_depth(8), do: :ok
  defp validate_bit_depth(_other), do: {:error, "only 8-bit PNGs are supported"}

  defp inflate(chunks) do
    zstream = :zlib.open()

    try do
      :ok = :zlib.inflateInit(zstream)
      inflated = chunks |> Enum.map(&:zlib.inflate(zstream, &1)) |> IO.iodata_to_binary()
      :ok = :zlib.inflateEnd(zstream)
      {:ok, inflated}
    rescue
      _error -> {:error, "could not decompress PNG image data"}
    after
      :zlib.close(zstream)
    end
  end

  defp unfilter_scanlines(data, width, height, color_type) do
    bytes_per_pixel = bytes_per_pixel(color_type)

    if is_nil(bytes_per_pixel) do
      {:error, "unsupported PNG color type"}
    else
      row_bytes = width * bytes_per_pixel
      expected_bytes = height * (row_bytes + 1)

      if byte_size(data) != expected_bytes do
        {:error, "PNG image data does not match IHDR dimensions"}
      else
        do_unfilter_scanlines(data, height, row_bytes, bytes_per_pixel, [])
      end
    end
  end

  defp do_unfilter_scanlines(<<>>, 0, _row_bytes, _bytes_per_pixel, rows) do
    {:ok, Enum.reverse(rows)}
  end

  defp do_unfilter_scanlines(data, remaining_rows, row_bytes, bytes_per_pixel, rows) do
    <<filter_type, filtered_row::binary-size(^row_bytes), rest::binary>> = data

    previous_row =
      case rows do
        [row | _] -> row
        [] -> :binary.copy(<<0>>, row_bytes)
      end

    with {:ok, row} <- unfilter_row(filter_type, filtered_row, previous_row, bytes_per_pixel) do
      do_unfilter_scanlines(rest, remaining_rows - 1, row_bytes, bytes_per_pixel, [row | rows])
    end
  end

  defp unfilter_row(0, filtered_row, _previous_row, _bytes_per_pixel), do: {:ok, filtered_row}

  defp unfilter_row(1, filtered_row, _previous_row, bytes_per_pixel) do
    {:ok, reconstruct_row(filtered_row, bytes_per_pixel, fn _index, left -> left end)}
  end

  defp unfilter_row(2, filtered_row, previous_row, bytes_per_pixel) do
    {:ok,
     reconstruct_row(filtered_row, bytes_per_pixel, fn index, _left ->
       :binary.at(previous_row, index)
     end)}
  end

  defp unfilter_row(3, filtered_row, previous_row, bytes_per_pixel) do
    {:ok,
     reconstruct_row(filtered_row, bytes_per_pixel, fn index, left ->
       up = :binary.at(previous_row, index)
       div(left + up, 2)
     end)}
  end

  defp unfilter_row(4, filtered_row, previous_row, bytes_per_pixel) do
    {:ok,
     reconstruct_row(filtered_row, bytes_per_pixel, fn index, left ->
       up = :binary.at(previous_row, index)

       up_left =
         if index >= bytes_per_pixel do
           :binary.at(previous_row, index - bytes_per_pixel)
         else
           0
         end

       paeth_predictor(left, up, up_left)
     end)}
  end

  defp unfilter_row(_filter_type, _filtered_row, _previous_row, _bytes_per_pixel) do
    {:error, "unsupported PNG filter type"}
  end

  defp reconstruct_row(filtered_row, bytes_per_pixel, predictor_fun) do
    filtered_row
    |> do_reconstruct_row(bytes_per_pixel, predictor_fun, 0, [], [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_reconstruct_row(<<>>, _bytes_per_pixel, _predictor_fun, _index, acc, _left_bytes),
    do: acc

  defp do_reconstruct_row(
         <<filtered_byte, rest::binary>>,
         bytes_per_pixel,
         predictor_fun,
         index,
         acc,
         left_bytes
       ) do
    left =
      if index >= bytes_per_pixel do
        hd(left_bytes)
      else
        0
      end

    predicted = predictor_fun.(index, left)
    reconstructed_byte = rem(filtered_byte + predicted, 256)

    do_reconstruct_row(
      rest,
      bytes_per_pixel,
      predictor_fun,
      index + 1,
      [reconstructed_byte | acc],
      update_left_bytes(left_bytes, reconstructed_byte, bytes_per_pixel)
    )
  end

  defp update_left_bytes(left_bytes, reconstructed_byte, bytes_per_pixel)
       when length(left_bytes) < bytes_per_pixel do
    left_bytes ++ [reconstructed_byte]
  end

  defp update_left_bytes([_oldest | rest], reconstructed_byte, _bytes_per_pixel) do
    rest ++ [reconstructed_byte]
  end

  defp paeth_predictor(left, up, up_left) do
    p = left + up - up_left
    pa = abs(p - left)
    pb = abs(p - up)
    pc = abs(p - up_left)

    cond do
      pa <= pb and pa <= pc -> left
      pb <= pc -> up
      true -> up_left
    end
  end

  defp grayscale_pixels(%{color_type: 0, rows: rows}) do
    {:ok, IO.iodata_to_binary(rows)}
  end

  defp grayscale_pixels(%{color_type: 4, rows: rows}) do
    pixels =
      rows
      |> Enum.map(fn row ->
        row
        |> :binary.bin_to_list()
        |> Enum.chunk_every(2)
        |> Enum.map(fn [gray, _alpha] -> gray end)
      end)
      |> IO.iodata_to_binary()

    {:ok, pixels}
  end

  defp grayscale_pixels(_png), do: {:error, "source PNG must be grayscale"}

  defp rgb_pixels(%{color_type: 0, rows: rows}) do
    pixels =
      rows
      |> Enum.flat_map(fn row ->
        row
        |> :binary.bin_to_list()
        |> Enum.map(fn gray -> {gray, gray, gray} end)
      end)

    {:ok, pixels}
  end

  defp rgb_pixels(%{color_type: 2, rows: rows}) do
    pixels =
      rows
      |> Enum.flat_map(fn row ->
        row
        |> :binary.bin_to_list()
        |> Enum.chunk_every(3)
        |> Enum.map(fn [red, green, blue] -> {red, green, blue} end)
      end)

    {:ok, pixels}
  end

  defp rgb_pixels(%{color_type: 4, rows: rows}) do
    pixels =
      rows
      |> Enum.flat_map(fn row ->
        row
        |> :binary.bin_to_list()
        |> Enum.chunk_every(2)
        |> Enum.map(fn [gray, _alpha] -> {gray, gray, gray} end)
      end)

    {:ok, pixels}
  end

  defp rgb_pixels(%{color_type: 6, rows: rows}) do
    pixels =
      rows
      |> Enum.flat_map(fn row ->
        row
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(fn [red, green, blue, _alpha] -> {red, green, blue} end)
      end)

    {:ok, pixels}
  end

  defp rgb_pixels(_png), do: {:error, "PNG color type cannot be converted to RGB"}

  defp encode_png(width, height, bit_depth, color_type, scanlines) do
    compressed = deflate(scanlines)

    @png_signature <>
      chunk(@ihdr, <<
        width::big-unsigned-integer-size(32),
        height::big-unsigned-integer-size(32),
        bit_depth,
        color_type,
        0,
        0,
        0
      >>) <> chunk(@idat, compressed) <> chunk(@iend, <<>>)
  end

  defp deflate(iodata) do
    zstream = :zlib.open()

    try do
      :ok = :zlib.deflateInit(zstream)
      compressed = :zlib.deflate(zstream, iodata, :finish)
      :ok = :zlib.deflateEnd(zstream)
      IO.iodata_to_binary(compressed)
    after
      :zlib.close(zstream)
    end
  end

  defp chunk(type, data) do
    size = byte_size(data)
    crc = :erlang.crc32([type, data])

    <<size::big-unsigned-integer-size(32), type::binary-size(4), data::binary,
      crc::big-unsigned-integer-size(32)>>
  end

  defp validate_chunk_crc(type, data, expected_crc) do
    actual_crc = :erlang.crc32([type, data])

    if actual_crc == expected_crc do
      :ok
    else
      {:error, "PNG chunk CRC mismatch for #{type}"}
    end
  end

  defp rgb_scanline(row) do
    encoded_row = Enum.map(row, fn {red, green, blue} -> <<red, green, blue>> end)
    [<<0>>, encoded_row]
  end

  defp bytes_per_pixel(0), do: 1
  defp bytes_per_pixel(2), do: 3
  defp bytes_per_pixel(4), do: 2
  defp bytes_per_pixel(6), do: 4
  defp bytes_per_pixel(_other), do: nil

  defp byte_value?(value), do: is_integer(value) and value in 0..255

  defp rgb_tuple?({red, green, blue}) do
    Enum.all?([red, green, blue], &byte_value?/1)
  end

  defp rgb_tuple?(_other), do: false
end

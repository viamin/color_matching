defmodule ColorMatching.MultiImagePaletteMapper do
  @moduledoc """
  Maps one grayscale PNG per illumination condition into a printable
  palette-color PNG using measured illuminant response vectors.

  Source grayscale values are treated as ordinary gamma-encoded PNG channel
  values normalized directly from `0..255` into `0.0..1.0`. This first
  version intentionally does not apply linear-luminance conversion.
  """

  alias ColorMatching.{ColorFormat, IlluminantMatching, Persistence, PNG, ResponseVector}
  alias ColorMatching.Persistence.{PaletteColor, PrinterProfile}
  @supported_light_sources ResponseVector.light_sources()

  @type source_images :: %{required(ResponseVector.light_source() | String.t()) => binary()}
  @type response_vector_builder :: (PaletteColor.t(), PrinterProfile.t() -> ResponseVector.t())
  @type response_vector_batch_builder ::
          ([PaletteColor.t()], PrinterProfile.t() -> [ResponseVector.t()])
  @type option ::
          {:response_vector_builder, response_vector_builder()}
          | {:response_vector_batch_builder, response_vector_batch_builder()}
          | {:scoring_module, module()}
  @type options :: [option()]

  @spec map_to_png(source_images(), [PaletteColor.t()], PrinterProfile.t(), map(), options()) ::
          {:ok, binary()} | {:error, String.t() | tuple()}
  def map_to_png(
        source_images_by_light_source,
        palette_colors,
        printer_profile,
        weights,
        options \\ []
      )

  def map_to_png(
        source_images_by_light_source,
        palette_colors,
        %PrinterProfile{} = printer_profile,
        weights,
        options
      )
      when is_map(source_images_by_light_source) and is_list(palette_colors) and is_map(weights) do
    if is_integer(printer_profile.id) do
      do_map_to_png(source_images_by_light_source, palette_colors, printer_profile, weights, options)
    else
      {:error, "invalid mapper arguments"}
    end
  end

  defp do_map_to_png(
         source_images_by_light_source,
         palette_colors,
         %PrinterProfile{} = printer_profile,
         weights,
         options
       ) do
    response_vector_builder = Keyword.get(options, :response_vector_builder)

    response_vector_batch_builder =
      Keyword.get(options, :response_vector_batch_builder, &Persistence.response_vectors/2)

    scoring_module = Keyword.get(options, :scoring_module, ColorMatching.WeightedSquaredError)

    with {:ok, normalized_images} <- normalize_source_images(source_images_by_light_source),
         {:ok, normalized_weights} <- normalize_weights(weights),
         :ok <- validate_positive_weights(normalized_weights),
         :ok <- validate_required_source_images(normalized_images, normalized_weights),
         :ok <- validate_palette_colors(palette_colors),
         {:ok, decoded_images} <- decode_source_images(normalized_images),
         {:ok, width, height} <- validate_dimensions(decoded_images),
         {:ok, candidates} <-
           build_candidates(
             palette_colors,
             printer_profile,
             response_vector_batch_builder,
             response_vector_builder
           ),
         {:ok, pixels} <-
           map_pixels(
             width,
             height,
             decoded_images,
             candidates,
             printer_profile,
             normalized_weights,
             scoring_module
           ) do
      PNG.encode_rgb(width, height, pixels)
    else
      {:error, _reason} = error -> error
    end
  end

  def map_to_png(
        _source_images_by_light_source,
        _palette_colors,
        _printer_profile,
        _weights,
        _options
      ) do
    {:error, "invalid mapper arguments"}
  end

  defp normalize_source_images(source_images_by_light_source) do
    Enum.reduce_while(source_images_by_light_source, {:ok, %{}}, &normalize_source_image/2)
  end

  defp normalize_source_image({source, png_binary}, {:ok, acc}) do
    case normalize_source_image_entry(source, png_binary) do
      {:ok, normalized_source} ->
        put_normalized_entry(
          acc,
          normalized_source,
          png_binary,
          "source images contain duplicate light source after normalization"
        )

      {:error, message} ->
        {:halt, {:error, message}}
    end
  end

  defp normalize_source_image(_entry, _acc),
    do: {:halt, {:error, "source images must be a map of light sources to PNG binaries"}}

  defp normalize_source_image_entry(source, png_binary) when is_binary(png_binary) do
    case normalize_light_source(source) do
      {:ok, normalized_source} -> {:ok, normalized_source}
      {:error, _message} = error -> error
    end
  end

  defp normalize_source_image_entry(source, _png_binary),
    do: {:error, "source image for #{inspect(source)} must be a PNG binary"}

  defp normalize_weights(weights) do
    Enum.reduce_while(weights, {:ok, %{}}, &normalize_weight/2)
  end

  defp normalize_weight({source, weight}, {:ok, acc}) do
    case normalize_weight_entry(source, weight) do
      {:ok, normalized_source, normalized_weight} ->
        put_normalized_entry(
          acc,
          normalized_source,
          normalized_weight,
          "weights contain duplicate light source after normalization"
        )

      {:error, message} ->
        {:halt, {:error, message}}
    end
  end

  defp normalize_weight(_entry, _acc),
    do: {:halt, {:error, "weights must be a map of light sources to numbers"}}

  defp normalize_weight_entry(source, weight) when is_integer(weight) do
    case normalize_light_source(source) do
      {:ok, normalized_source} -> {:ok, normalized_source, weight * 1.0}
      {:error, _message} = error -> error
    end
  end

  defp normalize_weight_entry(source, weight) when is_float(weight) do
    if finite_float?(weight) do
      normalized_light_source(source, weight)
    else
      invalid_weight(source)
    end
  end

  defp normalize_weight_entry(source, _weight), do: invalid_weight(source)

  defp normalized_light_source(source, weight) do
    case normalize_light_source(source) do
      {:ok, normalized_source} -> {:ok, normalized_source, weight}
      {:error, _message} = error -> error
    end
  end

  defp invalid_weight(source),
    do: {:error, "weight for #{inspect(source)} must be a finite number"}

  defp finite_float?(value) when is_float(value) do
    case :erlang.float_to_binary(value, [:compact]) do
      "nan" -> false
      "inf" -> false
      "-inf" -> false
      _other -> true
    end
  rescue
    ArgumentError -> false
  end

  defp validate_positive_weights(weights) do
    if Enum.any?(weights, fn {_source, weight} -> weight > 0 end) do
      :ok
    else
      {:error, "at least one light source weight must be greater than 0"}
    end
  end

  defp validate_required_source_images(source_images, weights) do
    missing_sources =
      weights
      |> Enum.filter(fn {_source, weight} -> weight > 0 end)
      |> Enum.map(fn {source, _weight} -> source end)
      |> Enum.reject(&Map.has_key?(source_images, &1))

    if missing_sources == [] do
      :ok
    else
      {:error,
       "missing source images for weighted light sources: " <>
         Enum.map_join(missing_sources, ", ", &Atom.to_string/1)}
    end
  end

  defp validate_palette_colors([]), do: {:error, "at least one palette color is required"}
  defp validate_palette_colors(_palette_colors), do: :ok

  defp decode_source_images(source_images) do
    Enum.reduce_while(source_images, {:ok, %{}}, fn {source, png_binary}, {:ok, acc} ->
      case PNG.decode_grayscale(png_binary) do
        {:ok, image} ->
          {:cont, {:ok, Map.put(acc, source, image)}}

        {:error, message} ->
          {:halt, {:error, "#{Atom.to_string(source)} source image: #{message}"}}
      end
    end)
  end

  defp validate_dimensions(decoded_images) do
    decoded_images
    |> sorted_decoded_images()
    |> case do
      [] ->
        {:error, "at least one source image is required"}

      [{first_source, first_image} | rest] ->
        uniform_dimensions(first_source, first_image, rest)
    end
  end

  defp sorted_decoded_images(decoded_images) do
    decoded_images
    |> Map.to_list()
    |> Enum.sort_by(fn {source, _image} ->
      Enum.find_index(@supported_light_sources, &(&1 == source))
    end)
  end

  defp uniform_dimensions(first_source, first_image, rest) do
    first_dimensions = {first_image.width, first_image.height}

    case Enum.find(rest, fn {_source, image} ->
           {image.width, image.height} != first_dimensions
         end) do
      nil ->
        {:ok, first_image.width, first_image.height}

      {source, image} ->
        first_label = Atom.to_string(first_source)
        source_label = Atom.to_string(source)

        {:error,
         "source images must all have the same dimensions; " <>
           "#{source_label} is #{image.width}x#{image.height} but " <>
           "#{first_label} is #{first_image.width}x#{first_image.height}"}
    end
  end

  defp build_candidates(
         palette_colors,
         printer_profile,
         response_vector_batch_builder,
         response_vector_builder
       ) do
    vectors =
      if response_vector_builder do
        Enum.map(palette_colors, &response_vector_builder.(&1, printer_profile))
      else
        response_vector_batch_builder.(palette_colors, printer_profile)
      end

    if Enum.all?(vectors, &match?(%ResponseVector{}, &1)) do
      {:ok, vectors}
    else
      {:error, "response vector builder must return %ResponseVector{}"}
    end
  end

  defp map_pixels(
         width,
         height,
         decoded_images,
         candidates,
         printer_profile,
         weights,
         scoring_module
       ) do
    pixel_count = width * height
    rgb_by_hex = Map.new(candidates, &candidate_rgb/1)

    0..(pixel_count - 1)
    |> Enum.reduce_while({:ok, []}, fn pixel_index, {:ok, acc} ->
      target = build_target_vector(pixel_index, decoded_images, printer_profile)

      case IlluminantMatching.best_match(candidates, target, weights, scoring_module) do
        {%ResponseVector{hex_color: hex_color}, _score} ->
          {:cont, {:ok, [Map.fetch!(rgb_by_hex, hex_color) | acc]}}

        nil ->
          {x, y} = pixel_coordinates(pixel_index, width)

          {:halt,
           {:error,
            "no eligible palette color for output pixel (#{x}, #{y}); " <>
              "all candidates were excluded for the weighted light sources"}}
      end
    end)
    |> case do
      {:ok, pixels} -> {:ok, Enum.reverse(pixels)}
      {:error, _reason} = error -> error
    end
  end

  defp build_target_vector(pixel_index, decoded_images, %PrinterProfile{id: printer_profile_id})
       when is_integer(printer_profile_id) do
    brightnesses =
      ResponseVector.light_sources()
      |> Enum.map(fn source ->
        brightness =
          case Map.get(decoded_images, source) do
            nil -> :missing
            image -> normalize_grayscale(:binary.at(image.pixels, pixel_index))
          end

        {source, brightness}
      end)

    missing? = Enum.any?(brightnesses, fn {_source, brightness} -> brightness == :missing end)

    %ResponseVector{
      hex_color: "#000000",
      printer_profile_id: printer_profile_id,
      measured_at: nil,
      inserted_at: nil,
      missing?: missing?,
      white: Keyword.get(brightnesses, :white, :missing),
      red: Keyword.get(brightnesses, :red, :missing),
      green: Keyword.get(brightnesses, :green, :missing),
      blue: Keyword.get(brightnesses, :blue, :missing),
      lps: Keyword.get(brightnesses, :lps, :missing)
    }
  end

  defp candidate_rgb(%ResponseVector{hex_color: hex_color}) do
    {:ok, rgb} = ColorFormat.hex_to_rgb(hex_color)
    {hex_color, rgb}
  end

  defp normalize_grayscale(value), do: value / 255

  defp pixel_coordinates(pixel_index, width) do
    {rem(pixel_index, width), div(pixel_index, width)}
  end

  defp normalize_light_source(source) when source in @supported_light_sources, do: {:ok, source}

  defp normalize_light_source(source) when is_binary(source) do
    normalized_source =
      source
      |> String.trim()
      |> String.downcase()

    case Enum.find(@supported_light_sources, &(Atom.to_string(&1) == normalized_source)) do
      nil -> {:error, "unsupported light source: #{inspect(source)}"}
      atom_source -> {:ok, atom_source}
    end
  end

  defp normalize_light_source(source),
    do: {:error, "unsupported light source: #{inspect(source)}"}

  defp put_normalized_entry(acc, normalized_source, value, duplicate_prefix) do
    if Map.has_key?(acc, normalized_source) do
      {:halt, {:error, "#{duplicate_prefix}: #{Atom.to_string(normalized_source)}"}}
    else
      {:cont, {:ok, Map.put(acc, normalized_source, value)}}
    end
  end
end

defmodule ColorMatching.MultiImagePaletteMapper do
  @moduledoc """
  Maps one grayscale PNG per illumination condition into a printable
  palette-color PNG using measured illuminant response vectors.

  Source grayscale values are treated as ordinary gamma-encoded PNG channel
  values normalized directly from `0..255` into `0.0..1.0`. This first
  version intentionally does not apply linear-luminance conversion.
  """

  alias ColorMatching.{ColorFormat, IlluminantMatching, PNG, Persistence, ResponseVector}
  alias ColorMatching.Persistence.{PaletteColor, PrinterProfile}
  @supported_light_sources ResponseVector.light_sources()

  @type source_images :: %{required(ResponseVector.light_source() | String.t()) => binary()}
  @type response_vector_builder :: (PaletteColor.t(), PrinterProfile.t() -> ResponseVector.t())
  @type option ::
          {:response_vector_builder, response_vector_builder()}
          | {:scoring_module, module()}
  @type options :: [option()]

  @spec map_to_png(source_images(), [PaletteColor.t()], PrinterProfile.t(), map(), options()) ::
          {:ok, binary()} | {:error, String.t() | tuple()}
  def map_to_png(source_images_by_light_source, palette_colors, printer_profile, weights, options \\ [])

  def map_to_png(source_images_by_light_source, palette_colors, %PrinterProfile{} = printer_profile, weights, options)
      when is_map(source_images_by_light_source) and is_list(palette_colors) and is_map(weights) do
    response_vector_builder =
      Keyword.get(options, :response_vector_builder, &Persistence.response_vector/2)

    scoring_module = Keyword.get(options, :scoring_module, ColorMatching.WeightedSquaredError)

    with {:ok, normalized_images} <- normalize_source_images(source_images_by_light_source),
         {:ok, normalized_weights} <- normalize_weights(weights),
         :ok <- validate_positive_weights(normalized_weights),
         :ok <- validate_required_source_images(normalized_images, normalized_weights),
         :ok <- validate_palette_colors(palette_colors),
         {:ok, decoded_images} <- decode_source_images(normalized_images),
         {:ok, width, height} <- validate_dimensions(decoded_images),
         {:ok, candidates} <-
           build_candidates(palette_colors, printer_profile, response_vector_builder),
         {:ok, pixels} <-
           map_pixels(
             width,
             height,
             decoded_images,
             candidates,
             printer_profile,
             normalized_weights,
             scoring_module
           ),
         {:ok, png} <- PNG.encode_rgb(width, height, pixels) do
      {:ok, png}
    else
      {:error, _reason} = error -> error
    end
  end

  def map_to_png(_source_images_by_light_source, _palette_colors, _printer_profile, _weights, _options) do
    {:error, "invalid mapper arguments"}
  end

  defp normalize_source_images(source_images_by_light_source) do
    Enum.reduce_while(source_images_by_light_source, {:ok, %{}}, fn {source, png_binary}, {:ok, acc} ->
      with {:ok, normalized_source} <- normalize_light_source(source),
           true <- is_binary(png_binary) do
        {:cont, {:ok, Map.put(acc, normalized_source, png_binary)}}
      else
        false -> {:halt, {:error, "source image for #{inspect(source)} must be a PNG binary"}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp normalize_weights(weights) do
    Enum.reduce_while(weights, {:ok, %{}}, fn {source, weight}, {:ok, acc} ->
      with {:ok, normalized_source} <- normalize_light_source(source),
           true <- is_number(weight) do
        {:cont, {:ok, Map.put(acc, normalized_source, weight * 1.0)}}
      else
        false -> {:halt, {:error, "weight for #{inspect(source)} must be numeric"}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
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
      {:error, "missing source images for weighted light sources: #{Enum.map_join(missing_sources, ", ", &Atom.to_string/1)}"}
    end
  end

  defp validate_palette_colors([]), do: {:error, "at least one palette color is required"}
  defp validate_palette_colors(_palette_colors), do: :ok

  defp decode_source_images(source_images) do
    Enum.reduce_while(source_images, {:ok, %{}}, fn {source, png_binary}, {:ok, acc} ->
      case PNG.decode_grayscale(png_binary) do
        {:ok, image} -> {:cont, {:ok, Map.put(acc, source, image)}}
        {:error, message} -> {:halt, {:error, "#{Atom.to_string(source)} source image: #{message}"}}
      end
    end)
  end

  defp validate_dimensions(decoded_images) do
    [{first_source, first_image} | rest] = Map.to_list(decoded_images)
    dimensions = {first_image.width, first_image.height}

    case Enum.find(rest, fn {_source, image} -> {image.width, image.height} != dimensions end) do
      {source, image} ->
        {:error,
         "source images must all have the same dimensions; #{Atom.to_string(source)} is #{image.width}x#{image.height} but #{Atom.to_string(first_source)} is #{first_image.width}x#{first_image.height}"}

      nil ->
        {:ok, first_image.width, first_image.height}
    end
  end

  defp build_candidates(palette_colors, printer_profile, response_vector_builder) do
    Enum.reduce_while(palette_colors, {:ok, []}, fn palette_color, {:ok, acc} ->
      case response_vector_builder.(palette_color, printer_profile) do
        %ResponseVector{} = vector ->
          {:cont, {:ok, [vector | acc]}}

        _other ->
          {:halt, {:error, "response vector builder must return %ColorMatching.ResponseVector{}"}}
      end
    end)
    |> case do
      {:ok, vectors} -> {:ok, Enum.reverse(vectors)}
      {:error, _reason} = error -> error
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
            "no eligible palette color for output pixel (#{x}, #{y}); all candidates were excluded for the weighted light sources"}}
      end
    end)
    |> case do
      {:ok, pixels} -> {:ok, Enum.reverse(pixels)}
      {:error, _reason} = error -> error
    end
  end

  defp build_target_vector(pixel_index, decoded_images, printer_profile) do
    brightnesses =
      ResponseVector.light_sources()
      |> Enum.map(fn source ->
        brightness =
          case Map.get(decoded_images, source) do
            nil -> :missing
            image -> normalize_grayscale(Enum.at(image.pixels, pixel_index))
          end

        {source, brightness}
      end)

    missing? = Enum.any?(brightnesses, fn {_source, brightness} -> brightness == :missing end)

    %ResponseVector{
      hex_color: "#000000",
      printer_profile_id: printer_profile.id,
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

  defp normalize_light_source(source), do: {:error, "unsupported light source: #{inspect(source)}"}
end

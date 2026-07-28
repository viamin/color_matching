defmodule ColorMatchingWeb.MultiImageMappingController do
  @moduledoc """
  API endpoint for multi-image grayscale-to-palette color mapping.

  Accepts one base64-encoded grayscale PNG per illumination condition along
  with per-light-source weights and palette/printer-profile identifiers.
  Returns a palette-colored RGB PNG on success, or structured JSON errors on
  failure.

  ## Request format (JSON)

      {
        "palette_id": 1,
        "printer_profile_id": 2,
        "weights": {
          "white": 0.5,
          "red": 1.0,
          "green": 1.0,
          "blue": 0.0,
          "lps": 1.5
        },
        "images": {
          "white": "<base64-encoded grayscale PNG>",
          "red":   "<base64-encoded grayscale PNG>"
        }
      }

  ## Success response

  HTTP 200 with `Content-Type: image/png` and the mapped PNG as the body.

  ## Error response

      { "errors": { "base": ["..."] } }
  """

  use ColorMatchingWeb, :controller

  alias ColorMatching.{MultiImagePaletteMapper, Persistence, PNG, ResponseVector}

  @max_image_base64_bytes 8_000_000
  def create(conn, params) do
    with {:ok, palette_id} <- require_integer(params, "palette_id"),
         {:ok, printer_profile_id} <- require_integer(params, "printer_profile_id"),
         {:ok, raw_weights} <- require_map(params, "weights"),
         {:ok, weights} <- normalize_light_source_map(raw_weights, "weights"),
         {:ok, raw_images} <- require_map(params, "images"),
         {:ok, images} <- normalize_light_source_map(raw_images, "images"),
         {:ok, palette} <- fetch_palette(palette_id),
         {:ok, printer_profile} <- fetch_printer_profile(printer_profile_id),
         {:ok, decoded_images} <- decode_images(images),
         {:ok, png_binary} <-
           MultiImagePaletteMapper.map_to_png(
             decoded_images,
             palette.colors,
             printer_profile,
             weights
           ) do
      conn
      |> put_resp_header("content-type", "image/png")
      |> send_resp(200, png_binary)
    else
      {:error, {:not_found, resource}} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{base: ["#{resource} not found"]}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{base: [reason]}})
    end
  end

  # ---------------------------------------------------------------------------
  # Parameter helpers
  # ---------------------------------------------------------------------------

  defp require_integer(params, key) do
    case fetch_param(params, key) do
      nil ->
        {:error, "#{key} is required"}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> {:error, "#{key} must be an integer"}
        end

      _ ->
        {:error, "#{key} must be an integer"}
    end
  end

  defp require_map(params, key) do
    case fetch_param(params, key) do
      nil -> {:error, "#{key} is required"}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a JSON object"}
    end
  end

  defp fetch_param(params, key) when is_map(params) and is_binary(key) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        case existing_atom_key(key) do
          {:ok, atom_key} -> Map.get(params, atom_key)
          :error -> nil
        end
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp fetch_palette(palette_id) do
    case Persistence.get_palette(palette_id) do
      nil -> {:error, {:not_found, "palette"}}
      palette -> {:ok, palette}
    end
  end

  defp fetch_printer_profile(printer_profile_id) do
    case Persistence.get_printer_profile(printer_profile_id) do
      nil -> {:error, {:not_found, "printer profile"}}
      printer_profile -> {:ok, printer_profile}
    end
  end

  defp normalize_light_source_map(values, param_name) when is_map(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_light_source(key) do
        {:ok, source} ->
          put_unique_light_source(acc, source, value, param_name)

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp decode_images(raw_images) do
    Enum.reduce_while(raw_images, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case decode_image(key, value) do
        {:ok, binary} -> {:cont, {:ok, Map.put(acc, key, binary)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode_image(key, value) when is_binary(value) do
    label = image_label(key)

    with :ok <- validate_base64_size(label, value),
         {:ok, binary} <- decode_base64_image(label, value),
         :ok <- validate_png_header(label, binary) do
      {:ok, binary}
    end
  end

  defp decode_image(key, _value),
    do: {:error, "images[#{image_label(key)}] must be a base64-encoded string"}

  defp validate_png_header(label, binary) do
    case PNG.inspect_header(binary) do
      {:ok, _header} -> :ok
      {:error, reason} -> {:error, "images[#{label}] #{reason}"}
    end
  end

  defp validate_base64_size(label, value) do
    if byte_size(value) <= @max_image_base64_bytes do
      :ok
    else
      {:error, "images[#{label}] exceeds the maximum allowed upload size"}
    end
  end

  defp decode_base64_image(label, value) do
    case Base.decode64(value) do
      {:ok, binary} ->
        {:ok, binary}

      :error ->
        case Base.decode64(value, padding: false) do
          {:ok, binary} -> {:ok, binary}
          :error -> {:error, "images[#{label}] is not valid base64"}
        end
    end
  end

  defp image_label(key) when is_atom(key), do: Atom.to_string(key)
  defp image_label(key) when is_binary(key), do: key
  defp image_label(key), do: inspect(key)

  defp normalize_light_source(source) when is_atom(source),
    do: normalize_light_source(Atom.to_string(source))

  defp normalize_light_source(source) when is_binary(source) do
    normalized_source =
      source
      |> String.trim()
      |> String.downcase()

    case Enum.find(ResponseVector.light_sources(), &(Atom.to_string(&1) == normalized_source)) do
      nil -> {:error, "unsupported light source: #{inspect(source)}"}
      atom_source -> {:ok, atom_source}
    end
  end

  defp normalize_light_source(source),
    do: {:error, "unsupported light source: #{inspect(source)}"}

  defp put_unique_light_source(acc, source, value, param_name) do
    if Map.has_key?(acc, source) do
      {:halt,
       {:error,
        "#{param_name} contains duplicate light source after normalization: #{Atom.to_string(source)}"}}
    else
      {:cont, {:ok, Map.put(acc, source, value)}}
    end
  end
end

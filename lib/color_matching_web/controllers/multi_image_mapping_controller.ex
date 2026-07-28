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

  alias ColorMatching.{MultiImagePaletteMapper, Persistence}

  @max_image_base64_bytes 8_000_000
  @max_image_pixels 4_000_000
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  def create(conn, params) do
    with {:ok, palette_id} <- require_integer(params, "palette_id"),
         {:ok, printer_profile_id} <- require_integer(params, "printer_profile_id"),
         {:ok, weights} <- require_map(params, "weights"),
         {:ok, raw_images} <- require_map(params, "images"),
         {:ok, palette} <- fetch_palette(palette_id),
         {:ok, printer_profile} <- fetch_printer_profile(printer_profile_id),
         {:ok, images} <- decode_images(raw_images),
         {:ok, png_binary} <-
           MultiImagePaletteMapper.map_to_png(
             images,
             palette.colors,
             printer_profile,
             weights
           ) do
      conn
      |> put_resp_content_type("image/png", nil)
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
    case Map.get(params, key) do
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
    case Map.get(params, key) do
      nil -> {:error, "#{key} is required"}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a JSON object"}
    end
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

  defp decode_images(raw_images) do
    Enum.reduce_while(raw_images, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case decode_image(key, value) do
        {:ok, binary} -> {:cont, {:ok, Map.put(acc, key, binary)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode_image(key, value) when is_binary(value) do
    with :ok <- validate_base64_size(key, value),
         {:ok, binary} <- decode_base64_image(key, value),
         :ok <- validate_png_header(key, binary) do
      {:ok, binary}
    end
  end

  defp decode_image(key, _value), do: {:error, "images[#{key}] must be a base64-encoded string"}

  defp validate_base64_size(key, value) do
    if byte_size(value) <= @max_image_base64_bytes do
      :ok
    else
      {:error, "images[#{key}] exceeds the maximum allowed upload size"}
    end
  end

  defp decode_base64_image(key, value) do
    case Base.decode64(value, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, "images[#{key}] is not valid base64"}
    end
  end

  defp validate_png_header(
         key,
         <<@png_signature, 13::big-unsigned-integer-size(32), "IHDR",
           width::big-unsigned-integer-size(32), height::big-unsigned-integer-size(32),
           _rest::binary>>
       ) do
    if width * height <= @max_image_pixels do
      :ok
    else
      {:error, "images[#{key}] exceeds the maximum allowed image area"}
    end
  end

  defp validate_png_header(key, <<@png_signature, _rest::binary>>) do
    {:error, "images[#{key}] has an invalid PNG header"}
  end

  defp validate_png_header(key, _binary) do
    {:error, "images[#{key}] is not a valid PNG"}
  end
end

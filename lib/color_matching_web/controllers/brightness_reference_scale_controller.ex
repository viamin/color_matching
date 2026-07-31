defmodule ColorMatchingWeb.BrightnessReferenceScaleController do
  @moduledoc """
  User-facing download endpoint for printable apparent-brightness reference
  scales.

  Accepts an illuminant in the path and optional `block_size` / `orientation`
  query params, then returns a printable PNG strip.
  """

  use ColorMatchingWeb, :controller

  alias ColorMatching.BrightnessReferenceScale

  @invalid_block_size_message "block_size must be a positive integer"
  @default_block_size BrightnessReferenceScale.default_block_size()

  def show(conn, params) do
    with {:ok, scale} <- BrightnessReferenceScale.new(params["illuminant"]),
         {:ok, options} <- png_options(params),
         {:ok, png} <- BrightnessReferenceScale.to_png(scale, options) do
      conn
      |> put_resp_content_type("image/png", nil)
      |> put_resp_header("content-disposition", content_disposition(scale))
      |> send_resp(200, png)
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{base: [reason]}})
    end
  end

  defp png_options(params) do
    with {:ok, block_size} <- parse_block_size(params["block_size"]),
         {:ok, orientation} <- parse_orientation(params["orientation"]) do
      {:ok, [block_size: block_size, orientation: orientation]}
    end
  end

  defp parse_block_size(nil), do: {:ok, @default_block_size}
  defp parse_block_size(block_size) when is_integer(block_size), do: {:ok, block_size}

  defp parse_block_size(block_size) when is_binary(block_size) do
    case Integer.parse(block_size) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, @invalid_block_size_message}
    end
  end

  defp parse_block_size(_block_size), do: {:error, @invalid_block_size_message}

  defp parse_orientation(nil), do: {:ok, :horizontal}
  defp parse_orientation("horizontal"), do: {:ok, :horizontal}
  defp parse_orientation("vertical"), do: {:ok, :vertical}
  defp parse_orientation(:horizontal), do: {:ok, :horizontal}
  defp parse_orientation(:vertical), do: {:ok, :vertical}

  defp parse_orientation(orientation),
    do: {:error, "unsupported orientation: #{inspect(orientation)}"}

  defp content_disposition(scale) do
    filename = "brightness-reference-scale-#{scale.illuminant}.png"
    ~s(attachment; filename="#{filename}")
  end
end

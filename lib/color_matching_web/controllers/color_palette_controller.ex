defmodule ColorMatchingWeb.ColorPaletteController do
  @moduledoc """
  Versioned JSON API for the printable-color palette and its measured
  illumination responses.

  Consumed by the macOS composition app (and any other client) to fetch the
  data it needs to solve illumination-dependent images without duplicating the
  `color_matching` data model:

    * `GET /api/v1/printer_profiles` — available printer/material profiles
    * `GET /api/v1/palettes` — available palettes
    * `GET /api/v1/colors?printer_profile_id=N&palette_id=M` — palette colors
      with their measured illuminant response vectors

  Response vectors are scoped to a printer profile, so `printer_profile_id` is
  required on `/colors`. `palette_id` is optional: when omitted, every color
  across all palettes is returned. Light sources without a measurement are
  omitted from a color's `responses` so clients can distinguish "missing" from
  "measured as zero brightness".
  """

  use ColorMatchingWeb, :controller

  alias ColorMatching.{ColorFormat, Persistence}
  alias ColorMatching.Persistence.{PaletteColor, PrinterProfile}

  @doc """
  `GET /api/v1/printer_profiles`
  """
  def printer_profiles(conn, _params) do
    profiles = Persistence.list_printer_profiles()
    json(conn, %{printer_profiles: Enum.map(profiles, &profile_json/1)})
  end

  @doc """
  `GET /api/v1/palettes`
  """
  def palettes(conn, _params) do
    palettes = Persistence.list_palettes()

    json(conn, %{
      palettes:
        Enum.map(palettes, fn palette ->
          %{
            id: palette.id,
            name: palette.name,
            is_preset: palette.is_preset,
            color_count: length(palette.colors)
          }
        end)
    })
  end

  @doc """
  `GET /api/v1/colors?printer_profile_id=N&palette_id=M`
  """
  def colors(conn, params) do
    with {:ok, printer_profile} <- fetch_printer_profile(params),
         {:ok, palette_colors, palette} <- fetch_palette_colors(params),
         details_by_id <- Persistence.response_details(palette_colors, printer_profile) do
      json(conn, %{
        printer_profile: profile_json(printer_profile),
        colors:
          Enum.map(
            palette_colors,
            &color_json(&1, palette, Map.get(details_by_id, &1.id, %{}))
          )
      })
    else
      {:error, :missing_param, key} ->
        bad_request(conn, "missing required query parameter: #{key}")

      {:error, :invalid_param, key} ->
        bad_request(conn, "invalid #{key}: expected an integer")

      {:error, :printer_profile_not_found} ->
        not_found(conn, "printer profile not found")

      {:error, :palette_not_found} ->
        not_found(conn, "palette not found")
    end
  end

  # ---------------------------------------------------------------------------
  # Parameter / lookup helpers
  # ---------------------------------------------------------------------------

  defp fetch_printer_profile(params) do
    with {:ok, id} <- require_integer_param(params, "printer_profile_id") do
      case Persistence.get_printer_profile(id) do
        %PrinterProfile{} = profile -> {:ok, profile}
        nil -> {:error, :printer_profile_not_found}
      end
    end
  end

  defp fetch_palette_colors(params) do
    case Map.fetch(params, "palette_id") do
      {:ok, value} -> fetch_palette(value)
      :error -> {:ok, Persistence.list_palette_colors(), nil}
    end
  end

  defp fetch_palette(value) do
    with {:ok, id} <- parse_integer(value, "palette_id"),
         %{} = palette <- Persistence.get_palette(id) do
      {:ok, palette.colors, palette}
    else
      nil -> {:error, :palette_not_found}
      error -> error
    end
  end

  defp require_integer_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> parse_integer(value, key)
      :error -> {:error, :missing_param, key}
    end
  end

  defp parse_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, key) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_param, key}
    end
  end

  defp parse_integer(_value, key), do: {:error, :invalid_param, key}

  # ---------------------------------------------------------------------------
  # JSON rendering
  # ---------------------------------------------------------------------------

  defp profile_json(%PrinterProfile{} = profile) do
    %{
      id: profile.id,
      printer_make_model: profile.printer_make_model,
      paper_type: profile.paper_type,
      ink_type: profile.ink_type
    }
  end

  defp color_json(%PaletteColor{} = color, palette, details) do
    resolved_palette = palette || color.palette

    %{
      id: color.id,
      name: color.display_label,
      hex: color.hex_color,
      rgb: rgb_json(color.hex_color),
      palette_id: color.palette_id,
      palette_name: palette_name(resolved_palette),
      sort_order: color.sort_order,
      responses: Map.new(details, fn {source, detail} -> {source, response_json(detail)} end)
    }
  end

  defp palette_name(%ColorMatching.Persistence.Palette{name: name}), do: name
  defp palette_name(_palette), do: nil

  defp rgb_json(hex_color) do
    case ColorFormat.hex_to_rgb(hex_color) do
      {:ok, {r, g, b}} -> %{r: r, g: g, b: b}
      {:error, _message} -> nil
    end
  end

  defp response_json(detail) do
    %{
      brightness: detail.brightness,
      source: detail.source,
      raw_value: detail.raw_value,
      raw_unit: detail.raw_unit,
      apparent_brightness: detail.apparent_brightness,
      measured_at: datetime_to_iso8601(detail.measured_at),
      test_run_id: detail.test_run_id
    }
  end

  defp datetime_to_iso8601(nil), do: nil

  defp datetime_to_iso8601(%DateTime{microsecond: {0, _}} = datetime) do
    DateTime.to_iso8601(%{datetime | microsecond: {0, 0}})
  end

  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp bad_request(conn, detail) do
    conn |> put_status(:bad_request) |> json(%{errors: %{detail: detail}})
  end

  defp not_found(conn, detail) do
    conn |> put_status(:not_found) |> json(%{errors: %{detail: detail}})
  end
end

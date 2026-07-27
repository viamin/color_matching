defmodule ColorMatchingWeb.IlluminantMeasurementController do
  use ColorMatchingWeb, :controller

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.IlluminantMeasurement

  def create(conn, params) do
    case Persistence.create_illuminant_measurement(params) do
      {:ok, measurement} ->
        conn
        |> put_status(:created)
        |> json(%{data: measurement_json(measurement)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: externalize_error_keys(changeset_errors(changeset))})
    end
  end

  def bulk_create(conn, params) do
    case Persistence.create_illuminant_measurements_bulk(params) do
      {:ok, measurements} ->
        conn
        |> put_status(:created)
        |> json(%{data: Enum.map(measurements, &measurement_json/1)})

      {:error, {:invalid_request, errors}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: externalize_error_keys(errors)})

      {:error, {:invalid_rows, invalid_rows}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          errors:
            Enum.map(invalid_rows, fn invalid_row ->
              %{
                index: invalid_row.index,
                color_id: invalid_row.color_id,
                errors: externalize_error_keys(invalid_row.errors)
              }
            end)
        })
    end
  end

  @spec measurement_json(IlluminantMeasurement.t()) :: map()
  defp measurement_json(measurement) do
    %{
      id: measurement.id,
      color_id: measurement.palette_color_id,
      printer_profile_id: measurement.printer_profile_id,
      light_source: measurement.light_source,
      brightness: measurement.normalized_brightness,
      raw_value: measurement.raw_measured_value,
      raw_unit: measurement.raw_value_unit,
      notes: measurement.notes,
      measured_at: datetime_to_iso8601(measurement.measured_at),
      measurement_method: measurement.measurement_method,
      measurement_device: measurement.measurement_device,
      test_run_id: measurement.test_run_id,
      inserted_at: datetime_to_iso8601(measurement.inserted_at),
      updated_at: datetime_to_iso8601(measurement.updated_at)
    }
  end

  @spec datetime_to_iso8601(DateTime.t() | nil) :: String.t() | nil
  defp datetime_to_iso8601(nil), do: nil
  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @spec externalize_error_keys(map()) :: map()
  defp externalize_error_keys(errors) do
    errors
    |> Enum.map(fn {key, value} -> {external_error_key(key), value} end)
    |> Map.new()
  end

  @spec external_error_key(atom()) :: atom()
  defp external_error_key(:palette_color_id), do: :color_id
  defp external_error_key(:normalized_brightness), do: :brightness
  defp external_error_key(:raw_measured_value), do: :raw_value
  defp external_error_key(:raw_value_unit), do: :raw_unit
  defp external_error_key(key), do: key
end

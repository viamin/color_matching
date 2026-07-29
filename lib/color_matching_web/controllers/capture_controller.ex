defmodule ColorMatchingWeb.CaptureController do
  use ColorMatchingWeb, :controller

  alias ColorMatching.Persistence

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"sheet_id" => sheet_id} = params) do
    case Persistence.create_capture(sheet_id, params) do
      {:ok, capture} ->
        conn
        |> put_status(:created)
        |> json(%{capture_id: capture.id})

      {:error, :test_sheet_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Sheet not found"}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  @spec upload_measurements(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def upload_measurements(conn, %{"capture_id" => capture_id} = params) do
    case Ecto.Type.cast(:integer, capture_id) do
      {:ok, integer_capture_id} -> handle_measurement_upload(conn, integer_capture_id, params)
      :error -> render_capture_not_found(conn)
    end
  end

  @spec handle_measurement_upload(Plug.Conn.t(), integer(), map()) :: Plug.Conn.t()
  defp handle_measurement_upload(conn, capture_id, params) do
    case Persistence.upload_capture_measurements(capture_id, params) do
      {:ok, %{measurements: measurements, pair_scores: pair_scores}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          capture_id: capture_id,
          measurement_count: length(measurements),
          pair_score_count: length(pair_scores)
        })

      {:error, :capture_not_found} ->
        render_capture_not_found(conn)

      {:error, {:invalid_request, errors}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})

      {:error, {:invalid_rows, invalid_rows}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: externalize_invalid_rows(invalid_rows)})
    end
  end

  @spec render_capture_not_found(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_capture_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Capture not found"}})
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: map()
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @spec externalize_invalid_rows(map()) :: map()
  defp externalize_invalid_rows(invalid_rows) do
    %{
      measurements: Enum.map(invalid_rows.measurements, &externalize_invalid_row(&1, :patch_id)),
      pair_scores: Enum.map(invalid_rows.pair_scores, &externalize_invalid_row(&1, :pair_id))
    }
  end

  @spec externalize_invalid_row(map(), atom()) :: map()
  defp externalize_invalid_row(invalid_row, identifier_key) do
    %{
      index: invalid_row.index,
      identifier_key => invalid_row.identifier,
      errors: invalid_row.errors
    }
  end
end

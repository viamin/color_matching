defmodule ColorMatchingWeb.TestSheetController do
  use ColorMatchingWeb, :controller

  alias ColorMatching.Persistence

  @spec manifest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifest(conn, %{"sheet_id" => sheet_id}) do
    sheet = Persistence.get_test_sheet_by_lookup_code!(sheet_id)
    render(conn, :manifest, sheet: sheet)
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{errors: %{detail: "Sheet not found"}})
  end

  @spec recent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def recent(conn, _params) do
    sheets = Persistence.list_test_sheets()
    render(conn, :recent, sheets: sheets)
  end
end

defmodule ColorMatchingWeb.TestSheetController do
  use ColorMatchingWeb, :controller

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet
  alias ColorMatching.Repo

  @spec manifest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifest(conn, %{"sheet_id" => sheet_id}) do
    sheet =
      TestSheet
      |> Repo.get_by(lookup_code: sheet_id)
      |> case do
        nil -> nil
        sheet -> Repo.preload(sheet, [:printer_profile, :pairs])
      end

    case sheet do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Sheet not found"}})

      sheet ->
        render(conn, :manifest, sheet: sheet)
    end
  end

  @spec recent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def recent(conn, _params) do
    sheets = Persistence.list_recent_test_sheets(limit: 20)
    render(conn, :recent, sheets: sheets)
  end
end

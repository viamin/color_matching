defmodule ColorMatchingWeb.TestSheetController do
  use ColorMatchingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias ColorMatching.Persistence
  alias ColorMatching.RankedResults
  alias ColorMatchingWeb.ApiSchemas.{JsonObject, Manifest}
  alias ColorMatchingWeb.ApiSchemas.RankedResults, as: RankedResultsSchema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true, replace_params: false

  tags ["Test sheets"]
  security [%{"bearerAuth" => []}]

  operation :manifest,
    summary: "Fetch a test sheet manifest",
    parameters: [sheet_id: [in: :path, type: :string]],
    responses: [ok: {"Sheet manifest", "application/json", Manifest}]

  operation :recent,
    summary: "List recent test sheets",
    responses: [ok: {"Recent sheets", "application/json", JsonObject}]

  operation :ranked_results,
    summary: "Fetch ranked results for a test sheet",
    parameters: [sheet_id: [in: :path, type: :string]],
    responses: [ok: {"Ranked results", "application/json", RankedResultsSchema}]

  @spec manifest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifest(conn, %{"sheet_id" => sheet_id}) do
    case Persistence.get_test_sheet_by_lookup_code(sheet_id) do
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

  @spec ranked_results(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ranked_results(conn, %{"sheet_id" => sheet_id}) do
    case Persistence.get_test_sheet_by_lookup_code(sheet_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Sheet not found"}})

      sheet ->
        results = RankedResults.for_sheet(sheet)
        render(conn, :ranked_results, sheet: sheet, results: results)
    end
  end
end

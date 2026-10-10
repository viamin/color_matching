defmodule ColorMatchingWeb.MethodNotAllowedController do
  @moduledoc false

  use ColorMatchingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  operation :show, false

  def show(conn, _params) do
    conn
    |> put_resp_header("allow", "GET")
    |> send_resp(:method_not_allowed, "")
  end
end

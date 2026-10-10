defmodule ColorMatchingWeb.OpenApiController do
  @moduledoc false

  use ColorMatchingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  operation :show, false

  def show(conn, _params), do: OpenApiSpex.Plug.RenderSpec.call(conn, [])
end

defmodule ColorMatchingWeb.OpenApiController do
  @moduledoc false

  use ColorMatchingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Plug.RenderSpec

  operation :show, false

  def show(conn, _params), do: RenderSpec.call(conn, [])
end

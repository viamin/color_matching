defmodule ColorMatchingWeb.ApiSpec do
  @moduledoc """
  OpenAPI 3 contract for every JSON endpoint exposed by `ColorMatchingWeb.Router`.
  """

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{title: "Color Matching API", version: "v1"},
      servers: [%Server{url: "/"}],
      paths: api_paths(),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "API token"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp api_paths do
    ColorMatchingWeb.Router.__routes__()
    |> Enum.filter(&String.starts_with?(&1.path, "/api/"))
    |> Paths.from_routes()
  end
end

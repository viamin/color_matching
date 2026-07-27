defmodule ColorMatchingWeb.Plugs.ApiAuth do
  @moduledoc """
  Optional bearer-token authentication for the JSON API.

  If `config :color_matching, :api_token` is set to a non-nil, non-empty string,
  every request must carry a matching `Authorization: Bearer <token>` header.
  If no token is configured (the default for local development), all requests are
  allowed through without authentication.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case configured_token() do
      nil ->
        conn

      token ->
        case extract_bearer_token(conn) do
          bearer_token when is_binary(bearer_token) ->
            if Plug.Crypto.secure_compare(bearer_token, token) do
              conn
            else
              reject_unauthorized(conn)
            end

          _ ->
            reject_unauthorized(conn)
        end
    end
  end

  @spec configured_token() :: String.t() | nil
  defp configured_token do
    case Application.get_env(:color_matching, :api_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @spec extract_bearer_token(Plug.Conn.t()) :: String.t() | nil
  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  @spec reject_unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp reject_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: "Unauthorized"}})
    |> halt()
  end
end

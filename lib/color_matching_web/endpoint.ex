defmodule ColorMatchingWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :color_matching

  @multi_image_mapping_request_limit_bytes 50_000_000

  @default_parser_options [
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  ]
  @multi_image_mapping_parser_options [
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: @multi_image_mapping_request_limit_bytes,
    json_decoder: Phoenix.json_library()
  ]

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_color_matching_key",
    signing_salt: "n6ZPl5hs",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :color_matching,
    gzip: false,
    only: ColorMatchingWeb.static_paths()
  )

  # Add tidewave plugin
  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(:parse_request)

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ColorMatchingWeb.Router)

  defp parse_request(%Plug.Conn{request_path: "/api/multi_image_mapping"} = conn, _opts) do
    parse_with_options(conn, @multi_image_mapping_parser_options)
  end

  defp parse_request(conn, _opts) do
    Plug.Parsers.call(conn, Plug.Parsers.init(@default_parser_options))
  end

  defp parse_with_options(conn, options) do
    Plug.Parsers.call(conn, Plug.Parsers.init(options))
  rescue
    Plug.Parsers.ParseError ->
      send_api_error(conn, :unprocessable_entity, "request body contains invalid JSON")

    Plug.Parsers.RequestTooLargeError ->
      send_api_error(conn, :payload_too_large, "request body exceeds the maximum allowed size")
  end

  defp send_api_error(conn, status, message) do
    body = Jason.encode!(%{errors: %{base: [message]}})

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
    |> Plug.Conn.halt()
  end
end

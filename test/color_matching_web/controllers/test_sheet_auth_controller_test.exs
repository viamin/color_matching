defmodule ColorMatchingWeb.TestSheetAuthControllerTest do
  # async: false is required because the setup block calls Application.put_env,
  # which mutates global state and is not safe to run concurrently.
  use ColorMatchingWeb.ConnCase, async: false

  describe "authentication" do
    setup do
      Application.put_env(:color_matching, :api_token, "test-secret-token")
      on_exit(fn -> Application.delete_env(:color_matching, :api_token) end)
      :ok
    end

    test "returns 401 when token is configured but no Authorization header provided", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end

    test "returns 401 when wrong token is provided", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> get(~p"/api/v1/test_sheets/recent")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end

    test "returns 200 when correct token is provided", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> get(~p"/api/v1/test_sheets/recent")

      assert json_response(conn, 200)
    end

    test "returns 401 when manifest is accessed without token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/test_sheets/UNKN-2345/manifest")

      body = json_response(conn, 401)
      assert body["errors"]["detail"] == "Unauthorized"
    end
  end
end

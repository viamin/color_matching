defmodule ColorMatchingWeb.BrightnessReferenceScaleControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.PNG

  describe "GET /brightness_reference_scales/:illuminant" do
    test "returns a printable PNG for a supported illuminant", %{conn: conn} do
      response =
        conn
        |> put_req_header("accept", "image/png")
        |> get(~p"/brightness_reference_scales/red", %{block_size: "12", orientation: "vertical"})

      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["image/png"]

      assert get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="brightness-reference-scale-red.png")
             ]

      assert {:ok, %{width: 12, height: 132}} = PNG.inspect_header(response.resp_body)
    end

    test "returns 422 for an unsupported illuminant", %{conn: conn} do
      response =
        conn
        |> get(~p"/brightness_reference_scales/candle")
        |> json_response(422)

      assert response == %{
               "errors" => %{"base" => ["unsupported illuminant: \"candle\""]}
             }
    end

    test "returns 422 for an invalid block size", %{conn: conn} do
      response =
        conn
        |> get(~p"/brightness_reference_scales/white", %{block_size: "zero"})
        |> json_response(422)

      assert response == %{
               "errors" => %{"base" => ["block_size must be a positive integer"]}
             }
    end
  end
end

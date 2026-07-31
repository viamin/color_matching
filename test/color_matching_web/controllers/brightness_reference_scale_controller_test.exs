defmodule ColorMatchingWeb.BrightnessReferenceScaleControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.BrightnessReferenceScale
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

      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]

      assert get_resp_header(response, "content-security-policy") == [
               "base-uri 'self'; frame-ancestors 'self';"
             ]

      assert {:ok, %{width: 25, height: 132}} = PNG.inspect_header(response.resp_body)
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

    test "returns 422 for an oversized block size", %{conn: conn} do
      response =
        conn
        |> get(~p"/brightness_reference_scales/white", %{
          block_size: Integer.to_string(BrightnessReferenceScale.max_block_size() + 1)
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "base" => [
                   "block_size must be less than or equal to #{BrightnessReferenceScale.max_block_size()}"
                 ]
               }
             }
    end
  end
end

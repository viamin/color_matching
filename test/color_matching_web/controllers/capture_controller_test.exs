defmodule ColorMatchingWeb.CaptureControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp create_palette do
    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Capture API Palette",
        colors: [
          %{hex_color: "#FF0000", sort_order: 0},
          %{hex_color: "#00FF00", sort_order: 1}
        ]
      })

    palette
  end

  defp create_printer_profile do
    {:ok, profile} =
      Persistence.create_printer_profile(%{
        printer_make_model: "Epson SureColor P900",
        paper_type: "Ultra Premium Luster",
        ink_type: "OEM UltraChrome PRO10"
      })

    profile
  end

  defp create_sheet(lookup_code) do
    palette = create_palette()
    profile = create_printer_profile()

    {:ok, sheet} =
      Persistence.create_test_sheet(%{
        lookup_code: lookup_code,
        palette_id: palette.id,
        printer_profile_id: profile.id,
        sheet_version: "lps-letter-grid-v1",
        pairs: [
          %{
            pair_id: TestSheet.pair_id(lookup_code, 0, 0),
            row: 0,
            col: 0,
            color_a_hex: "#FF0000",
            color_b_hex: "#00FFFF"
          },
          %{
            pair_id: TestSheet.pair_id(lookup_code, 0, 1),
            row: 0,
            col: 1,
            color_a_hex: "#00FF00",
            color_b_hex: "#FF00FF"
          }
        ]
      })

    sheet
  end

  defp capture_payload do
    %{
      device_model: "iPhone16,2",
      lens: "wide",
      exposure_duration: 0.008,
      iso: 100,
      focus_lens_position: 0.42,
      white_balance_gains: %{r: 2.1, g: 1.0, b: 1.9},
      image_width: 3024,
      image_height: 4032,
      app_version: "1.2.3",
      timestamp: "2026-07-28T12:34:56.123456Z",
      detected_marker_count: 4,
      blur_score: 0.03,
      rejection_reasons: ["none"]
    }
  end

  defp measurement_payload(sheet) do
    [first_pair, second_pair] = sheet.pairs

    %{
      measurements: [
        %{
          patch_id: first_pair.pair_id,
          linear_rgb_median: [0.12, 0.34, 0.56],
          normalized_linear_rgb_median: [0.2, 0.3, 0.4],
          sample_count: 1200,
          clipping_fraction: 0.01,
          mean: [0.13, 0.35, 0.57],
          standard_deviation: [0.01, 0.02, 0.03]
        },
        %{
          patch_id: second_pair.pair_id,
          linear_rgb_median: [0.22, 0.44, 0.66],
          normalized_linear_rgb_median: [0.5, 0.6, 0.7],
          sample_count: 900,
          clipping_fraction: 0.0,
          mean: [0.23, 0.45, 0.67],
          standard_deviation: [0.02, 0.03, 0.04]
        }
      ],
      pair_scores: [
        %{pair_id: first_pair.pair_id, algorithm_version: "ios-score/v1", score: 0.91},
        %{pair_id: second_pair.pair_id, algorithm_version: "ios-score/v1", score: 0.87}
      ]
    }
  end

  defp judgment_payload(sheet, judgment \\ "near_match") do
    [first_pair | _rest] = sheet.pairs

    %{
      judgments: [
        %{
          pair_id: first_pair.pair_id,
          judgment: judgment
        }
      ]
    }
  end

  describe "POST /api/v1/test_sheets/:sheet_id/captures" do
    test "creates a capture session for a known sheet", %{conn: conn} do
      sheet = create_sheet("CAPA-2345")

      response =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)

      assert is_integer(response["capture_id"])
      assert Persistence.get_capture(response["capture_id"]).test_sheet_id == sheet.id
    end

    test "returns structured 404 JSON for an unknown sheet", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/test_sheets/UNKN-2345/captures", capture_payload())
        |> json_response(404)

      assert response == %{"errors" => %{"detail" => "Sheet not found"}}
    end

    test "returns validation errors for invalid quality metadata", %{conn: conn} do
      sheet = create_sheet("CAPA-2346")

      response =
        conn
        |> post(
          ~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures",
          capture_payload()
          |> Map.merge(%{
            detected_marker_count: -1,
            image_width: 0
          })
        )
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "detected_marker_count" => ["must be greater than or equal to 0"],
                 "image_width" => ["must be greater than 0"]
               }
             }
    end
  end

  describe "POST /api/v1/captures/:capture_id/measurements" do
    test "uploads measurements and pair scores idempotently", %{conn: conn} do
      sheet = create_sheet("CAPA-2347")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      first_response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", measurement_payload(sheet))
        |> json_response(200)

      conn = recycle(conn)

      second_response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", measurement_payload(sheet))
        |> json_response(200)

      assert first_response == %{
               "capture_id" => capture_id,
               "measurement_count" => 2,
               "pair_score_count" => 2
             }

      assert second_response == first_response
      assert length(Persistence.list_capture_patch_measurements(capture_id)) == 2
      assert length(Persistence.list_capture_pair_scores(capture_id)) == 2
    end

    test "returns structured 404 JSON for an unknown capture", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/captures/999999/measurements", %{measurements: []})
        |> json_response(404)

      assert response == %{"errors" => %{"detail" => "Capture not found"}}
    end

    test "returns row-level errors for invalid patch and pair ids", %{conn: conn} do
      sheet = create_sheet("CAPA-2348")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", %{
          measurements: [
            %{
              patch_id: "pair-missing",
              linear_rgb_median: [0.12, 0.34, 0.56],
              normalized_linear_rgb_median: [0.2, 0.3, 0.4],
              sample_count: 1200,
              clipping_fraction: 0.01,
              mean: [0.13, 0.35, 0.57],
              standard_deviation: [0.01, 0.02, 0.03]
            }
          ],
          pair_scores: [
            %{pair_id: "pair-missing", algorithm_version: "ios-score/v1", score: 0.91}
          ]
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "measurements" => [
                   %{
                     "index" => 0,
                     "patch_id" => "pair-missing",
                     "errors" => %{"patch_id" => ["is not present on the capture sheet"]}
                   }
                 ],
                 "pair_scores" => [
                   %{
                     "index" => 0,
                     "pair_id" => "pair-missing",
                     "errors" => %{"pair_id" => ["is not present on the capture sheet"]}
                   }
                 ]
               }
             }
    end

    test "returns validation errors for malformed RGB payloads", %{conn: conn} do
      sheet = create_sheet("CAPA-2349")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      invalid_patch_id = hd(sheet.pairs).pair_id

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", %{
          measurements: [
            %{
              patch_id: invalid_patch_id,
              linear_rgb_median: [0.12, 0.34],
              normalized_linear_rgb_median: [0.2, 0.3, 0.4],
              sample_count: 1200,
              clipping_fraction: 0.01,
              mean: [0.13, 0.35, 0.57],
              standard_deviation: [0.01, 0.02, 0.03]
            }
          ]
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "measurements" => [
                   %{
                     "index" => 0,
                     "patch_id" => invalid_patch_id,
                     "errors" => %{"linear_rgb_median" => ["is invalid"]}
                   }
                 ],
                 "pair_scores" => []
               }
             }
    end

    test "returns validation errors for malformed RGB JSON strings", %{conn: conn} do
      sheet = create_sheet("CAPA-235A")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      patch_id = hd(sheet.pairs).pair_id

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", %{
          measurements: [
            %{
              patch_id: patch_id,
              linear_rgb_median: "[0.12, 0.34]",
              normalized_linear_rgb_median: [0.2, 0.3, 0.4],
              sample_count: 1200,
              clipping_fraction: 0.01,
              mean: "{\"r\":0.13}",
              standard_deviation: [0.01, 0.02, 0.03]
            }
          ]
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "measurements" => [
                   %{
                     "index" => 0,
                     "patch_id" => patch_id,
                     "errors" => %{
                       "linear_rgb_median" => ["is invalid"],
                       "mean" => ["is invalid"]
                     }
                   }
                 ],
                 "pair_scores" => []
               }
             }
    end

    test "accepts RGB JSON strings that normalize to three numeric channels", %{conn: conn} do
      sheet = create_sheet("CAPA-235B")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      [first_pair, second_pair] = sheet.pairs

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/measurements", %{
          measurements: [
            %{
              patch_id: first_pair.pair_id,
              linear_rgb_median: "[0.12, 0.34, 0.56]",
              normalized_linear_rgb_median: "{\"r\":0.2,\"g\":0.3,\"b\":0.4}",
              sample_count: 1200,
              clipping_fraction: 0.01,
              mean: "{\"r\":0.13,\"g\":0.35,\"b\":0.57}",
              standard_deviation: [0.01, 0.02, 0.03]
            }
          ],
          pair_scores: [
            %{pair_id: second_pair.pair_id, algorithm_version: "ios-score/v1", score: 0.87}
          ]
        })
        |> json_response(200)

      assert response == %{
               "capture_id" => capture_id,
               "measurement_count" => 1,
               "pair_score_count" => 1
             }

      [measurement] = Persistence.list_capture_patch_measurements(capture_id)

      assert Jason.decode!(measurement.linear_rgb_median) == [0.12, 0.34, 0.56]
      assert Jason.decode!(measurement.normalized_linear_rgb_median) == [0.2, 0.3, 0.4]
      assert Jason.decode!(measurement.mean) == [0.13, 0.35, 0.57]
    end
  end

  describe "POST /api/v1/captures/:capture_id/judgments" do
    test "appends the first observation and returns a derived current finding", %{conn: conn} do
      sheet = create_sheet("CAPA-235C")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/judgments", judgment_payload(sheet))
        |> json_response(200)

      pair_id = hd(sheet.pairs).pair_id
      pair_finding = Persistence.get_pair_finding_by_pair_id(pair_id)
      [observation] = Persistence.list_pair_finding_observations(pair_id)

      assert response == %{
               "capture_id" => capture_id,
               "judgment_count" => 1
             }

      assert observation.capture_id == capture_id
      assert observation.judgment == "near_match"
      assert pair_finding.current_capture_id == capture_id
      assert pair_finding.current_judgment == "near_match"
    end

    test "preserves history and updates the current finding on later observations", %{conn: conn} do
      sheet = create_sheet("CAPA-235D")

      first_capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      conn
      |> post(~p"/api/v1/captures/#{first_capture_id}/judgments", judgment_payload(sheet))
      |> json_response(200)

      conn = recycle(conn)

      second_capture_id =
        conn
        |> post(
          ~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures",
          Map.put(capture_payload(), :timestamp, "2026-07-28T12:35:56.123456Z")
        )
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      response =
        conn
        |> post(
          ~p"/api/v1/captures/#{second_capture_id}/judgments",
          judgment_payload(sheet, "match")
        )
        |> json_response(200)

      pair_id = hd(sheet.pairs).pair_id
      observations = Persistence.list_pair_finding_observations(pair_id)
      pair_finding = Persistence.get_pair_finding_by_pair_id(pair_id)

      assert response == %{
               "capture_id" => second_capture_id,
               "judgment_count" => 1
             }

      assert Enum.map(observations, & &1.judgment) == ["near_match", "match"]
      assert pair_finding.current_capture_id == second_capture_id
      assert pair_finding.current_judgment == "match"
    end

    test "returns structured 404 JSON for an unknown capture", %{conn: conn} do
      response =
        conn
        |> post(~p"/api/v1/captures/999999/judgments", %{
          judgments: [%{pair_id: "pair-1", judgment: "match"}]
        })
        |> json_response(404)

      assert response == %{"errors" => %{"detail" => "Capture not found"}}
    end

    test "returns row-level errors for an invalid pair id", %{conn: conn} do
      sheet = create_sheet("CAPA-235E")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/judgments", %{
          judgments: [%{pair_id: "pair-missing", judgment: "near_match"}]
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "judgments" => [
                   %{
                     "index" => 0,
                     "pair_id" => "pair-missing",
                     "errors" => %{"pair_id" => ["is not present on the capture sheet"]}
                   }
                 ]
               }
             }
    end

    test "returns row-level errors for an unsupported judgment value", %{conn: conn} do
      sheet = create_sheet("CAPA-235F")

      capture_id =
        conn
        |> post(~p"/api/v1/test_sheets/#{sheet.lookup_code}/captures", capture_payload())
        |> json_response(201)
        |> Map.fetch!("capture_id")

      conn = recycle(conn)
      pair_id = hd(sheet.pairs).pair_id

      response =
        conn
        |> post(~p"/api/v1/captures/#{capture_id}/judgments", %{
          judgments: [%{pair_id: pair_id, judgment: "close_enough"}]
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "judgments" => [
                   %{
                     "index" => 0,
                     "pair_id" => pair_id,
                     "errors" => %{"judgment" => ["is invalid"]}
                   }
                 ]
               }
             }
    end
  end
end

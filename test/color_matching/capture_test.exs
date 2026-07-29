defmodule ColorMatching.CaptureTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet

  defp create_palette do
    {:ok, palette} =
      Persistence.create_palette(%{
        name: "Capture Fixture Palette",
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

  defp capture_attrs do
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

  defp upload_payload(sheet) do
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
        %{
          pair_id: first_pair.pair_id,
          algorithm_version: "ios-score/v1",
          score: 0.91
        },
        %{
          pair_id: second_pair.pair_id,
          algorithm_version: "ios-score/v1",
          score: 0.87
        }
      ]
    }
  end

  describe "capture persistence" do
    test "creates a capture and stores encoded metadata" do
      sheet = create_sheet("CAPT-2345")

      assert {:ok, capture} = Persistence.create_capture(sheet.lookup_code, capture_attrs())

      loaded_capture = Persistence.get_capture(capture.id)

      assert loaded_capture.test_sheet_id == sheet.id
      assert loaded_capture.device_model == "iPhone16,2"
      assert loaded_capture.lens == "wide"
      assert loaded_capture.image_width == 3024
      assert loaded_capture.image_height == 4032

      assert Jason.decode!(loaded_capture.white_balance_gains) == %{
               "b" => 1.9,
               "g" => 1.0,
               "r" => 2.1
             }

      assert Jason.decode!(loaded_capture.rejection_reasons) == ["none"]
    end

    test "upserts measurements and pair scores idempotently for a capture" do
      sheet = create_sheet("CAPT-2346")
      {:ok, capture} = Persistence.create_capture(sheet.lookup_code, capture_attrs())
      payload = upload_payload(sheet)

      assert {:ok, %{measurements: measurements, pair_scores: pair_scores}} =
               Persistence.upload_capture_measurements(capture.id, payload)

      assert length(measurements) == 2
      assert length(pair_scores) == 2

      assert {:ok, %{measurements: second_measurements, pair_scores: second_pair_scores}} =
               Persistence.upload_capture_measurements(capture.id, payload)

      assert length(second_measurements) == 2
      assert length(second_pair_scores) == 2
      assert length(Persistence.list_capture_patch_measurements(capture.id)) == 2
      assert length(Persistence.list_capture_pair_scores(capture.id)) == 2

      [first_measurement | _rest] = Persistence.list_capture_patch_measurements(capture.id)
      assert Jason.decode!(first_measurement.linear_rgb_median) |> length() == 3
    end
  end
end

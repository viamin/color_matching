defmodule ColorMatching.PrinterProfileTest do
  use ExUnit.Case

  alias ColorMatching.{GeneratedSheet, MeasuredColorPair, PredictionRequest, PrinterProfile}

  describe "validate/1" do
    test "builds a first-class printer profile with the core metadata fields" do
      assert {:ok, profile} =
               PrinterProfile.validate(%{
                 "printer_make_model" => "Epson SureColor P900",
                 "paper_type" => "Premium Luster",
                 "ink_type" => "OEM pigment",
                 "icc_profile" => "P900 Luster ICC",
                 "print_settings" => "1440 dpi",
                 "driver_name" => "Epson Driver",
                 "driver_version" => "15.4",
                 "calibration_date" => "2026-07-01",
                 "calibration_version" => "baseline-1",
                 "notes" => "Fresh nozzle check"
               })

      assert profile.printer_make_model == "Epson SureColor P900"
      assert profile.paper_type == "Premium Luster"
      assert profile.ink_type == "OEM pigment"
      assert profile.icc_profile == "P900 Luster ICC"
      assert profile.print_settings == "1440 dpi"
      assert profile.driver_name == "Epson Driver"
      assert profile.driver_version == "15.4"
      assert profile.calibration_date == "2026-07-01"
      assert profile.calibration_version == "baseline-1"
      assert profile.notes == "Fresh nozzle check"
      assert String.starts_with?(profile.id, "profile-")
    end

    test "rejects profiles missing required printer metadata" do
      assert {:error, "Printer make/model is required"} =
               PrinterProfile.validate(%{"paper_type" => "Matte", "ink_type" => "OEM"})
    end
  end

  describe "associations" do
    test "generated sheets and measured pairs retain printer profile context" do
      profile =
        PrinterProfile.new(%{
          printer_make_model: "Canon PRO-100",
          paper_type: "Matte",
          ink_type: "Third-party dye"
        })

      sheet =
        GeneratedSheet.new(%{
          colors: ["#112233", "#445566"],
          grid_size: 6,
          palette_name: "Studio Set",
          printer_profile: profile
        })

      pair =
        MeasuredColorPair.new(%{
          color_a: "#112233",
          color_b: "#445566",
          printer_profile: profile,
          generated_sheet_id: sheet.id
        })

      prediction =
        PredictionRequest.new(%{
          target_colors: ["#112233", "#445566"],
          printer_profile: profile
        })

      assert sheet.printer_profile.id == profile.id
      assert pair.printer_profile.id == profile.id
      assert pair.generated_sheet_id == sheet.id
      assert prediction.printer_profile.id == profile.id
    end

    test "query params round-trip enough profile context for pair measurements" do
      profile =
        PrinterProfile.new(%{
          id: "profile-demo",
          printer_make_model: "Epson SureColor P700",
          paper_type: "Baryta",
          ink_type: "OEM pigment"
        })

      params = profile |> PrinterProfile.to_query_params() |> Map.new()
      rebuilt = PrinterProfile.from_query_params(params)

      assert rebuilt.id == "profile-demo"
      assert rebuilt.printer_make_model == "Epson SureColor P700"
      assert rebuilt.paper_type == "Baryta"
      assert rebuilt.ink_type == "OEM pigment"
    end
  end
end

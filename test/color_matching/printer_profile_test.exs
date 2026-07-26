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

  describe "from_map/1" do
    test "builds a printer profile from valid map attributes" do
      profile =
        PrinterProfile.from_map(%{
          "printer_make_model" => "Epson SureColor P900",
          "paper_type" => "Premium Luster",
          "ink_type" => "OEM pigment",
          "notes" => "Fresh nozzle check"
        })

      assert %PrinterProfile{} = profile
      assert profile.printer_make_model == "Epson SureColor P900"
      assert profile.paper_type == "Premium Luster"
      assert profile.ink_type == "OEM pigment"
      assert profile.notes == "Fresh nozzle check"
    end

    test "returns nil for invalid printer profile attributes" do
      assert is_nil(PrinterProfile.from_map(%{"paper_type" => "Matte", "ink_type" => "OEM"}))
      assert is_nil(PrinterProfile.from_map("not-a-map"))
    end
  end

  describe "merge_with_defaults/1" do
    test "preserves custom profiles and appends missing defaults without duplicates" do
      custom_profile =
        PrinterProfile.new(%{
          id: "profile-custom",
          printer_make_model: "Canon PRO-1000",
          paper_type: "Fine Art",
          ink_type: "OEM pigment"
        })

      [default_profile | _] = PrinterProfile.default_profiles()

      merged =
        PrinterProfile.merge_with_defaults([
          custom_profile,
          default_profile
        ])

      assert Enum.take(merged, 2) == [custom_profile, default_profile]
      assert Enum.count(merged, &(&1.id == custom_profile.id)) == 1
      assert Enum.count(merged, &(&1.id == default_profile.id)) == 1
      assert length(merged) == length(PrinterProfile.default_profiles()) + 1
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
          ink_type: "OEM pigment",
          icc_profile: "P700 Baryta ICC",
          print_settings: "2880 dpi",
          driver_name: "Epson Driver",
          driver_version: "15.4",
          calibration_date: "2026-07-01",
          calibration_version: "baseline-1",
          notes: "Reference profile"
        })

      params = profile |> PrinterProfile.to_query_params() |> Map.new()
      rebuilt = PrinterProfile.from_query_params(params, [])

      assert rebuilt.id == "profile-demo"
      assert rebuilt.printer_make_model == "Epson SureColor P700"
      assert rebuilt.paper_type == "Baryta"
      assert rebuilt.ink_type == "OEM pigment"
      assert rebuilt.icc_profile == "P700 Baryta ICC"
      assert rebuilt.print_settings == "2880 dpi"
      assert rebuilt.driver_name == "Epson Driver"
      assert rebuilt.driver_version == "15.4"
      assert rebuilt.calibration_date == "2026-07-01"
      assert rebuilt.calibration_version == "baseline-1"
      assert rebuilt.notes == nil
    end

    test "query params include enough data to rebuild a custom profile anywhere" do
      profile =
        PrinterProfile.new(%{
          id: "profile-full",
          printer_make_model: "Epson SureColor P900",
          paper_type: "Ultra Premium Luster",
          ink_type: "OEM UltraChrome PRO10",
          icc_profile: "SC-P900 Premium Luster",
          print_settings: "1440 dpi, high quality",
          driver_name: "Epson macOS Driver",
          driver_version: "15.4",
          calibration_date: "2026-07-01",
          calibration_version: "baseline-1",
          notes: "Reference profile"
        })

      params = profile |> PrinterProfile.to_query_params() |> Map.new()

      assert params == %{
               profile_calibration_date: "2026-07-01",
               profile_calibration_version: "baseline-1",
               profile_driver_name: "Epson macOS Driver",
               profile_driver_version: "15.4",
               profile_icc_profile: "SC-P900 Premium Luster",
               profile_id: "profile-full",
               profile_ink_type: "OEM UltraChrome PRO10",
               profile_paper_type: "Ultra Premium Luster",
               profile_print_settings: "1440 dpi, high quality",
               profile_printer_make_model: "Epson SureColor P900"
             }
    end

    test "query params tolerate missing optional string keys" do
      rebuilt =
        PrinterProfile.from_query_params(
          %{
            "profile_id" => "profile-demo",
            "profile_printer_make_model" => "Epson SureColor P700",
            "profile_paper_type" => "Baryta",
            "profile_ink_type" => "OEM pigment"
          },
          []
        )

      assert rebuilt.id == "profile-demo"
      assert rebuilt.printer_make_model == "Epson SureColor P700"
      assert rebuilt.paper_type == "Baryta"
      assert rebuilt.ink_type == "OEM pigment"
      assert rebuilt.icc_profile == nil
      assert rebuilt.print_settings == nil
      assert rebuilt.driver_name == nil
      assert rebuilt.driver_version == nil
      assert rebuilt.calibration_date == nil
      assert rebuilt.calibration_version == nil
      assert rebuilt.notes == nil
    end
  end
end

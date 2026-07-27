defmodule ColorMatchingWeb.IlluminantMeasurementControllerTest do
  use ColorMatchingWeb.ConnCase, async: false

  alias ColorMatching.Persistence

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "POST /api/illuminant_measurements" do
    test "creates one measurement from JSON", %{conn: conn} do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()
      color_id = color.id
      printer_profile_id = printer_profile.id

      response =
        conn
        |> post(~p"/api/illuminant_measurements", %{
          color_id: color_id,
          printer_profile_id: printer_profile_id,
          light_source: "white",
          brightness: 0.91,
          raw_value: 184.2,
          raw_unit: "8-bit grayscale",
          notes: "center patch",
          measured_at: "2026-07-27T12:34:56Z",
          measurement_method: "camera",
          measurement_device: "phone-camera",
          test_run_id: "sheet-2026-07-26-a"
        })
        |> json_response(201)

      assert %{
               "color_id" => ^color_id,
               "printer_profile_id" => ^printer_profile_id,
               "light_source" => "white",
               "brightness" => 0.91,
               "raw_value" => 184.2,
               "raw_unit" => "8-bit grayscale",
               "notes" => "center patch",
               "measured_at" => "2026-07-27T12:34:56Z",
               "measurement_method" => "camera",
               "measurement_device" => "phone-camera",
               "test_run_id" => "sheet-2026-07-26-a"
             } = response["data"]
    end

    test "returns validation errors with API field names", %{conn: conn} do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      response =
        conn
        |> post(~p"/api/illuminant_measurements", %{
          color_id: color.id,
          printer_profile_id: printer_profile.id,
          light_source: "red",
          brightness: 1.2
        })
        |> json_response(422)

      assert response == %{
               "errors" => %{
                 "brightness" => ["must be less than or equal to 1.0"]
               }
             }
    end
  end

  describe "POST /api/illuminant_measurements/bulk" do
    test "bulk creates measurements from shared metadata", %{conn: conn} do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()
      color_id = color.id
      printer_profile_id = printer_profile.id

      response =
        conn
        |> post(~p"/api/illuminant_measurements/bulk", %{
          printer_profile_id: printer_profile_id,
          light_source: "red",
          test_run_id: "sheet-2026-07-26-a",
          measurement_method: "camera",
          measurement_device: "phone-camera",
          measurements: [
            %{
              color_id: color_id,
              brightness: 0.91,
              raw_value: 184.2,
              raw_unit: "8-bit grayscale",
              notes: "center patch"
            },
            %{
              color_id: color_id,
              brightness: 0.88,
              raw_value: 176.1,
              raw_unit: "8-bit grayscale",
              notes: "edge patch"
            }
          ]
        })
        |> json_response(201)

      response_ids = Enum.map(response["data"], & &1["id"])

      assert Enum.count(response["data"]) == 2
      assert response_ids == Enum.uniq(response_ids)
      assert Enum.all?(response["data"], &(&1["color_id"] == color_id))
      assert Enum.all?(response["data"], &(&1["printer_profile_id"] == printer_profile_id))
      assert Enum.all?(response["data"], &(&1["light_source"] == "red"))
      assert Enum.all?(response["data"], &(&1["measurement_method"] == "camera"))
      assert Enum.all?(response["data"], &(&1["measurement_device"] == "phone-camera"))
      assert Enum.all?(response["data"], &(&1["test_run_id"] == "sheet-2026-07-26-a"))

      persisted = Persistence.list_illuminant_measurements(color.id, printer_profile.id)
      assert Enum.count(persisted) == 2
    end

    test "returns row-level errors and does not partially import", %{conn: conn} do
      %{color: color, printer_profile: printer_profile} = persisted_measurement_fixture()

      response =
        conn
        |> post(~p"/api/illuminant_measurements/bulk", %{
          printer_profile_id: printer_profile.id,
          light_source: "blue",
          measurements: [
            %{color_id: color.id, brightness: 0.5},
            %{color_id: 999_999, brightness: 0.7},
            %{color_id: color.id, brightness: -0.1}
          ]
        })
        |> json_response(422)

      assert response == %{
               "errors" => [
                 %{
                   "index" => 1,
                   "color_id" => 999_999,
                   "errors" => %{"color_id" => ["does not exist"]}
                 },
                 %{
                   "index" => 2,
                   "color_id" => color.id,
                   "errors" => %{"brightness" => ["must be greater than or equal to 0.0"]}
                 }
               ]
             }

      assert Persistence.list_illuminant_measurements(color.id, printer_profile.id) == []
    end
  end

  defp persisted_measurement_fixture do
    assert {:ok, palette} =
             Persistence.create_palette(%{
               name: "API Measured Swatches",
               colors: [
                 %{hex_color: "#112233", sort_order: 0, display_label: "Patch 1"}
               ]
             })

    assert {:ok, printer_profile} =
             Persistence.create_printer_profile(%{
               printer_make_model: "Epson SureColor P900",
               paper_type: "Ultra Premium Luster",
               ink_type: "OEM UltraChrome PRO10"
             })

    color = Persistence.get_palette!(palette.id).colors |> List.first()

    %{color: color, printer_profile: printer_profile}
  end
end

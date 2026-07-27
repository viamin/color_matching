defmodule ColorMatching.ResponseVectorTest do
  use ExUnit.Case, async: true

  alias ColorMatching.Persistence.IlluminantMeasurement
  alias ColorMatching.ResponseVector

  @printer_profile_id "profile-test"

  describe "light_sources/0" do
    test "returns the supported illuminant light sources as atoms" do
      assert ResponseVector.light_sources() == [:white, :red, :green, :blue, :lps]
    end
  end

  describe "new/3" do
    test "builds a vector with brightnesses from latest measurements" do
      measurement = measurement_fixture("white", 0.42, ~U[2026-07-27 10:00:00Z])

      vector = ResponseVector.new("#112233", @printer_profile_id, %{"white" => measurement})

      assert vector.hex_color == "#112233"
      assert vector.printer_profile_id == @printer_profile_id
      assert vector.white == 0.42
      assert vector.red == :missing
      assert vector.green == :missing
      assert vector.blue == :missing
      assert vector.lps == :missing
    end

    test "distinguishes zero brightness from missing measurements" do
      zero_measurement = measurement_fixture("white", 0.0, ~U[2026-07-27 10:00:00Z])
      measured_measurement = measurement_fixture("red", 0.5, ~U[2026-07-27 10:00:00Z])

      vector =
        ResponseVector.new("#112233", @printer_profile_id, %{
          "white" => zero_measurement,
          "red" => measured_measurement
        })

      assert vector.white == 0.0
      refute vector.white == :missing
      assert vector.red == 0.5
      assert vector.green == :missing
    end

    test "consumes the latest measurement per light source supplied by the caller" do
      latest_red =
        measurement_fixture("red", 0.55, ~U[2026-07-27 11:00:00Z])

      latest_white =
        measurement_fixture("white", 0.65, ~U[2026-07-27 12:00:00Z])

      vector =
        ResponseVector.new("#112233", @printer_profile_id, %{
          "red" => latest_red,
          "white" => latest_white
        })

      assert vector.red == 0.55
      assert vector.white == 0.65
    end

    test "tracks the most recent measured_at and inserted_at across light sources" do
      green =
        measurement_fixture("green", 0.4, ~U[2026-07-27 10:00:00Z],
          inserted_at: ~U[2026-07-27 09:00:00Z]
        )

      red =
        measurement_fixture("red", 0.5, ~U[2026-07-27 12:00:00Z],
          inserted_at: ~U[2026-07-27 12:00:00Z]
        )

      vector =
        ResponseVector.new("#112233", @printer_profile_id, %{"green" => green, "red" => red})

      assert vector.measured_at == ~U[2026-07-27 12:00:00Z]
      assert vector.inserted_at == ~U[2026-07-27 12:00:00Z]
    end

    test "records missing? when at least one light source is missing a measurement" do
      measurement = measurement_fixture("white", 0.5, ~U[2026-07-27 10:00:00Z])

      vector = ResponseVector.new("#112233", @printer_profile_id, %{"white" => measurement})

      assert vector.missing? == true
    end

    test "records missing? as false when every light source has a measurement" do
      measurements =
        Enum.reduce(ResponseVector.light_sources(), %{}, fn source, acc ->
          key = Atom.to_string(source)
          Map.put(acc, key, measurement_fixture(key, 0.1, ~U[2026-07-27 10:00:00Z]))
        end)

      vector = ResponseVector.new("#112233", @printer_profile_id, measurements)

      assert vector.missing? == false
    end

    test "ignores measurement entries with unknown light sources" do
      measurement = measurement_fixture("white", 0.5, ~U[2026-07-27 10:00:00Z])

      vector =
        ResponseVector.new("#112233", @printer_profile_id, %{
          "white" => measurement,
          "unknown" => measurement_fixture("unknown", 0.99, ~U[2026-07-27 10:00:00Z])
        })

      assert vector.white == 0.5
      assert vector.red == :missing
    end

    test "accepts integer printer profile ids" do
      measurement = measurement_fixture("white", 0.42, ~U[2026-07-27 10:00:00Z])

      vector = ResponseVector.new("#112233", 1, %{"white" => measurement})

      assert vector.printer_profile_id == 1
    end
  end

  describe "value/2 and brightness_map/1" do
    test "look up a single brightness value by light source" do
      measurement = measurement_fixture("lps", 0.6, ~U[2026-07-27 10:00:00Z])

      vector = ResponseVector.new("#112233", @printer_profile_id, %{"lps" => measurement})

      assert ResponseVector.value(vector, :lps) == 0.6
      assert ResponseVector.value(vector, :white) == :missing
    end

    test "returns a map of every supported light source brightness" do
      measurements =
        Enum.reduce(ResponseVector.light_sources(), %{}, fn source, acc ->
          key = Atom.to_string(source)
          Map.put(acc, key, measurement_fixture(key, 0.5, ~U[2026-07-27 10:00:00Z]))
        end)

      vector = ResponseVector.new("#112233", @printer_profile_id, measurements)

      assert ResponseVector.brightness_map(vector) == %{
               white: 0.5,
               red: 0.5,
               green: 0.5,
               blue: 0.5,
               lps: 0.5
             }
    end
  end

  defp measurement_fixture(light_source, normalized_brightness, measured_at, opts \\ []) do
    %IlluminantMeasurement{
      id: :erlang.unique_integer([:positive]),
      light_source: light_source,
      normalized_brightness: normalized_brightness,
      measured_at: measured_at,
      inserted_at: Keyword.get(opts, :inserted_at, measured_at)
    }
  end
end

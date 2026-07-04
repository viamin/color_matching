defmodule ColorMatching.PaletteTest do
  use ExUnit.Case
  alias ColorMatching.Palette

  describe "new/1" do
    test "builds a palette struct with defaults" do
      palette = Palette.new(%{name: "Test", colors: ["#FF0000"]})

      assert palette.name == "Test"
      assert palette.colors == ["#FF0000"]
      assert palette.is_preset == false
      assert palette.created_at == nil
    end

    test "accepts explicit is_preset and created_at" do
      palette =
        Palette.new(%{
          name: "Warm",
          colors: ["#FF0000"],
          is_preset: true,
          created_at: "2026-01-01T00:00:00Z"
        })

      assert palette.is_preset == true
      assert palette.created_at == "2026-01-01T00:00:00Z"
    end
  end

  describe "from_json_map/1" do
    test "builds a palette from string-keyed map" do
      map = %{
        "name" => "Saved",
        "colors" => ["#111111", "#222222"],
        "is_preset" => false,
        "created_at" => "2026-01-01T00:00:00Z"
      }

      assert {:ok, palette} = Palette.from_json_map(map)
      assert palette.name == "Saved"
      assert palette.colors == ["#111111", "#222222"]
      assert palette.is_preset == false
      assert palette.created_at == "2026-01-01T00:00:00Z"
    end

    test "defaults is_preset and created_at when missing" do
      map = %{"name" => "Saved", "colors" => ["#111111"]}

      assert {:ok, palette} = Palette.from_json_map(map)
      assert palette.is_preset == false
      assert palette.created_at == nil
    end

    test "returns error when name is missing" do
      assert {:error, "Missing required fields"} = Palette.from_json_map(%{"colors" => []})
    end

    test "returns error when colors is missing" do
      assert {:error, "Missing required fields"} = Palette.from_json_map(%{"name" => "Test"})
    end

    test "returns error for non-map input" do
      assert {:error, "Missing required fields"} = Palette.from_json_map("not a map")
    end
  end

  describe "to_json_map/1" do
    test "converts a palette struct into a string-keyed map" do
      palette = Palette.new(%{name: "Test", colors: ["#FF0000"], is_preset: true})

      assert Palette.to_json_map(palette) == %{
               "name" => "Test",
               "colors" => ["#FF0000"],
               "is_preset" => true,
               "created_at" => nil
             }
    end
  end

  describe "duplicate/2" do
    test "creates an editable copy with a new name" do
      preset = Palette.new(%{name: "Warm", colors: ["#FF0000", "#00FF00"], is_preset: true})

      copy = Palette.duplicate(preset, "Warm Copy")

      assert copy.name == "Warm Copy"
      assert copy.colors == preset.colors
      assert copy.is_preset == false
      assert is_binary(copy.created_at)
    end
  end

  describe "Jason.Encoder" do
    test "encodes a palette struct to JSON" do
      palette = Palette.new(%{name: "Test", colors: ["#FF0000"], is_preset: false})

      json = Jason.encode!(palette)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["name"] == "Test"
      assert decoded["colors"] == ["#FF0000"]
      assert decoded["is_preset"] == false
    end
  end
end

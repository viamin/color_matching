defmodule ColorMatching.PaletteStorageTest do
  use ExUnit.Case
  alias ColorMatching.PaletteStorage

  describe "get_preset_palettes/0" do
    test "returns all preset palettes with correct structure" do
      palettes = PaletteStorage.get_preset_palettes()
      
      assert is_list(palettes)
      assert length(palettes) == 8
      
      # Check that each palette has the correct structure
      Enum.each(palettes, fn palette ->
        assert Map.has_key?(palette, :name)
        assert Map.has_key?(palette, :colors)
        assert Map.has_key?(palette, :is_preset)
        assert palette.is_preset == true
        assert is_binary(palette.name)
        assert is_list(palette.colors)
      end)
    end

    test "includes expected preset palette names" do
      palettes = PaletteStorage.get_preset_palettes()
      names = Enum.map(palettes, & &1.name)
      
      expected_names = ["Warm", "Cool", "Monochrome", "High Contrast", 
                       "Earth Tones", "Pastels", "Vibrant", "Neon"]
      
      assert Enum.sort(names) == Enum.sort(expected_names)
    end
  end

  describe "get_preset_palette/1" do
    test "returns colors for valid preset palette name" do
      colors = PaletteStorage.get_preset_palette("Warm")
      
      assert is_list(colors)
      assert length(colors) == 10
      assert Enum.all?(colors, &String.starts_with?(&1, "#"))
    end

    test "returns nil for non-existent palette" do
      assert PaletteStorage.get_preset_palette("NonExistent") == nil
    end

    test "returns correct colors for known palettes" do
      warm_colors = PaletteStorage.get_preset_palette("Warm")
      assert "#FF6B6B" in warm_colors
      
      cool_colors = PaletteStorage.get_preset_palette("Cool")
      assert "#74B9FF" in cool_colors
      
      high_contrast = PaletteStorage.get_preset_palette("High Contrast")
      assert "#000000" in high_contrast
      assert "#FFFFFF" in high_contrast
    end
  end

  describe "encode_palette/2" do
    test "encodes palette to valid JSON" do
      name = "Test Palette"
      colors = ["#FF0000", "#00FF00", "#0000FF"]
      
      json = PaletteStorage.encode_palette(name, colors)
      
      assert is_binary(json)
      assert String.contains?(json, "Test Palette")
      assert String.contains?(json, "#FF0000")
    end

    test "encoded palette has correct structure" do
      name = "Custom Colors"
      colors = ["#123456", "#ABCDEF"]
      
      json = PaletteStorage.encode_palette(name, colors)
      {:ok, decoded} = Jason.decode(json)
      
      assert decoded["name"] == name
      assert decoded["colors"] == colors
      assert decoded["is_preset"] == false
    end
  end

  describe "decode_palette/1" do
    test "decodes valid palette JSON" do
      json = ~s({"name":"Test","colors":["#FF0000","#00FF00"],"is_preset":false})
      
      {:ok, palette} = PaletteStorage.decode_palette(json)
      
      assert palette.name == "Test"
      assert palette.colors == ["#FF0000", "#00FF00"]
      assert palette.is_preset == false
    end

    test "handles preset palettes" do
      json = ~s({"name":"Warm","colors":["#FF6B6B"],"is_preset":true})
      
      {:ok, palette} = PaletteStorage.decode_palette(json)
      
      assert palette.is_preset == true
    end

    test "returns error for invalid JSON" do
      invalid_json = "not valid json"
      
      {:error, _reason} = PaletteStorage.decode_palette(invalid_json)
    end

    test "returns error for JSON missing required fields" do
      incomplete_json = ~s({"name":"Test"})
      
      result = PaletteStorage.decode_palette(incomplete_json)
      assert match?({:error, _}, result)
    end
  end

  describe "validate_palette_name/1" do
    test "accepts valid names" do
      assert {:ok, "Valid Name"} = PaletteStorage.validate_palette_name("Valid Name")
      assert {:ok, "Short"} = PaletteStorage.validate_palette_name("Short")
      assert {:ok, "Numbers123"} = PaletteStorage.validate_palette_name("Numbers123")
    end

    test "trims whitespace from names" do
      assert {:ok, "Trimmed"} = PaletteStorage.validate_palette_name("  Trimmed  ")
      assert {:ok, "Leading"} = PaletteStorage.validate_palette_name("   Leading")
      assert {:ok, "Trailing"} = PaletteStorage.validate_palette_name("Trailing   ")
    end

    test "rejects empty names" do
      assert {:error, "Name cannot be empty"} = PaletteStorage.validate_palette_name("")
      assert {:error, "Name cannot be empty"} = PaletteStorage.validate_palette_name("   ")
    end

    test "rejects names that are too long" do
      long_name = String.duplicate("a", 51)
      assert {:error, "Name too long (max 50 characters)"} = PaletteStorage.validate_palette_name(long_name)
    end

    test "rejects names that conflict with presets" do
      assert {:error, "Name conflicts with preset palette"} = PaletteStorage.validate_palette_name("Warm")
      assert {:error, "Name conflicts with preset palette"} = PaletteStorage.validate_palette_name("Cool")
      assert {:error, "Name conflicts with preset palette"} = PaletteStorage.validate_palette_name("Neon")
    end

    test "rejects non-string names" do
      assert {:error, "Name must be a string"} = PaletteStorage.validate_palette_name(123)
      assert {:error, "Name must be a string"} = PaletteStorage.validate_palette_name(nil)
      assert {:error, "Name must be a string"} = PaletteStorage.validate_palette_name(%{})
    end

    test "accepts names exactly at length limit" do
      max_length_name = String.duplicate("a", 50)
      assert {:ok, ^max_length_name} = PaletteStorage.validate_palette_name(max_length_name)
    end
  end

  describe "encode and decode round trip" do
    test "encoding and decoding preserves data" do
      original_name = "Round Trip Test"
      original_colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]
      
      json = PaletteStorage.encode_palette(original_name, original_colors)
      {:ok, decoded} = PaletteStorage.decode_palette(json)
      
      assert decoded.name == original_name
      assert decoded.colors == original_colors
      assert decoded.is_preset == false
    end
  end
end
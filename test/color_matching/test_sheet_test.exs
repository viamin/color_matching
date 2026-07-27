defmodule ColorMatching.TestSheetTest do
  use ColorMatching.DataCase, async: false

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.TestSheet

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_palette(name \\ "Test Palette") do
    {:ok, palette} =
      Persistence.create_palette(%{
        name: name,
        colors: [
          %{hex_color: "#FF0000", sort_order: 0},
          %{hex_color: "#00FF00", sort_order: 1},
          %{hex_color: "#0000FF", sort_order: 2}
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

  defp sheet_attrs(palette, profile, opts \\ []) do
    lookup_code = Keyword.get(opts, :lookup_code, "ABCD-EFGH")

    pairs =
      Keyword.get(opts, :pairs, [
        %{
          pair_id: TestSheet.pair_id(lookup_code, 0, 0),
          row: 0,
          col: 0,
          color_a_hex: "#FF0000",
          color_b_hex: "#FF0000"
        },
        %{
          pair_id: TestSheet.pair_id(lookup_code, 0, 1),
          row: 0,
          col: 1,
          color_a_hex: "#FF0000",
          color_b_hex: "#00FFFF"
        }
      ])

    %{
      lookup_code: lookup_code,
      palette_id: palette.id,
      printer_profile_id: profile.id,
      sheet_version: "lps-letter-grid-v1",
      page_width_mm: 215.9,
      page_height_mm: 279.4,
      page_units: "mm",
      pairs: pairs
    }
  end

  # ---------------------------------------------------------------------------
  # Creation
  # ---------------------------------------------------------------------------

  describe "create_test_sheet/1" do
    test "creates a test sheet with stable lookup code and associated pairs" do
      palette = create_palette()
      profile = create_printer_profile()
      attrs = sheet_attrs(palette, profile, lookup_code: "LPSM-ABCD")

      assert {:ok, sheet} = Persistence.create_test_sheet(attrs)

      assert sheet.lookup_code == "LPSM-ABCD"
      assert sheet.palette_id == palette.id
      assert sheet.printer_profile_id == profile.id
      assert sheet.sheet_version == "lps-letter-grid-v1"
      assert sheet.page_width_mm == 215.9
      assert sheet.page_height_mm == 279.4
      assert sheet.page_units == "mm"
      assert length(sheet.pairs) == 2
      assert Enum.map(sheet.pairs, & &1.pair_id) == [
               TestSheet.pair_id("LPSM-ABCD", 0, 0),
               TestSheet.pair_id("LPSM-ABCD", 0, 1)
             ]
    end

    test "auto-generates lookup code when not provided" do
      palette = create_palette()
      profile = create_printer_profile()

      attrs = %{
        palette_id: palette.id,
        printer_profile_id: profile.id,
        sheet_version: "lps-letter-grid-v1"
      }

      assert {:ok, sheet} = Persistence.create_test_sheet(attrs)
      assert is_binary(sheet.lookup_code)
      assert String.length(sheet.lookup_code) == 9
      # Format: XXXX-XXXX
      assert String.match?(sheet.lookup_code, ~r/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/)
    end

    test "enforces unique lookup codes" do
      palette = create_palette()
      profile = create_printer_profile()
      attrs = sheet_attrs(palette, profile, lookup_code: "DUPL-CATE")

      assert {:ok, _sheet} = Persistence.create_test_sheet(attrs)

      assert {:error, changeset} =
               Persistence.create_test_sheet(
                 sheet_attrs(palette, profile, lookup_code: "DUPL-CATE", pairs: [])
               )

      assert "has already been taken" in errors_on(changeset).lookup_code
    end

    test "requires palette_id, printer_profile_id, and sheet_version" do
      assert {:error, changeset} = Persistence.create_test_sheet(%{})

      errors = errors_on(changeset)
      assert errors[:palette_id]
      assert errors[:printer_profile_id]
      assert errors[:sheet_version]
    end

    test "rejects a lookup_code that does not match XXXX-XXXX unambiguous format" do
      palette = create_palette()
      profile = create_printer_profile()

      for invalid_code <- ["lowercase", "ABCD-123", "ABCD-1234", "ABCD-OOOO", "ABCD-IIII"] do
        attrs = %{
          lookup_code: invalid_code,
          palette_id: palette.id,
          printer_profile_id: profile.id,
          sheet_version: "lps-letter-grid-v1"
        }

        assert {:error, changeset} = Persistence.create_test_sheet(attrs),
               "expected #{inspect(invalid_code)} to be rejected"

        assert errors_on(changeset).lookup_code,
               "expected lookup_code error for #{inspect(invalid_code)}"
      end
    end

    test "validates pair hex color format" do
      palette = create_palette()
      profile = create_printer_profile()

      attrs =
        sheet_attrs(palette, profile,
          pairs: [
            %{
              pair_id: TestSheet.pair_id("ABCD-EFGH", 0, 0),
              row: 0,
              col: 0,
              color_a_hex: "not-a-color",
              color_b_hex: "#FF0000"
            }
          ]
        )

      assert {:error, changeset} = Persistence.create_test_sheet(attrs)
      assert changeset.errors == [] or get_in(errors_on(changeset), [:pairs]) != nil
    end

    test "derives canonical pair_id from lookup_code and coordinates" do
      palette = create_palette()
      profile = create_printer_profile()

      attrs =
        sheet_attrs(palette, profile,
          lookup_code: "PARK-2345",
          pairs: [
            %{
              pair_id: "pair-user-supplied",
              row: 0,
              col: 1,
              color_a_hex: "#FF0000",
              color_b_hex: "#00FFFF"
            }
          ]
        )

      assert {:ok, sheet} = Persistence.create_test_sheet(attrs)

      assert Enum.map(sheet.pairs, & &1.pair_id) == [TestSheet.pair_id("PARK-2345", 0, 1)]
    end
  end

  # ---------------------------------------------------------------------------
  # Lookup
  # ---------------------------------------------------------------------------

  describe "get_test_sheet_by_lookup_code!/1" do
    test "retrieves a sheet by its lookup code with associations preloaded" do
      palette = create_palette()
      profile = create_printer_profile()
      {:ok, _} = Persistence.create_test_sheet(sheet_attrs(palette, profile))

      sheet = Persistence.get_test_sheet_by_lookup_code!("ABCD-EFGH")

      assert sheet.lookup_code == "ABCD-EFGH"
      assert sheet.palette.id == palette.id
      assert sheet.printer_profile.id == profile.id
      assert length(sheet.pairs) == 2
    end

    test "returns pairs in stable row and column order" do
      palette = create_palette()
      profile = create_printer_profile()
      lookup_code = "RDRM-2345"

      {:ok, _} =
        Persistence.create_test_sheet(
          sheet_attrs(palette, profile,
            lookup_code: lookup_code,
            pairs: [
              %{
                pair_id: TestSheet.pair_id(lookup_code, 1, 0),
                row: 1,
                col: 0,
                color_a_hex: "#00FF00",
                color_b_hex: "#FF00FF"
              },
              %{
                pair_id: TestSheet.pair_id(lookup_code, 0, 1),
                row: 0,
                col: 1,
                color_a_hex: "#FF0000",
                color_b_hex: "#00FFFF"
              },
              %{
                pair_id: TestSheet.pair_id(lookup_code, 0, 0),
                row: 0,
                col: 0,
                color_a_hex: "#FF0000",
                color_b_hex: "#FF0000"
              }
            ]
          )
        )

      sheet = Persistence.get_test_sheet_by_lookup_code!(lookup_code)

      assert Enum.map(sheet.pairs, &{&1.row, &1.col}) == [{0, 0}, {0, 1}, {1, 0}]
    end

    test "raises for an unknown lookup code" do
      assert_raise Ecto.NoResultsError, fn ->
        Persistence.get_test_sheet_by_lookup_code!("UNKN-2345")
      end
    end
  end

  describe "get_test_sheet!/1" do
    test "retrieves a sheet by integer id with associations preloaded" do
      palette = create_palette()
      profile = create_printer_profile()
      {:ok, created} = Persistence.create_test_sheet(sheet_attrs(palette, profile))

      sheet = Persistence.get_test_sheet!(created.id)

      assert sheet.id == created.id
      assert sheet.palette.id == palette.id
      assert sheet.printer_profile.id == profile.id
    end
  end

  describe "list_test_sheets/0" do
    test "returns all test sheets ordered by most recently inserted" do
      palette = create_palette("P1")
      profile = create_printer_profile()

      {:ok, first} =
        Persistence.create_test_sheet(sheet_attrs(palette, profile, lookup_code: "AAAA-2222"))

      {:ok, second} =
        Persistence.create_test_sheet(
          sheet_attrs(palette, profile, lookup_code: "BBBB-2222", pairs: [])
        )

      sheets = Persistence.list_test_sheets()
      ids = Enum.map(sheets, & &1.id)

      assert first.id in ids
      assert second.id in ids
      # Most-recently inserted is first
      assert List.first(ids) == second.id
    end
  end

  # ---------------------------------------------------------------------------
  # Palette and printer profile association
  # ---------------------------------------------------------------------------

  describe "palette and printer profile association" do
    test "sheet belongs to the palette it was created with" do
      palette = create_palette()
      profile = create_printer_profile()
      {:ok, _} = Persistence.create_test_sheet(sheet_attrs(palette, profile))

      sheet = Persistence.get_test_sheet_by_lookup_code!("ABCD-EFGH")

      assert sheet.palette.name == "Test Palette"
      assert Enum.map(sheet.palette.colors, & &1.hex_color) == ["#FF0000", "#00FF00", "#0000FF"]
    end

    test "sheet belongs to the printer profile it was created with" do
      palette = create_palette()
      profile = create_printer_profile()
      {:ok, _} = Persistence.create_test_sheet(sheet_attrs(palette, profile))

      sheet = Persistence.get_test_sheet_by_lookup_code!("ABCD-EFGH")

      assert sheet.printer_profile.printer_make_model == "Epson SureColor P900"
    end
  end

  # ---------------------------------------------------------------------------
  # Stable pair identity
  # ---------------------------------------------------------------------------

  describe "stable pair identity" do
    test "pair_id/3 is deterministic for the same inputs" do
      id1 = TestSheet.pair_id("LPSM-TEST", 0, 1)
      id2 = TestSheet.pair_id("LPSM-TEST", 0, 1)

      assert id1 == id2
      assert String.starts_with?(id1, "pair-")
      assert String.length(id1) == 17
    end

    test "pair_id/3 differs for different positions" do
      id_00 = TestSheet.pair_id("LPSM-TEST", 0, 0)
      id_01 = TestSheet.pair_id("LPSM-TEST", 0, 1)
      id_10 = TestSheet.pair_id("LPSM-TEST", 1, 0)

      assert id_00 != id_01
      assert id_00 != id_10
      assert id_01 != id_10
    end

    test "pair_id/3 differs for different lookup codes" do
      id_a = TestSheet.pair_id("AAAA-2222", 0, 0)
      id_b = TestSheet.pair_id("BBBB-2222", 0, 0)

      assert id_a != id_b
    end

    test "persisted pairs carry stable pair_ids that survive a round-trip" do
      palette = create_palette()
      profile = create_printer_profile()
      lookup_code = "STBL-2345"

      expected_pair_id = TestSheet.pair_id(lookup_code, 0, 1)

      {:ok, _} =
        Persistence.create_test_sheet(
          sheet_attrs(palette, profile,
            lookup_code: lookup_code,
            pairs: [
              %{
                pair_id: expected_pair_id,
                row: 0,
                col: 1,
                color_a_hex: "#FF0000",
                color_b_hex: "#00FFFF"
              }
            ]
          )
        )

      sheet = Persistence.get_test_sheet_by_lookup_code!(lookup_code)
      pair = List.first(sheet.pairs)

      assert pair.pair_id == expected_pair_id
      assert pair.row == 0
      assert pair.col == 1
      assert pair.color_a_hex == "#FF0000"
      assert pair.color_b_hex == "#00FFFF"
    end

    test "pair_ids are globally unique across different sheets" do
      palette = create_palette()
      profile = create_printer_profile()

      pairs_a = [
        %{
          pair_id: TestSheet.pair_id("AAAA-2222", 0, 0),
          row: 0,
          col: 0,
          color_a_hex: "#FF0000",
          color_b_hex: "#FF0000"
        }
      ]

      pairs_b = [
        %{
          pair_id: TestSheet.pair_id("BBBB-2222", 0, 0),
          row: 0,
          col: 0,
          color_a_hex: "#00FF00",
          color_b_hex: "#00FF00"
        }
      ]

      assert {:ok, sheet_a} =
               Persistence.create_test_sheet(
                 sheet_attrs(palette, profile, lookup_code: "AAAA-2222", pairs: pairs_a)
               )

      assert {:ok, sheet_b} =
               Persistence.create_test_sheet(
                 sheet_attrs(palette, profile, lookup_code: "BBBB-2222", pairs: pairs_b)
               )

      pair_a_id = sheet_a.pairs |> List.first() |> Map.get(:pair_id)
      pair_b_id = sheet_b.pairs |> List.first() |> Map.get(:pair_id)

      assert pair_a_id != pair_b_id
    end
  end

  # ---------------------------------------------------------------------------
  # generate_lookup_code/0
  # ---------------------------------------------------------------------------

  describe "generate_lookup_code/0" do
    test "produces codes in XXXX-XXXX format" do
      code = TestSheet.generate_lookup_code()

      assert String.match?(code, ~r/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/)
    end

    test "produces distinct codes on repeated calls" do
      codes = for _ <- 1..20, do: TestSheet.generate_lookup_code()

      assert length(Enum.uniq(codes)) == 20
    end
  end
end

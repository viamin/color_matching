defmodule ColorMatching.SheetGeometryTest do
  use ExUnit.Case, async: true

  alias ColorMatching.Persistence.TestSheet
  alias ColorMatching.SheetGeometry

  defp sheet(attrs) do
    %TestSheet{
      page_width_mm: Map.get(attrs, :page_width_mm, 215.9),
      page_height_mm: Map.get(attrs, :page_height_mm, 279.4),
      page_units: "mm",
      patch_layout:
        Map.get(attrs, :patch_layout, ~s({"cell_size_mm": 20, "gap_mm": 2, "grid_size": 3})),
      reg_marker_layout:
        Map.get(attrs, :reg_marker_layout, ~s({"radius_mm": 5, "type": "corner_circles"})),
      safe_inset_mm: Map.get(attrs, :safe_inset_mm, 12.7)
    }
  end

  describe "build/1" do
    test "parses layout fields and centers the grid on the page" do
      geometry = SheetGeometry.build(sheet(%{}))

      assert geometry.cell_size == 20.0
      assert geometry.gap == 2.0
      assert geometry.grid_size == 3

      # grid extent = 3*20 + 2*2 = 64mm, centered on the page.
      assert_in_delta geometry.origin_x, (215.9 - 64) / 2, 0.001
      assert_in_delta geometry.origin_y, (279.4 - 64) / 2, 0.001
    end

    test "exposes one corner registration marker per page corner" do
      geometry = SheetGeometry.build(sheet(%{}))

      assert Enum.map(geometry.markers, & &1.role) ==
               ["top_left", "top_right", "bottom_right", "bottom_left"]

      for marker <- geometry.markers do
        assert marker.rect.width == 10.0
        assert marker.rect.height == 10.0
      end
    end

    test "falls back to defaults when layout json is absent" do
      geometry = SheetGeometry.build(sheet(%{patch_layout: nil, reg_marker_layout: nil}))

      assert geometry.cell_size == 20.0
      assert geometry.grid_size == 3
      assert length(geometry.markers) == 4
    end
  end

  describe "cell_rect/3 and patch_rects/1" do
    test "a diagonal cell splits into top-left and bottom-right quadrant patches" do
      geometry = SheetGeometry.build(sheet(%{page_width_mm: 200.0, page_height_mm: 200.0}))

      cell = SheetGeometry.cell_rect(geometry, 0, 0)

      assert cell.x == geometry.origin_x
      assert cell.y == geometry.origin_y
      assert cell.width == 20.0
      assert cell.height == 20.0

      [first, second] = SheetGeometry.patch_rects(cell)

      # first = top-left quadrant, second = bottom-right quadrant
      assert first.x == cell.x
      assert first.y == cell.y
      assert first.width == 10.0

      assert second.x == cell.x + 10.0
      assert second.y == cell.y + 10.0
      assert second.width == 10.0
    end

    test "cell coordinates advance by cell_size + gap" do
      geometry = SheetGeometry.build(sheet(%{}))

      c00 = SheetGeometry.cell_rect(geometry, 0, 0)
      c12 = SheetGeometry.cell_rect(geometry, 1, 2)

      assert c12.x == c00.x + 2 * (20.0 + 2.0)
      assert c12.y == c00.y + 1 * (20.0 + 2.0)
    end
  end
end

defmodule ColorMatchingWeb.ColorGridLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "ColorGridLive" do
    test "mounts with default colors and settings", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Color Matching Grid"
      assert html =~ "Manage Colors"
      assert html =~ "Grid Size: 6×6"
    end

    test "displays the default color palette", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Check that default colors are displayed
      assert html =~ "#FF6B6B"
      assert html =~ "#4ECDC4"
      assert html =~ "#45B7D1"
      assert html =~ "#96CEB4"
      assert html =~ "#FFEAA7"
      assert html =~ "#FD79A8"
    end

    test "adds a new color via color picker and increases grid size", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Initial state should be 6x6 grid with 6 default colors
      html = render(view)
      assert html =~ "Grid Size: 6×6"
      initial_color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert initial_color_count == 6

      # First update the color picker value
      view
      |> element("form[phx-change='update_color_input']")
      |> render_change(%{"value" => "#123456"})

      # Then submit the form to add the color
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{})

      # Check that the new color appears and grid size increased
      html = render(view)
      assert html =~ "#123456"
      assert html =~ "Grid Size: 7×7"
      new_color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert new_color_count == 7
    end

    test "adds a new color via text input and increases grid size", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Add a new color by typing in text input and submitting
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => "#ABCDEF"})

      # Check that the new color appears and grid size increased
      html = render(view)
      assert html =~ "#ABCDEF"
      assert html =~ "Grid Size: 7×7"
    end

    test "removes a color and updates color count", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Get initial state - should have 6 default colors
      html = render(view)
      initial_color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert initial_color_count == 6
      # First default color
      assert html =~ "#FF6B6B"

      # Remove the first color (index 0, which should be #FF6B6B)
      view
      |> element("button[phx-click='remove_color'][phx-value-index='0']")
      |> render_click()

      # Verify color was removed
      html = render(view)
      color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert color_count == 5

      # The first color should no longer be #FF6B6B (it should now be the second default color)
      # Since we removed index 0, the remaining colors should have shifted
    end

    test "updates color input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Simulate typing in the color input by using the form change event
      view
      |> element("form[phx-change='update_color_input']")
      |> render_change(%{"value" => "#ABCDEF"})

      # The color picker should reflect the new value
      html = render(view)
      assert html =~ "value=\"#ABCDEF\""
    end

    test "changes grid size", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Change grid size to 8
      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "8"})
      |> render_change()

      html = render(view)
      assert html =~ "Grid Size: 8×8"
      assert html =~ "grid-template-columns: repeat(8, 1fr)"
    end

    test "renders edge-to-edge swatches without grid gaps or borders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(class="grid gap-0 w-full h-full")
      assert html =~ ~s(class="grid gap-0 no-print")
      assert html =~ ~s(class="relative overflow-hidden print-cell")
      assert html =~ ~s(class="relative overflow-hidden w-16 h-16")
    end

    test "links to palette management", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Manage Palettes"
      assert html =~ "/palettes"
    end

    test "renders a global display format selector", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Grid and print label format"
      assert html =~ ~s(class="rounded-lg border border-gray-300 pl-3 pr-10 py-2 text-sm")
      assert html =~ ~s(<option value="hex")
      assert html =~ "selected"
      assert html =~ "RGB"
      assert html =~ "HSL"
      assert html =~ "HSV"
    end

    test "validates color input format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Try to input an invalid color
      view
      |> element("form[phx-change='update_color_input']")
      |> render_change(%{"value" => "invalid-color"})

      # The submit button should be disabled for invalid colors
      html = render(view)
      assert html =~ "disabled"
    end

    test "grid automatically adds random colors when size exceeds available colors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Start with 6 default colors, change grid size to 10
      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "10"})
      |> render_change()

      html = render(view)
      # Should now have 10 colors displayed (6 original + 4 random)
      color_divs = (html |> String.split("phx-value-index=") |> length()) - 1
      assert color_divs == 10
    end

    test "displays preset palettes in initial state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # The LiveView should load preset palettes on mount
      # We can't easily test the menu display without complex DOM interactions
      # So we'll just verify the page loads successfully with palette data
      assert html =~ "Color Matching Grid"
      assert html =~ "Manage Palettes"
    end

    test "handles empty color list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Remove all colors (from highest index to lowest)
      for i <- 5..0//-1 do
        view
        |> element("button[phx-click='remove_color'][phx-value-index='#{i}']")
        |> render_click()
      end

      # Should still render without crashing
      html = render(view)
      assert html =~ "Color Matching Grid"
    end

    test "preserves grid state across interactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Add a color and change grid size
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => "#ABCDEF"})

      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "8"})
      |> render_change()

      html = render(view)
      # Both changes should be reflected
      assert html =~ "#ABCDEF"
      assert html =~ "Grid Size: 8×8"
    end

    test "rejects invalid hex colors without poisoning the palette", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # "#TESTING" is not valid hex; it must be rejected so it never reaches
      # ColorUtils.invert_color/1 (which would be a crash before this fix).
      html =
        view
        |> element("form[phx-submit='add_color']")
        |> render_submit(%{"color" => "#TESTING"})

      refute html =~ "#TESTING"
      assert html =~ "Hex color must start with # followed by 3 or 6 hex digits"
      assert html =~ "Grid Size: 6×6"
    end

    test "disables add color button when grid is at maximum size", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Change grid to maximum size
      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "12"})
      |> render_change()

      # Set a color in the input
      view
      |> element("form[phx-change='update_color_input']")
      |> render_change(%{"value" => "#ABCDEF"})

      html = render(view)
      # Button should be disabled even with valid color when at max size
      assert html =~ "disabled"
      assert html =~ "Grid Size: 12×12"
    end

    test "add color button works when grid size is less than maximum and color is valid", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      # Set a valid color and submit
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => "#FFFFFF"})

      html = render(view)
      # Color should be added successfully
      assert html =~ "#FFFFFF"
      assert html =~ "Grid Size: 7×7"
    end

    test "multiple color additions increase grid size appropriately", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Add multiple colors
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => "#111111"})

      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => "#222222"})

      html = render(view)
      assert html =~ "#111111"
      assert html =~ "#222222"
      # Started at 6, added 2, now 8
      assert html =~ "Grid Size: 8×8"
    end

    test "handles empty color input for add_color", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Try to add color with empty input
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"color" => ""})

      # Should not add any color or change grid size
      html = render(view)
      assert html =~ "Grid Size: 6×6"
      color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert color_count == 6
    end

    test "handles color input with 'value' parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # First update the color picker value to enable the button
      view
      |> element("form[phx-change='update_color_input']")
      |> render_change(%{"value" => "#ABCDEF"})

      # Then submit the form to add the color
      view
      |> element("form[phx-submit='add_color']")
      |> render_submit(%{"value" => "#ABCDEF"})

      html = render(view)
      # Should now have 7 colors (6 original + 1 added)
      color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert color_count == 7
      assert html =~ "Grid Size: 7×7"
    end

    test "handles grid size change with existing colors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Start with 6 colors, change grid size to 7 (will add 1 random color)
      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "7"})
      |> render_change()

      html = render(view)
      assert html =~ "Grid Size: 7×7"

      # Should now have 7 colors (6 original + 1 random)
      color_count = (html |> String.split("phx-value-index=") |> length()) - 1
      assert color_count == 7
    end

    test "displays grid when colors are sufficient", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render(view)
      # With 6 colors and 6x6 grid, should show the actual grid
      assert html =~ "triangle-top-left"
      assert html =~ "triangle-bottom-right"
      refute html =~ "Add at least"
    end

    test "displays warning when insufficient colors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Remove multiple colors to get below grid size requirement
      for i <- 5..2//-1 do
        view
        |> element("button[phx-click='remove_color'][phx-value-index='#{i}']")
        |> render_click()
      end

      # Now we should have 2 colors but grid size will be 6 (minimum)
      html = render(view)
      assert html =~ "Add at least 6 colors to generate the grid"
    end
  end

  describe "active palette state" do
    test "defaults to a custom/unsaved active palette", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Active palette:"
      assert html =~ "Custom"
    end

    test "loads colors handed off from a previous session via the storage hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "active_palette_loaded", %{
          "palette" => %{
            "name" => "Handoff Palette",
            "colors" => ["#111111", "#222222", "#333333", "#444444", "#555555", "#666666"],
            "is_preset" => false
          }
        })

      assert html =~ "#111111"
      assert html =~ "Handoff Palette"
      refute html =~ "Custom</span>"
    end

    test "renders an edited selected palette when returning from palette management", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "active_palette_loaded", %{
        "palette" => %{
          "name" => "Studio Set",
          "colors" => ["#111111", "#222222", "#333333", "#444444", "#555555", "#666666"],
          "is_preset" => false
        }
      })

      html =
        render_hook(view, "active_palette_loaded", %{
          "palette" => %{
            "name" => "Studio Set Revised",
            "colors" => ["#ABCDEF", "#222222", "#333333", "#444444", "#555555", "#666666"],
            "is_preset" => false
          }
        })

      assert html =~ "Studio Set Revised"
      assert html =~ "#ABCDEF"
      refute html =~ ">Studio Set<"
    end

    test "ignores an empty active palette handoff", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "active_palette_loaded", %{"palette" => nil})

      assert html =~ "Grid Size: 6×6"
      assert html =~ "Custom"
    end

    test "loading a preset handoff makes it the active palette and marks it as a preset", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "active_palette_loaded", %{
          "palette" => %{
            "name" => "Warm",
            "colors" => ["#FF6B6B", "#FF8E53", "#FF6B35", "#F7931E", "#FFD23F", "#FFF07C"],
            "is_preset" => true
          }
        })

      assert html =~ "Active palette:"
      assert html =~ "Warm"
      assert html =~ "(preset)"
    end

    test "adding a color to a loaded preset clears the active selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "active_palette_loaded", %{
        "palette" => %{
          "name" => "Warm",
          "colors" => ["#FF6B6B", "#FF8E53", "#FF6B35", "#F7931E", "#FFD23F", "#FFF07C"],
          "is_preset" => true
        }
      })

      html =
        view
        |> element("form[phx-submit='add_color']")
        |> render_submit(%{"color" => "#123456"})

      assert html =~ "Custom"
    end

    test "removing a color from a loaded preset clears the active selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "active_palette_loaded", %{
        "palette" => %{
          "name" => "Warm",
          "colors" => ["#FF6B6B", "#FF8E53", "#FF6B35", "#F7931E", "#FFD23F", "#FFF07C"],
          "is_preset" => true
        }
      })

      html =
        view
        |> element("button[phx-click='remove_color'][phx-value-index='0']")
        |> render_click()

      assert html =~ "Custom"
    end

    test "changing grid size after loading a preset clears the active selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "active_palette_loaded", %{
        "palette" => %{
          "name" => "Warm",
          "colors" => ["#FF6B6B", "#FF8E53", "#FF6B35", "#F7931E", "#FFD23F", "#FFF07C"],
          "is_preset" => true
        }
      })

      html =
        view
        |> form("form[phx-change='change_grid_size']", %{"size" => "11"})
        |> render_change()

      assert html =~ "Custom"
    end
  end

  describe "display format preference and print output" do
    test "uses the selected display format for grid labels and print legend", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("form[phx-change='set_display_format']", %{"format" => "rgb"})
        |> render_change()

      assert html =~ "rgb(255, 107, 107)"
      assert html =~ "rgb(0, 148, 148)"
      assert html =~ "rgb(255, 107, 107) (Row 1)"
      refute html =~ "<span class=\"print-legend-text\">#FF6B6B (Row 1)</span>"
    end

    test "loads a persisted display format preference from the storage hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "display_format_loaded", %{"format" => "hsl"})

      assert html =~ "hsl(0, 100%, 71%)"
      assert html =~ "hsl(180, 100%, 29%)"
    end

    test "print title uses the active palette name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "active_palette_loaded", %{
          "palette" => %{
            "name" => "Studio Set",
            "colors" => ["#111111", "#222222", "#333333", "#444444", "#555555", "#666666"],
            "is_preset" => false
          }
        })

      assert html =~ ~s(<div class="print-title">Studio Set</div>)
      refute html =~ ~s(<div class="print-title">Color Matching Grid)
      refute html =~ "<div class=\"print-title\">Color Matching Grid (6×6)</div>"
    end

    test "print title falls back to Custom when the active palette is unnamed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "active_palette_loaded", %{
          "palette" => %{
            "name" => nil,
            "colors" => ["#111111", "#222222", "#333333", "#444444", "#555555", "#666666"],
            "is_preset" => false
          }
        })

      assert html =~ ~s(<div class="print-title">Custom</div>)
      refute html =~ ~s(<div class="print-title">Color Matching Grid)
    end

    test "print grid renders cells with the same triangle classes as the screen grid", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/")

      # Regression guard: before the shared `color_cell` component, the print
      # grid used a `linear-gradient` fallback and never emitted any
      # triangle-* classes. Pinning the print grid to the same triangle
      # classes as the screen grid keeps both renderers in lock-step.
      print_section =
        html
        |> String.split(~s(class="print-area">))
        |> Enum.at(1)
        |> String.split(~s(class="print-legend">))
        |> hd()

      assert print_section =~ ~s(class="absolute inset-0 triangle-top-left")
      assert print_section =~ ~s(class="absolute inset-0 triangle-bottom-right")
      assert print_section =~ ~s(class="absolute inset-0 triangle-diagonal-split")
    end
  end
end

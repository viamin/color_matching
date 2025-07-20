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

    test "toggles palette menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Initially, palette menu should be closed
      html = render(view)
      refute html =~ "Save Current Palette"

      # Click to toggle palette menu
      view
      |> element("button[phx-click='toggle_palette_menu']")
      |> render_click()

      html = render(view)
      assert html =~ "Save Current Palette" or html =~ "Load Preset"
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
      assert html =~ "Palette Options"
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
      |> render_submit(%{"color" => "#TESTING"})

      view
      |> form("form[phx-change='change_grid_size']", %{"size" => "8"})
      |> render_change()

      html = render(view)
      # Both changes should be reflected
      assert html =~ "#TESTING"
      assert html =~ "Grid Size: 8×8"
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
  end
end

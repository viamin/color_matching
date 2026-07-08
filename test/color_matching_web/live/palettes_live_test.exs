defmodule ColorMatchingWeb.PalettesLiveTest do
  use ColorMatchingWeb.ConnCase
  import Phoenix.LiveViewTest

  alias ColorMatching.PaletteStorage

  describe "/palettes" do
    test "renders preset palettes, saved palettes, and a path back to the grid", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/palettes")

      assert html =~ "Palette Management"
      assert html =~ "Preset Palettes"
      assert html =~ "Your Palettes"
      assert html =~ "Return to Grid"

      html =
        render_hook(view, "palettes_updated", %{
          "palettes" => [
            %{
              "name" => "Studio Set",
              "colors" => ["#111111", "#222222", "#333333"],
              "is_preset" => false,
              "created_at" => "2026-07-08T00:00:00Z"
            }
          ]
        })

      assert html =~ "Studio Set"
      assert html =~ "Use in Grid"
    end

    test "duplicates a preset into an editable user palette", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      warm = Enum.find(PaletteStorage.get_preset_palettes(), &(&1.name == "Warm"))

      html = render_click(view, "duplicate_palette", %{"palette" => Jason.encode!(warm)})

      assert html =~ "Warm Copy"
      assert html =~ "Palette Editor"
      assert html =~ "Duplicated"
      assert html =~ "Rename"
    end

    test "editing hex updates the same color across all displayed formats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      palette = %{
        "name" => "Studio Set",
        "colors" => ["#111111", "#222222", "#333333"],
        "is_preset" => false,
        "created_at" => "2026-07-08T00:00:00Z"
      }

      render_hook(view, "palettes_updated", %{"palettes" => [palette]})
      render_click(view, "open_palette", %{"palette" => Jason.encode!(palette)})

      view
      |> element("input[phx-value-index='0'][phx-value-format='hex']")
      |> render_change(%{"value" => "#123456"})

      html = render_click(view, "apply_color_format", %{"index" => "0", "format" => "hex"})

      assert html =~ "#123456"
      assert html =~ "rgb(18, 52, 86)"
      assert html =~ "hsl(210, 65%, 20%)"
      assert html =~ "hsv(210, 79%, 34%)"
    end

    test "editing rgb updates the canonical hex value", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      palette = %{
        "name" => "Studio Set",
        "colors" => ["#111111", "#222222", "#333333"],
        "is_preset" => false,
        "created_at" => "2026-07-08T00:00:00Z"
      }

      render_hook(view, "palettes_updated", %{"palettes" => [palette]})
      render_click(view, "open_palette", %{"palette" => Jason.encode!(palette)})

      view
      |> element("input[phx-value-index='0'][phx-value-format='rgb']")
      |> render_change(%{"value" => "rgb(171, 205, 239)"})

      html = render_click(view, "apply_color_format", %{"index" => "0", "format" => "rgb"})

      assert html =~ "#ABCDEF"
      assert html =~ "rgb(171, 205, 239)"
    end

    test "editing hsl and hsv both update the shared color", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      palette = %{
        "name" => "Studio Set",
        "colors" => ["#111111", "#222222", "#333333"],
        "is_preset" => false,
        "created_at" => "2026-07-08T00:00:00Z"
      }

      render_hook(view, "palettes_updated", %{"palettes" => [palette]})
      render_click(view, "open_palette", %{"palette" => Jason.encode!(palette)})

      view
      |> element("input[phx-value-index='1'][phx-value-format='hsl']")
      |> render_change(%{"value" => "hsl(120, 100%, 50%)"})

      html = render_click(view, "apply_color_format", %{"index" => "1", "format" => "hsl"})

      assert html =~ "#00FF00"
      assert html =~ "hsl(120, 100%, 50%)"

      view
      |> element("input[phx-value-index='1'][phx-value-format='hsv']")
      |> render_change(%{"value" => "hsv(240, 100%, 100%)"})

      html = render_click(view, "apply_color_format", %{"index" => "1", "format" => "hsv"})

      assert html =~ "#0000FF"
      assert html =~ "hsv(240, 100%, 100%)"
    end

    test "invalid color input shows a clear validation error without changing the palette", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      palette = %{
        "name" => "Studio Set",
        "colors" => ["#111111", "#222222", "#333333"],
        "is_preset" => false,
        "created_at" => "2026-07-08T00:00:00Z"
      }

      render_hook(view, "palettes_updated", %{"palettes" => [palette]})
      render_click(view, "open_palette", %{"palette" => Jason.encode!(palette)})

      view
      |> element("input[phx-value-index='0'][phx-value-format='rgb']")
      |> render_change(%{"value" => "rgb(999, 0, 0)"})

      html = render_click(view, "apply_color_format", %{"index" => "0", "format" => "rgb"})

      assert html =~ "RGB values must be between 0 and 255"
      assert html =~ "#111111"
      refute html =~ "#FF0000"
    end

    test "use in grid marks the palette as the active grid selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/palettes")

      palette = %{
        "name" => "Studio Set",
        "colors" => ["#111111", "#222222", "#333333"],
        "is_preset" => false,
        "created_at" => "2026-07-08T00:00:00Z"
      }

      render_hook(view, "palettes_updated", %{"palettes" => [palette]})

      html = render_click(view, "use_palette", %{"palette" => Jason.encode!(palette)})

      assert html =~ "Grid selection:"
      assert html =~ "Studio Set"
      assert html =~ "ready for the grid"
    end
  end
end

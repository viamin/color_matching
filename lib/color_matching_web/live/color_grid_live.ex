defmodule ColorMatchingWeb.ColorGridLive do
  use ColorMatchingWeb, :live_view
  alias ColorMatching.{ColorFormat, ColorUtils, Grid}

  @default_colors ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#FD79A8"]
  # Lower bound for grid_size; matches the `min` attribute on the grid-size
  # range input. All paths that derive grid_size from a color count must clamp
  # to this so reloads/loads cannot shrink the grid below what the UI allows.
  @min_grid_size 6
  # Upper bound for grid_size and palette length. The grid-size range input
  # caps at this value, and `ColorMatchingWeb.PalettesLive` rejects adding
  # more colors once a palette reaches this count so "Use in Grid" never
  # hands the grid a palette whose colors it cannot represent.
  @max_grid_colors 12

  def mount(_params, _session, socket) do
    # NOTE: intentionally do not `push_active_palette/1` here. On a hard
    # refresh the PaletteStorage hook hydrates the saved palette from
    # localStorage and pushes it back via `active_palette_loaded`. Pushing
    # `activate_palette` now (with the default colors) would race that
    # hydration and overwrite the saved palette. Only re-persist on real user
    # changes (add/remove/save/load/etc.).
    {:ok,
     socket
     |> assign(:colors, @default_colors)
     |> assign(:grid_size, @min_grid_size)
     |> assign(:new_color, "")
     |> assign(:active_palette, nil)
     |> assign(:display_format, ColorFormat.default_display_format())
     |> assign(:display_formats, ColorFormat.display_formats())
     |> assign(:max_grid_colors, @max_grid_colors)
     |> assign_grid()}
  end

  def handle_event("add_color", params, socket) do
    # Get color from either 'color' or 'value' parameter
    color = params["color"] || params["value"] || socket.assigns.new_color

    if color && color != "" do
      current_size = socket.assigns.grid_size
      max_size = @max_grid_colors
      colors = socket.assigns.colors ++ [color]
      new_size = min(max(length(colors), current_size + 1), max_size)

      {:noreply,
       socket
       |> assign(:colors, colors)
       |> assign(:grid_size, new_size)
       |> assign(:new_color, "")
       |> assign(:active_palette, nil)
       |> assign_grid()
       |> push_active_palette()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_color", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    colors = List.delete_at(socket.assigns.colors, index)

    {:noreply,
     socket
     |> assign(:colors, colors)
     |> assign(:grid_size, grid_size_for_colors(colors))
     |> assign(:active_palette, nil)
     |> assign_grid()
     |> push_active_palette()}
  end

  def handle_event("update_color_input", params, socket) do
    # Get color from either input
    color = params["value"] || params["color"] || ""
    {:noreply, assign(socket, :new_color, color)}
  end

  def handle_event("change_grid_size", %{"size" => size_str}, socket) do
    new_size = String.to_integer(size_str)
    old_size = socket.assigns.grid_size
    current_colors = socket.assigns.colors

    updated_colors =
      if new_size > old_size and length(current_colors) < new_size do
        # Add random colors to fill the new grid size
        colors_needed = new_size - length(current_colors)
        new_random_colors = for _ <- 1..colors_needed, do: ColorUtils.random_color()
        current_colors ++ new_random_colors
      else
        current_colors
      end

    {:noreply,
     socket
     |> assign(:grid_size, new_size)
     |> assign(:colors, updated_colors)
     |> assign(:active_palette, nil)
     |> assign_grid()
     |> push_active_palette()}
  end

  def handle_event("palettes_updated", _params, socket), do: {:noreply, socket}

  def handle_event("set_display_format", %{"format" => format}, socket) do
    with {:ok, display_format} <- ColorFormat.normalize_display_format(format) do
      {:noreply,
       socket
       |> assign(:display_format, display_format)
       |> push_event("set_display_format_preference", %{format: Atom.to_string(display_format)})}
    else
      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("display_format_loaded", %{"format" => format}, socket) do
    with {:ok, display_format} <- ColorFormat.normalize_display_format(format) do
      {:noreply, assign(socket, :display_format, display_format)}
    else
      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("display_format_loaded", _params, socket), do: {:noreply, socket}

  def handle_event(
        "active_palette_loaded",
        %{"palette" => %{"colors" => colors} = palette_map},
        socket
      )
      when is_list(colors) and colors != [] do
    name = Map.get(palette_map, "name")
    is_preset = Map.get(palette_map, "is_preset", false)

    {:noreply,
     socket
     |> assign(:colors, colors)
     |> assign(:grid_size, grid_size_for_colors(colors))
     |> assign(:active_palette, name && %{name: name, is_preset: is_preset})
     |> assign_grid()}
  end

  def handle_event("active_palette_loaded", _params, socket), do: {:noreply, socket}

  defp assign_grid(socket) do
    grid = Grid.new(socket.assigns.colors, socket.assigns.grid_size)
    assign(socket, :grid, grid)
  end

  # Derives a grid size from a color count, clamped to the app minimum.
  defp grid_size_for_colors(colors) do
    max(length(colors), @min_grid_size)
  end

  # Persists the currently active palette (name + colors) to localStorage via
  # the PaletteStorage hook, so any other page/reload can pick up the same
  # in-progress selection. See ColorMatching.PaletteStorage moduledoc for the
  # full explanation of this handoff.
  defp push_active_palette(socket) do
    active = socket.assigns.active_palette

    push_event(socket, "activate_palette", %{
      name: active && active.name,
      colors: socket.assigns.colors,
      is_preset: (active && active.is_preset) || false
    })
  end

  defp active_palette_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp active_palette_label(_active_palette), do: "Custom"

  defp display_format_label(format), do: format |> Atom.to_string() |> String.upcase()

  defp format_color_label(color, display_format) do
    case ColorFormat.format_color(color, display_format) do
      {:ok, formatted} -> formatted
      {:error, _reason} -> color
    end
  end

  def render(assigns) do
    ~H"""
    <div
      class="max-w-6xl mx-auto p-6"
      phx-hook="PaletteStorage"
      id="palette-storage"
      data-load-display-format="true"
    >
      <h1 class="text-3xl font-bold text-gray-900 mb-4 no-print">Color Matching Grid</h1>
      <p class="text-gray-600 mb-8 no-print">
        This grid shows all unique color combinations from your palette, split by the main diagonal:
      </p>
      <div class="mb-6 text-sm text-gray-600 bg-blue-50 p-4 rounded-lg no-print">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <h3 class="font-semibold text-blue-800 mb-2">Below Main Diagonal (\)</h3>
            <p>Top-left triangle: Palette color by row</p>
            <p>Bottom-right triangle: Palette color by column</p>
            <p class="text-xs mt-1 italic">Shows original color combinations</p>
          </div>
          <div>
            <h3 class="font-semibold text-blue-800 mb-2">Above Main Diagonal (\)</h3>
            <p>Top-left triangle: Palette color by row</p>
            <p>Bottom-right triangle: <strong>Inverted</strong> color by column</p>
            <p class="text-xs mt-1 italic">Shows high-contrast combinations for maximum difference</p>
          </div>
        </div>
        <div class="mt-3 pt-3 border-t border-blue-200">
          <p class="text-xs">
            <strong>On the diagonal:</strong>
            Squares show the same color split—original below the diagonal, inverted above.
          </p>
        </div>
      </div>

      <!-- Color Management -->
      <div class="mb-8 p-4 bg-gray-50 rounded-lg no-print">
        <div class="flex justify-between items-center mb-4">
          <div>
            <h2 class="text-xl font-semibold">Manage Colors</h2>
            <p class="text-xs text-gray-500 mt-1">
              Active palette:
              <%= if @active_palette do %>
                <span class="font-medium">{active_palette_label(@active_palette)}</span>
                <%= if @active_palette.is_preset do %>
                  (preset)
                <% end %>
              <% else %>
                <span class="italic">Custom</span>
              <% end %>
            </p>
          </div>
          <.link
            navigate={~p"/palettes"}
            class="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-white"
          >
            Manage Palettes
          </.link>
        </div>

        <p class="text-sm text-gray-600 mb-3">
          The palette editor still exposes every format. This preference controls how grid and print labels are displayed.
        </p>

        <form
          id="display-format-form"
          phx-change="set_display_format"
          class="mb-4 flex items-center gap-3"
        >
          <label for="display-format" class="text-sm font-medium text-gray-700">
            Grid and print label format
          </label>
          <select
            id="display-format"
            name="format"
            class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
          >
            <%= for format <- @display_formats do %>
              <option value={format} selected={@display_format == format}>
                {display_format_label(format)}
              </option>
            <% end %>
          </select>
        </form>

        <!-- Current Colors -->
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for {color, index} <- Enum.with_index(@colors) do %>
            <div class="flex items-center bg-white border rounded-lg p-3">
              <!-- Color Preview -->
              <div class="flex items-center mr-3">
                <div
                  class="w-8 h-8 rounded border border-gray-300 mr-3"
                  style={"background-color: #{color}"}
                >
                </div>
                <div class="flex flex-col">
                  <span class="text-sm font-mono">
                    {format_color_label(color, @display_format)}
                  </span>
                  <span class="text-xs text-gray-500 font-mono">
                    {format_color_label(ColorUtils.invert_color(color), @display_format)}
                  </span>
                </div>
              </div>

              <button
                phx-click="remove_color"
                phx-value-index={index}
                class="ml-2 text-red-500 hover:text-red-700 text-sm"
              >
                ×
              </button>
            </div>
          <% end %>
        </div>

        <!-- Add Color -->
        <form
          id="add-color-form"
          phx-change="update_color_input"
          phx-submit="add_color"
          class="flex gap-2 items-center"
        >
          <input
            type="color"
            name="value"
            value={@new_color || "#FF6B6B"}
            class="w-10 h-10 border rounded"
          />
          <input
            type="text"
            name="color"
            value={@new_color}
            placeholder="#FF6B6B"
            class="px-3 py-2 border rounded font-mono text-sm"
          />
          <button
            type="submit"
            disabled={@new_color == "" || @grid_size >= @max_grid_colors}
            class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
          >
            Add Color
          </button>
        </form>
      </div>

      <!-- Grid Size Control -->
      <div class="mb-6 no-print">
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Grid Size: {@grid_size}×{@grid_size}
        </label>
        <p class="text-xs text-gray-500 mb-2">
          Expanding the grid will automatically add random colors as needed
        </p>
        <form id="grid-size-form" phx-change="change_grid_size">
          <input
            type="range"
            name="size"
            min="6"
            max={@max_grid_colors}
            value={@grid_size}
            class="w-48"
          />
        </form>
      </div>

      <!-- Color Grid -->
      <%= if length(@colors) >= @grid_size do %>
        <!-- Print Area (hidden on screen, visible when printing) -->
        <div class="print-area">
          <div class="print-title">{active_palette_label(@active_palette)}</div>
          <div class="print-grid">
            <div class="print-grid-container">
              <div
                class="grid gap-1 w-full h-full"
                style={"grid-template-columns: repeat(#{@grid_size}, 1fr);"}
              >
                <%= for row <- @grid.grid do %>
                  <%= for cell <- row do %>
                    <div
                      class="relative border border-gray-300 print-cell"
                      style={"background: linear-gradient(to bottom right, #{cell.top_left_color} 0%, #{cell.top_left_color} 50%, #{cell.bottom_right_color} 50%, #{cell.bottom_right_color} 100%)"}
                    >
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Print Legend -->
          <div class="print-legend">
            <h3>Color Legend</h3>
            <div class="print-legend-colors">
              <%= for {color, index} <- Enum.with_index(@colors) do %>
                <div class="print-legend-item">
                  <div
                    class="print-color-preview triangle-top-left"
                    style={"background-color: #{color}"}
                  >
                  </div>
                  <span class="print-legend-text">
                    {format_color_label(color, @display_format)} (Row {index + 1})
                  </span>
                </div>
                <div class="print-legend-item">
                  <div
                    class="print-color-preview triangle-bottom-right"
                    style={"background-color: #{color}"}
                  >
                  </div>
                  <span class="print-legend-text">
                    {format_color_label(color, @display_format)} (Col {index + 1})
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Screen Display (visible on screen, hidden when printing) -->
        <div
          class="grid gap-1 no-print"
          style={"grid-template-columns: repeat(#{@grid_size}, 1fr); max-width: 600px;"}
        >
          <%= for row <- @grid.grid do %>
            <%= for cell <- row do %>
              <div class="relative w-16 h-16 border border-gray-300">
                <!-- Top-left triangle -->
                <div
                  class="absolute inset-0 triangle-top-left"
                  style={"background-color: #{cell.top_left_color}"}
                >
                </div>
                <!-- Bottom-right triangle -->
                <%= if cell.is_diagonal do %>
                  <!-- On diagonal: split the bottom-right triangle -->
                  <!-- First layer: inverted color covering the whole bottom-right area -->
                  <div
                    class="absolute inset-0 triangle-bottom-right"
                    style={"background-color: #{ColorUtils.invert_color(cell.bottom_right_color)}"}
                  >
                  </div>
                  <!-- Second layer: original color covering only the lower portion -->
                  <div
                    class="absolute inset-0 triangle-diagonal-split"
                    style={"background-color: #{cell.bottom_right_color}"}
                  >
                  </div>
                <% else %>
                  <!-- Off diagonal: normal bottom-right triangle -->
                  <div
                    class="absolute inset-0 triangle-bottom-right"
                    style={"background-color: #{cell.bottom_right_color}"}
                  >
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="text-gray-500 italic no-print">
          Add at least {@grid_size} colors to generate the grid.
        </div>
      <% end %>
    </div>
    """
  end
end

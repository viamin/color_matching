defmodule ColorMatchingWeb.ColorGridLive do
  use ColorMatchingWeb, :live_view
  alias ColorMatching.{Grid, ColorUtils, PaletteStorage}

  @default_colors ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#FD79A8"]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:colors, @default_colors)
     |> assign(:grid_size, 6)
     |> assign(:new_color, "")
     |> assign(:preset_palettes, PaletteStorage.get_preset_palettes())
     |> assign(:saved_palettes, [])
     |> assign(:show_palette_menu, false)
     |> assign(:show_save_modal, false)
     |> assign(:show_load_modal, false)
     |> assign(:show_rename_modal, false)
     |> assign(:show_confirm_load, false)
     |> assign(:save_palette_name, "")
     |> assign(:rename_palette_name, "")
     |> assign(:selected_palette, nil)
     |> assign(:pending_load_palette, nil)
     |> assign_grid()}
  end

  def handle_event("add_color", %{"color" => color}, socket) do
    colors = socket.assigns.colors ++ [color]
    
    {:noreply,
     socket
     |> assign(:colors, colors)
     |> assign(:new_color, "")
     |> assign_grid()}
  end

  def handle_event("remove_color", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    colors = List.delete_at(socket.assigns.colors, index)
    
    {:noreply,
     socket
     |> assign(:colors, colors)
     |> assign_grid()}
  end

  def handle_event("update_color_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_color, value)}
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
     |> assign_grid()}
  end

  # Palette management events
  def handle_event("toggle_palette_menu", _params, socket) do
    {:noreply, assign(socket, :show_palette_menu, !socket.assigns.show_palette_menu)}
  end

  def handle_event("show_save_modal", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_save_modal, true)
     |> assign(:save_palette_name, "")
     |> assign(:show_palette_menu, false)}
  end

  def handle_event("show_load_modal", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_load_modal, true)
     |> assign(:show_palette_menu, false)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, 
     socket
     |> assign(:show_save_modal, false)
     |> assign(:show_load_modal, false)
     |> assign(:show_rename_modal, false)
     |> assign(:show_confirm_load, false)
     |> assign(:save_palette_name, "")
     |> assign(:rename_palette_name, "")}
  end

  def handle_event("update_save_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :save_palette_name, value)}
  end

  def handle_event("update_rename_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :rename_palette_name, value)}
  end

  def handle_event("save_palette", %{"name" => name}, socket) do
    case PaletteStorage.validate_palette_name(name) do
      {:ok, validated_name} ->
        # Send to client-side hook to save in localStorage
        {:noreply, 
         socket
         |> assign(:show_save_modal, false)
         |> assign(:save_palette_name, "")
         |> push_event("save_palette", %{name: validated_name, colors: socket.assigns.colors})}
      
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("request_load_palette", %{"palette" => palette_json}, socket) do
    case Jason.decode(palette_json) do
      {:ok, %{"name" => name, "colors" => colors, "is_preset" => is_preset}} ->
        palette = %{name: name, colors: colors, is_preset: is_preset}
        {:noreply, 
         socket
         |> assign(:show_load_modal, false)
         |> assign(:show_confirm_load, true)
         |> assign(:pending_load_palette, palette)}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid palette data")}
    end
  end

  def handle_event("confirm_load_palette", _params, socket) do
    palette = socket.assigns.pending_load_palette
    new_grid_size = length(palette.colors)
    
    {:noreply,
     socket
     |> assign(:colors, palette.colors)
     |> assign(:grid_size, new_grid_size)
     |> assign(:show_confirm_load, false)
     |> assign(:pending_load_palette, nil)
     |> assign_grid()}
  end

  def handle_event("show_rename_modal", %{"palette" => palette_json}, socket) do
    case Jason.decode(palette_json) do
      {:ok, %{"name" => name, "colors" => colors, "is_preset" => false}} ->
        palette = %{name: name, colors: colors, is_preset: false}
        {:noreply, 
         socket
         |> assign(:show_rename_modal, true)
         |> assign(:show_load_modal, false)
         |> assign(:selected_palette, palette)
         |> assign(:rename_palette_name, name)}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid palette data")}
    end
  end

  def handle_event("rename_palette", %{"old_name" => old_name, "new_name" => new_name}, socket) do
    case PaletteStorage.validate_palette_name(new_name) do
      {:ok, validated_name} ->
        {:noreply, 
         socket
         |> assign(:show_rename_modal, false)
         |> assign(:rename_palette_name, "")
         |> assign(:selected_palette, nil)
         |> push_event("rename_palette", %{old_name: old_name, new_name: validated_name})}
      
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("delete_palette", %{"name" => name}, socket) do
    {:noreply, 
     socket
     |> assign(:show_load_modal, false)
     |> push_event("delete_palette", %{name: name})}
  end

  def handle_event("palettes_updated", %{"palettes" => palettes}, socket) do
    {:noreply, assign(socket, :saved_palettes, palettes)}
  end

  defp assign_grid(socket) do
    grid = Grid.new(socket.assigns.colors, socket.assigns.grid_size)
    assign(socket, :grid, grid)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6" phx-hook="PaletteStorage" id="palette-storage">
      <h1 class="text-3xl font-bold text-gray-900 mb-4 no-print">Color Matching Grid</h1>
      <p class="text-gray-600 mb-8 no-print">
        Each square shows two triangles: the top-left uses your selected colors, 
        and the bottom-right uses their inverse colors for maximum contrast and double the combinations.
      </p>
      
      <!-- Color Management -->
      <div class="mb-8 p-4 bg-gray-50 rounded-lg no-print">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold">Manage Colors</h2>
          <div class="relative">
            <button 
              phx-click="toggle_palette_menu"
              class="p-2 text-gray-600 hover:text-gray-800 hover:bg-gray-200 rounded-full"
              title="Palette Options"
            >
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z"></path>
              </svg>
            </button>
            
            <%= if @show_palette_menu do %>
              <div class="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg z-10 border">
                <div class="py-1">
                  <button 
                    phx-click="show_save_modal"
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    Save Current Palette
                  </button>
                  <button 
                    phx-click="show_load_modal"
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                  >
                    Load Palette
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        
        <!-- Current Colors -->
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for {color, index} <- Enum.with_index(@colors) do %>
            <div class="flex items-center bg-white border rounded-lg p-3">
              <!-- Original Color (Top-left triangle shape) -->
              <div class="flex flex-col items-center mr-3">
                <div class="relative w-6 h-6 mb-1">
                  <div class="absolute inset-0 triangle-top-left border border-gray-300" style={"background-color: #{color}"}></div>
                </div>
                <span class="text-xs text-gray-600">Top-left</span>
              </div>
              
              <!-- Inverse Color (Bottom-right triangle shape) -->
              <div class="flex flex-col items-center mr-3">
                <div class="relative w-6 h-6 mb-1">
                  <div class="absolute inset-0 triangle-bottom-right border border-gray-300" style={"background-color: #{ColorUtils.invert_color(color)}"}></div>
                </div>
                <span class="text-xs text-gray-600">Bottom-right</span>
              </div>
              
              <!-- Color Values -->
              <div class="flex flex-col mr-2">
                <span class="text-sm font-mono"><%= color %></span>
                <span class="text-xs font-mono text-gray-500"><%= ColorUtils.invert_color(color) %></span>
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
        <form phx-change="update_color_input" phx-submit="add_color" class="flex gap-2 items-center">
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
            disabled={@new_color == ""}
            class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
          >
            Add Color
          </button>
        </form>
      </div>

      <!-- Grid Size Control -->
      <div class="mb-6 no-print">
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Grid Size: <%= @grid_size %>×<%= @grid_size %>
        </label>
        <p class="text-xs text-gray-500 mb-2">
          Expanding the grid will automatically add random colors as needed
        </p>
        <form phx-change="change_grid_size">
          <input 
            type="range" 
            name="size"
            min="6" 
            max="12" 
            value={@grid_size}
            class="w-48"
          />
        </form>
      </div>

      <!-- Color Grid -->
      <%= if length(@colors) >= @grid_size do %>
        <!-- Print Area (hidden on screen, visible when printing) -->
        <div class="print-area">
          <div class="print-title">Color Matching Grid (<%= @grid_size %>×<%= @grid_size %>)</div>
          <div class="print-grid">
            <div class="print-grid-container">
              <div class="grid gap-1 w-full h-full" style={"grid-template-columns: repeat(#{@grid_size}, 1fr);"}>
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
                  <div class="print-color-preview triangle-top-left" style={"background-color: #{color}"}></div>
                  <span class="print-legend-text"><%= color %> (Row <%= index + 1 %>)</span>
                </div>
                <div class="print-legend-item">
                  <div class="print-color-preview triangle-bottom-right" style={"background-color: #{ColorUtils.invert_color(color)}"}></div>
                  <span class="print-legend-text"><%= ColorUtils.invert_color(color) %> (Col <%= index + 1 %>)</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
        <!-- Screen Display (visible on screen, hidden when printing) -->
        <div class="grid gap-1 no-print" style={"grid-template-columns: repeat(#{@grid_size}, 1fr); max-width: 600px;"}>
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
                <div 
                  class="absolute inset-0 triangle-bottom-right"
                  style={"background-color: #{cell.bottom_right_color}"}
                >
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <div class="text-gray-500 italic no-print">
          Add at least <%= @grid_size %> colors to generate the grid.
        </div>
      <% end %>

      <!-- Save Palette Modal -->
      <%= if @show_save_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 no-print">
          <div class="bg-white rounded-lg p-6 w-96">
            <h3 class="text-lg font-semibold mb-4">Save Color Palette</h3>
            <form phx-submit="save_palette">
              <input 
                type="text" 
                name="name"
                value={@save_palette_name}
                phx-change="update_save_name"
                placeholder="Enter palette name"
                class="w-full px-3 py-2 border rounded mb-4"
                required
              />
              <div class="flex gap-2">
                <button 
                  type="submit"
                  class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
                >
                  Save
                </button>
                <button 
                  type="button"
                  phx-click="close_modal"
                  class="px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Load Palette Modal -->
      <%= if @show_load_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 no-print">
          <div class="bg-white rounded-lg p-6 w-96 max-h-96 overflow-y-auto">
            <h3 class="text-lg font-semibold mb-4">Load Color Palette</h3>
            
            <!-- Preset Palettes -->
            <div class="mb-6">
              <h4 class="font-medium text-gray-700 mb-2">Preset Palettes</h4>
              <%= for palette <- @preset_palettes do %>
                <div class="flex items-center justify-between p-2 border rounded mb-2 hover:bg-gray-50">
                  <div class="flex items-center">
                    <span class="font-medium mr-2"><%= palette.name %></span>
                    <div class="flex">
                      <%= for color <- Enum.take(palette.colors, 4) do %>
                        <div class="w-4 h-4 rounded-sm mr-1" style={"background-color: #{color}"}></div>
                      <% end %>
                      <%= if length(palette.colors) > 4 do %>
                        <span class="text-xs text-gray-500">+<%= length(palette.colors) - 4 %></span>
                      <% end %>
                    </div>
                  </div>
                  <button 
                    phx-click="request_load_palette"
                    phx-value-palette={Jason.encode!(palette)}
                    class="px-3 py-1 bg-blue-500 text-white text-sm rounded hover:bg-blue-600"
                  >
                    Load
                  </button>
                </div>
              <% end %>
            </div>

            <!-- Saved Palettes -->
            <%= if length(@saved_palettes) > 0 do %>
              <div class="mb-4">
                <h4 class="font-medium text-gray-700 mb-2">Saved Palettes</h4>
                <%= for palette <- @saved_palettes do %>
                  <div class="flex items-center justify-between p-2 border rounded mb-2 hover:bg-gray-50">
                    <div class="flex items-center">
                      <span class="font-medium mr-2"><%= palette["name"] %></span>
                      <div class="flex">
                        <%= for color <- Enum.take(palette["colors"], 4) do %>
                          <div class="w-4 h-4 rounded-sm mr-1" style={"background-color: #{color}"}></div>
                        <% end %>
                        <%= if length(palette["colors"]) > 4 do %>
                          <span class="text-xs text-gray-500">+<%= length(palette["colors"]) - 4 %></span>
                        <% end %>
                      </div>
                    </div>
                    <div class="flex gap-1">
                      <button 
                        phx-click="request_load_palette"
                        phx-value-palette={Jason.encode!(palette)}
                        class="px-2 py-1 bg-blue-500 text-white text-xs rounded hover:bg-blue-600"
                      >
                        Load
                      </button>
                      <button 
                        phx-click="show_rename_modal"
                        phx-value-palette={Jason.encode!(palette)}
                        class="px-2 py-1 bg-gray-500 text-white text-xs rounded hover:bg-gray-600"
                      >
                        Rename
                      </button>
                      <button 
                        phx-click="delete_palette"
                        phx-value-name={palette["name"]}
                        class="px-2 py-1 bg-red-500 text-white text-xs rounded hover:bg-red-600"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
            
            <button 
              phx-click="close_modal"
              class="w-full px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
            >
              Close
            </button>
          </div>
        </div>
      <% end %>

      <!-- Rename Palette Modal -->
      <%= if @show_rename_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 no-print">
          <div class="bg-white rounded-lg p-6 w-96">
            <h3 class="text-lg font-semibold mb-4">Rename Palette</h3>
            <form phx-submit="rename_palette" phx-value-old_name={@selected_palette && @selected_palette.name}>
              <input 
                type="text" 
                name="new_name"
                value={@rename_palette_name}
                phx-change="update_rename_name"
                placeholder="Enter new palette name"
                class="w-full px-3 py-2 border rounded mb-4"
                required
              />
              <div class="flex gap-2">
                <button 
                  type="submit"
                  class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
                >
                  Rename
                </button>
                <button 
                  type="button"
                  phx-click="close_modal"
                  class="px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Confirm Load Modal -->
      <%= if @show_confirm_load do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 no-print">
          <div class="bg-white rounded-lg p-6 w-96">
            <h3 class="text-lg font-semibold mb-4">Confirm Load Palette</h3>
            <p class="mb-4 text-gray-600">
              Loading "<%= @pending_load_palette && @pending_load_palette.name %>" will replace your current colors. 
              Are you sure you want to continue?
            </p>
            <div class="flex gap-2">
              <button 
                phx-click="confirm_load_palette"
                class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
              >
                Yes, Load Palette
              </button>
              <button 
                phx-click="close_modal"
                class="px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
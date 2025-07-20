defmodule ColorMatchingWeb.ColorGridLive do
  use ColorMatchingWeb, :live_view
  alias ColorMatching.{Grid, ColorUtils}

  @default_colors ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7"]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:colors, @default_colors)
     |> assign(:grid_size, 5)
     |> assign(:new_color, "")
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

  defp assign_grid(socket) do
    grid = Grid.new(socket.assigns.colors, socket.assigns.grid_size)
    assign(socket, :grid, grid)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6">
      <h1 class="text-3xl font-bold text-gray-900 mb-4">Color Matching Grid</h1>
      <p class="text-gray-600 mb-8">
        Each square shows two triangles: the top-left uses your selected colors, 
        and the bottom-right uses their inverse colors for maximum contrast and double the combinations.
      </p>
      
      <!-- Color Management -->
      <div class="mb-8 p-4 bg-gray-50 rounded-lg">
        <h2 class="text-xl font-semibold mb-4">Manage Colors</h2>
        
        <!-- Current Colors -->
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for {color, index} <- Enum.with_index(@colors) do %>
            <div class="flex items-center bg-white border rounded-lg p-3">
              <!-- Original Color -->
              <div class="flex flex-col items-center mr-3">
                <div class="w-6 h-6 rounded mb-1" style={"background-color: #{color}"}></div>
                <span class="text-xs text-gray-600">Original</span>
              </div>
              
              <!-- Inverse Color -->
              <div class="flex flex-col items-center mr-3">
                <div class="w-6 h-6 rounded mb-1" style={"background-color: #{ColorUtils.invert_color(color)}"}></div>
                <span class="text-xs text-gray-600">Inverse</span>
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
      <div class="mb-6">
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
            min="3" 
            max="10" 
            value={@grid_size}
            class="w-48"
          />
        </form>
      </div>

      <!-- Color Grid -->
      <%= if length(@colors) >= @grid_size do %>
        <div class="grid gap-1" style={"grid-template-columns: repeat(#{@grid_size}, 1fr); max-width: 600px;"}>
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
        <div class="text-gray-500 italic">
          Add at least <%= @grid_size %> colors to generate the grid.
        </div>
      <% end %>
    </div>
    """
  end
end
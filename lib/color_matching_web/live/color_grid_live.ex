defmodule ColorMatchingWeb.ColorGridLive do
  use ColorMatchingWeb, :live_view
  alias ColorMatching.{ColorFormat, ColorUtils, GeneratedSheet, Grid, PrinterProfile}

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
    printer_profiles = PrinterProfile.default_profiles()
    [default_printer_profile | _] = printer_profiles

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
     |> assign(:printer_profiles, printer_profiles)
     |> assign(:active_printer_profile, default_printer_profile)
     |> assign(:printer_profile_form, empty_printer_profile_form())
     |> assign(:display_format, ColorFormat.default_display_format())
     |> assign(:display_formats, ColorFormat.display_formats())
     |> assign(:max_grid_colors, @max_grid_colors)
     |> assign_grid()}
  end

  def handle_event("add_color", params, socket) do
    # Get color from either 'color' or 'value' parameter
    raw_color = params["color"] || params["value"] || socket.assigns.new_color

    cond do
      length(socket.assigns.colors) >= @max_grid_colors ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Palettes are limited to #{@max_grid_colors} colors so the grid can render every combination."
         )}

      raw_color && raw_color != "" ->
        case ColorFormat.normalize_hex(raw_color) do
          {:ok, color} ->
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

          {:error, reason} ->
            # Reject invalid hex at the boundary so downstream renderers
            # (Grid.new, ColorUtils.invert_color/1) never see an unparseable
            # color. ColorUtils.invert_color/1 now also tolerates bad input as
            # defense in depth, but normalizing here keeps storage clean.
            {:noreply, put_flash(socket, :error, reason)}
        end

      true ->
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

  def handle_event("update_printer_profile_form", %{"profile" => params}, socket) do
    {:noreply, assign(socket, :printer_profile_form, normalize_printer_profile_form(params))}
  end

  def handle_event("create_printer_profile", %{"profile" => params}, socket) do
    case PrinterProfile.validate(params) do
      {:ok, printer_profile} ->
        printer_profiles =
          upsert_printer_profile(socket.assigns.printer_profiles, printer_profile)

        {:noreply,
         socket
         |> assign(:printer_profiles, printer_profiles)
         |> assign(:active_printer_profile, printer_profile)
         |> assign(:printer_profile_form, empty_printer_profile_form())
         |> assign_grid()
         |> persist_printer_profiles()
         |> persist_active_printer_profile()
         |> put_flash(
           :info,
           "Created printer profile #{PrinterProfile.display_name(printer_profile)}"
         )}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:printer_profile_form, normalize_printer_profile_form(params))
         |> put_flash(:error, message)}
    end
  end

  def handle_event("select_printer_profile", %{"profile_id" => profile_id}, socket) do
    printer_profile =
      Enum.find(socket.assigns.printer_profiles, &(&1.id == profile_id)) ||
        socket.assigns.active_printer_profile

    {:noreply,
     socket
     |> assign(:active_printer_profile, printer_profile)
     |> assign_grid()
     |> persist_active_printer_profile()}
  end

  def handle_event("set_display_format", %{"format" => format}, socket) do
    case ColorFormat.normalize_display_format(format) do
      {:ok, display_format} ->
        {:noreply,
         socket
         |> assign(:display_format, display_format)
         |> push_event("set_display_format_preference", %{
           format: Atom.to_string(display_format)
         })}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("display_format_loaded", %{"format" => format}, socket) do
    case ColorFormat.normalize_display_format(format) do
      {:ok, display_format} ->
        {:noreply, assign(socket, :display_format, display_format)}

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

  def handle_event("printer_profiles_loaded", %{"profiles" => profiles}, socket)
      when is_list(profiles) do
    printer_profiles =
      profiles
      |> Enum.map(&build_printer_profile/1)
      |> Enum.reject(&is_nil/1)
      |> merge_default_printer_profiles()

    {:noreply,
     socket
     |> assign(:printer_profiles, printer_profiles)
     |> assign(:active_printer_profile, active_printer_profile(printer_profiles, socket.assigns))
     |> assign_grid()}
  end

  def handle_event("printer_profiles_loaded", _params, socket), do: {:noreply, socket}

  def handle_event("active_printer_profile_loaded", %{"profile_id" => profile_id}, socket)
      when is_binary(profile_id) and profile_id != "" do
    printer_profile =
      Enum.find(socket.assigns.printer_profiles, &(&1.id == profile_id)) ||
        socket.assigns.active_printer_profile

    {:noreply,
     socket
     |> assign(:active_printer_profile, printer_profile)
     |> assign_grid()}
  end

  def handle_event("active_printer_profile_loaded", _params, socket), do: {:noreply, socket}

  defp assign_grid(socket) do
    grid = Grid.new(socket.assigns.colors, socket.assigns.grid_size)

    generated_sheet =
      GeneratedSheet.new(%{
        colors: socket.assigns.colors,
        grid_size: socket.assigns.grid_size,
        palette_name: active_palette_label(socket.assigns.active_palette),
        printer_profile: socket.assigns.active_printer_profile
      })

    socket
    |> assign(:grid, grid)
    |> assign(:generated_sheet, generated_sheet)
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

  defp persist_printer_profiles(socket) do
    push_event(socket, "save_printer_profiles", %{
      profiles: Enum.map(socket.assigns.printer_profiles, &Map.from_struct/1)
    })
  end

  defp persist_active_printer_profile(socket) do
    push_event(socket, "set_active_printer_profile", %{
      profile_id: socket.assigns.active_printer_profile.id
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

  defp pair_second_color(%{is_diagonal: true, bottom_right_color: color}) do
    ColorUtils.invert_color(color)
  end

  defp pair_second_color(%{bottom_right_color: color}), do: color

  defp pair_link_params(cell, generated_sheet) do
    [
      a: cell.top_left_color,
      b: pair_second_color(cell),
      sheet_id: generated_sheet.id
    ] ++ PrinterProfile.to_query_params(generated_sheet.printer_profile)
  end

  defp normalize_printer_profile_form(params) when is_map(params) do
    Enum.reduce(empty_printer_profile_form(), %{}, fn {key, _default}, acc ->
      Map.put(acc, key, Map.get(params, Atom.to_string(key), Map.get(params, key, "")))
    end)
  end

  defp empty_printer_profile_form do
    %{
      printer_make_model: "",
      paper_type: "",
      ink_type: "",
      icc_profile: "",
      print_settings: "",
      driver_name: "",
      driver_version: "",
      calibration_date: "",
      calibration_version: "",
      notes: ""
    }
  end

  defp upsert_printer_profile(printer_profiles, printer_profile) do
    [printer_profile | Enum.reject(printer_profiles, &(&1.id == printer_profile.id))]
  end

  defp build_printer_profile(params) when is_map(params) do
    case PrinterProfile.validate(params) do
      {:ok, printer_profile} -> printer_profile
      {:error, _message} -> nil
    end
  end

  defp build_printer_profile(_params), do: nil

  defp merge_default_printer_profiles(printer_profiles) do
    existing_ids = MapSet.new(printer_profiles, & &1.id)

    printer_profiles ++
      Enum.reject(PrinterProfile.default_profiles(), &MapSet.member?(existing_ids, &1.id))
  end

  defp active_printer_profile(printer_profiles, assigns) do
    Enum.find(printer_profiles, &(&1.id == assigns.active_printer_profile.id)) ||
      List.first(printer_profiles)
  end

  def render(assigns) do
    ~H"""
    <div
      class="max-w-6xl mx-auto p-6"
      phx-hook="PaletteStorage"
      id="grid-palette-storage"
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
          The palette editor still exposes every format. This preference controls how grid and
          print labels are displayed.
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
            class="rounded-lg border border-gray-300 pl-3 pr-10 py-2 text-sm"
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
            disabled={@new_color == "" || length(@colors) >= @max_grid_colors}
            class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
          >
            Add Color
          </button>
        </form>
      </div>

      <div class="mb-8 rounded-lg border border-emerald-200 bg-emerald-50 p-4 no-print">
        <div class="mb-4">
          <h2 class="text-xl font-semibold text-gray-900">Printer Profile</h2>
          <p class="mt-1 text-sm text-gray-600">
            Generated sheets and pair measurements are scoped to the selected printer profile.
          </p>
        </div>

        <form
          id="select-printer-profile-form"
          phx-change="select_printer_profile"
          class="mb-4 flex flex-col gap-2 md:max-w-xl"
        >
          <label for="profile_id" class="text-sm font-medium text-gray-700">
            Active printer profile
          </label>
          <select
            id="profile_id"
            name="profile_id"
            class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
          >
            <%= for profile <- @printer_profiles do %>
              <option value={profile.id} selected={profile.id == @active_printer_profile.id}>
                {PrinterProfile.display_name(profile)}
              </option>
            <% end %>
          </select>
          <p class="text-xs text-gray-600">
            ICC: {@active_printer_profile.icc_profile || "Not specified"}.
            Calibration: {@active_printer_profile.calibration_version || "Not specified"}.
          </p>
        </form>

        <form
          id="create-printer-profile-form"
          phx-change="update_printer_profile_form"
          phx-submit="create_printer_profile"
        >
          <div class="grid gap-3 md:grid-cols-2">
            <input
              type="text"
              name="profile[printer_make_model]"
              value={@printer_profile_form.printer_make_model}
              placeholder="Printer make/model"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[paper_type]"
              value={@printer_profile_form.paper_type}
              placeholder="Paper type"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[ink_type]"
              value={@printer_profile_form.ink_type}
              placeholder="Ink type"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[icc_profile]"
              value={@printer_profile_form.icc_profile}
              placeholder="ICC color profile"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[print_settings]"
              value={@printer_profile_form.print_settings}
              placeholder="Print quality/settings"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[driver_name]"
              value={@printer_profile_form.driver_name}
              placeholder="Driver"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[driver_version]"
              value={@printer_profile_form.driver_version}
              placeholder="Driver version"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[calibration_date]"
              value={@printer_profile_form.calibration_date}
              placeholder="Calibration date"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[calibration_version]"
              value={@printer_profile_form.calibration_version}
              placeholder="Calibration version"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <input
              type="text"
              name="profile[notes]"
              value={@printer_profile_form.notes}
              placeholder="Notes"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
          </div>
          <button
            type="submit"
            class="mt-3 rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
          >
            Create Printer Profile
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
          <div class="mb-2 text-sm text-gray-700">
            Sheet {@generated_sheet.id} for {PrinterProfile.display_name(@active_printer_profile)}
          </div>
          <div class="print-grid">
            <div class="print-grid-container">
              <div
                class="print-color-grid grid gap-0 w-full h-full"
                style={"grid-template-columns: repeat(#{@grid_size}, 1fr);"}
              >
                <%= for row <- @grid.grid do %>
                  <%= for cell <- row do %>
                    <.color_cell cell={cell} class="print-grid-cell print-cell" />
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
          class="grid gap-0 no-print"
          style={"grid-template-columns: repeat(#{@grid_size}, 1fr); max-width: 600px;"}
        >
          <%= for row <- @grid.grid do %>
            <%= for cell <- row do %>
              <.link
                navigate={~p"/pair?#{pair_link_params(cell, @generated_sheet)}"}
                class="block focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                aria-label={"Compare #{cell.top_left_color} and #{pair_second_color(cell)}"}
              >
                <.color_cell cell={cell} class="w-16 h-16" />
              </.link>
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

  # Renders a grid cell as a top-left triangle plus a bottom-right triangle.
  # On the main diagonal, the bottom-right triangle is further split into an
  # inverted-color layer topped by an original-color layer (see Grid moduledoc).
  # Shared by the screen and print grids so both stay visually in sync.
  attr :cell, :map, required: true
  attr :class, :string, default: ""

  defp color_cell(assigns) do
    ~H"""
    <div class={["relative overflow-hidden", @class]}>
      <div
        class="absolute inset-0 triangle-top-left"
        style={"background-color: #{@cell.top_left_color}"}
      >
      </div>
      <%= if @cell.is_diagonal do %>
        <div
          class="absolute inset-0 triangle-bottom-right"
          style={"background-color: #{ColorUtils.invert_color(@cell.bottom_right_color)}"}
        >
        </div>
        <div
          class="absolute inset-0 triangle-diagonal-split"
          style={"background-color: #{@cell.bottom_right_color}"}
        >
        </div>
      <% else %>
        <div
          class="absolute inset-0 triangle-bottom-right"
          style={"background-color: #{@cell.bottom_right_color}"}
        >
        </div>
      <% end %>
    </div>
    """
  end
end

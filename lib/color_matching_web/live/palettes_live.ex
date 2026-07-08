defmodule ColorMatchingWeb.PalettesLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.{ColorFormat, Palette, PaletteStorage}

  @default_colors ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#FD79A8"]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:preset_palettes, PaletteStorage.get_preset_palettes())
     |> assign(:saved_palettes, [])
     |> assign(:active_palette, nil)
     |> assign(:active_palette_colors, @default_colors)
     |> assign(:editing_palette, nil)
     |> assign(:editing_name, "")
     |> assign(:editor_inputs, %{})
     |> assign(:editor_errors, %{})
     |> assign(:new_palette_name, "")
     |> assign(:new_color_value, "#FFFFFF")}
  end

  def handle_event("palettes_updated", %{"palettes" => palettes}, socket) do
    {:noreply, assign(socket, :saved_palettes, normalize_saved_palettes(palettes))}
  end

  def handle_event(
        "active_palette_loaded",
        %{"palette" => %{"colors" => colors} = palette_map},
        socket
      )
      when is_list(colors) and colors != [] do
    palette = Palette.new(palette_map)

    socket =
      socket
      |> assign(:active_palette, palette_meta(palette))
      |> assign(:active_palette_colors, colors)

    {:noreply, maybe_assign_editor(socket, palette)}
  end

  def handle_event("active_palette_loaded", _params, socket), do: {:noreply, socket}

  def handle_event("update_new_palette_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_palette_name, value)}
  end

  def handle_event("create_palette", %{"name" => name}, socket) do
    with {:ok, validated_name} <- validate_user_palette_name(socket, name),
         colors <- socket.assigns.active_palette_colors,
         palette <-
           Palette.new(%{
             name: validated_name,
             colors: colors,
             is_preset: false,
             created_at: DateTime.to_iso8601(DateTime.utc_now())
           }) do
      {:noreply,
       socket
       |> assign(:new_palette_name, "")
       |> put_flash(:info, "Created \"#{palette.name}\" from the current grid palette")
       |> persist_palette(palette)
       |> assign_editor(palette)}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("open_palette", %{"palette" => palette_json}, socket) do
    case PaletteStorage.decode_palette(palette_json) do
      {:ok, %Palette{is_preset: false} = palette} ->
        {:noreply, assign_editor(socket, palette)}

      {:ok, _palette} ->
        {:noreply, put_flash(socket, :error, "Preset palettes must be duplicated before editing")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid palette data")}
    end
  end

  def handle_event("use_palette", %{"palette" => palette_json}, socket) do
    case PaletteStorage.decode_palette(palette_json) do
      {:ok, palette} ->
        {:noreply,
         socket
         |> activate_palette(palette)
         |> put_flash(:info, "\"#{palette.name}\" is ready for the grid")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid palette data")}
    end
  end

  def handle_event("duplicate_palette", %{"palette" => palette_json}, socket) do
    case PaletteStorage.decode_palette(palette_json) do
      {:ok, palette} ->
        existing_names = Enum.map(socket.assigns.saved_palettes, & &1.name)

        case PaletteStorage.duplicate_name(palette.name, existing_names) do
          nil ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Couldn't find a free name for the duplicate. Rename or remove some existing copies of \"#{palette.name}\" and try again."
             )}

          candidate_name ->
            with {:ok, validated_name} <- validate_user_palette_name(socket, candidate_name),
                 duplicated = Palette.duplicate(palette, validated_name) do
              {:noreply,
               socket
               |> put_flash(:info, "Duplicated \"#{palette.name}\" as \"#{duplicated.name}\"")
               |> persist_palette(duplicated)
               |> assign_editor(duplicated)}
            else
              {:error, error} -> {:noreply, put_flash(socket, :error, error)}
            end
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid palette data")}
    end
  end

  def handle_event("delete_palette", %{"name" => name}, socket) do
    deleted =
      Enum.find(socket.assigns.saved_palettes, &(&1.name == name)) ||
        socket.assigns.editing_palette

    socket =
      socket
      |> assign(:saved_palettes, Enum.reject(socket.assigns.saved_palettes, &(&1.name == name)))
      |> maybe_clear_editor(name)
      |> push_event("delete_palette", %{name: name})

    socket =
      case {socket.assigns.active_palette, deleted} do
        {%{name: ^name}, %Palette{} = palette} ->
          socket
          |> assign(:active_palette, nil)
          |> assign(:active_palette_colors, palette.colors)
          |> push_event("activate_palette", %{name: nil, colors: palette.colors, is_preset: false})

        _ ->
          socket
      end

    {:noreply, put_flash(socket, :info, "Deleted \"#{name}\"")}
  end

  def handle_event("update_editor_name_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :editing_name, value)}
  end

  def handle_event("rename_palette", %{"name" => name}, socket) do
    case socket.assigns.editing_palette do
      %Palette{} = palette ->
        with {:ok, validated_name} <-
               validate_user_palette_name(socket, name, except_name: palette.name) do
          renamed = %{palette | name: validated_name}

          {:noreply,
           socket
           |> assign(:saved_palettes, rename_saved_palette(socket.assigns.saved_palettes, palette.name, renamed))
           |> assign_editor(renamed)
           |> push_event("rename_palette", %{old_name: palette.name, new_name: validated_name})
           |> maybe_activate_after_rename(palette, renamed)
           |> put_flash(:info, "Renamed palette to \"#{validated_name}\"")}
        else
          {:error, error} -> {:noreply, put_flash(socket, :error, error)}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a user palette to rename")}
    end
  end

  def handle_event("update_editor_field", %{"index" => index, "format" => format, "value" => value}, socket) do
    {:noreply,
     socket
     |> put_in_editor_input(index, format, value)
     |> clear_editor_error(index)}
  end

  def handle_event("apply_color_format", %{"index" => index, "format" => format}, socket) do
    with %Palette{} = palette <- socket.assigns.editing_palette,
         value when is_binary(value) <- get_in(socket.assigns.editor_inputs, [index, format]),
         {:ok, normalized_hex} <- parse_color_value(format, value),
         updated_palette <- replace_palette_color(palette, index, normalized_hex) do
      {:noreply,
       socket
       |> clear_editor_error(index)
       |> persist_palette(updated_palette)
       |> assign_editor(updated_palette)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose a user palette to edit")}

      {:error, error} ->
        {:noreply, put_editor_error(socket, index, error)}
    end
  end

  def handle_event("update_new_color_value", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_color_value, value)}
  end

  def handle_event("add_editor_color", %{"color" => color}, socket) do
    with %Palette{} = palette <- socket.assigns.editing_palette,
         {:ok, normalized_hex} <- ColorFormat.normalize_hex(color),
         updated_palette <- %{palette | colors: palette.colors ++ [normalized_hex]} do
      {:noreply,
       socket
       |> assign(:new_color_value, "#FFFFFF")
       |> persist_palette(updated_palette)
       |> assign_editor(updated_palette)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose a user palette to edit")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("remove_editor_color", %{"index" => index}, socket) do
    case socket.assigns.editing_palette do
      %Palette{} = palette ->
        # Refuse to empty the palette: both LiveViews guard `active_palette_loaded`
        # on `colors != []`, so an empty palette would silently fall back to
        # defaults on `/` even though the user just selected it via "Use in Grid".
        if length(palette.colors) <= 1 do
          {:noreply, put_flash(socket, :error, "Palettes must have at least one color")}
        else
          updated_palette = %{palette | colors: List.delete_at(palette.colors, String.to_integer(index))}

          {:noreply,
           socket
           |> persist_palette(updated_palette)
           |> assign_editor(updated_palette)}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a user palette to edit")}
    end
  end

  def handle_event("move_color", %{"index" => index, "direction" => direction}, socket) do
    case socket.assigns.editing_palette do
      %Palette{} = palette ->
        updated_palette = %{palette | colors: move_color(palette.colors, String.to_integer(index), direction)}

        {:noreply,
         socket
         |> persist_palette(updated_palette)
         |> assign_editor(updated_palette)}

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a user palette to edit")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto p-6 space-y-6" phx-hook="PaletteStorage" id="palette-storage">
      <div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Palette Management</h1>
          <p class="mt-2 text-sm text-gray-600">
            Duplicate presets, maintain saved palettes, and compare HEX, RGB, HSL, and HSV side by side while editing.
          </p>
        </div>
        <div class="flex gap-3">
          <.link
            navigate={~p"/"}
            class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            Return to Grid
          </.link>
        </div>
      </div>

      <div class="rounded-xl border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-900">
        <span class="font-semibold">Grid selection:</span>
        <%= if @active_palette do %>
          {@active_palette.name}
          <%= if @active_palette.is_preset do %>
            <span>(preset)</span>
          <% end %>
        <% else %>
          Custom unsaved colors
        <% end %>
      </div>

      <div class="grid gap-6 xl:grid-cols-[24rem_minmax(0,1fr)]">
        <section class="space-y-6">
          <div class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <h2 class="text-lg font-semibold text-gray-900">Create Palette</h2>
            <p class="mt-1 text-sm text-gray-600">
              New palettes start from the colors currently selected for the grid.
            </p>

            <form phx-submit="create_palette" class="mt-4 flex gap-2">
              <input
                type="text"
                name="name"
                value={@new_palette_name}
                phx-change="update_new_palette_name"
                placeholder="Palette name"
                class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
              <button
                type="submit"
                class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
              >
                Create
              </button>
            </form>
          </div>

          <div class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-gray-900">Preset Palettes</h2>
              <span class="text-xs uppercase tracking-wide text-gray-500">Read only</span>
            </div>

            <div class="mt-4 space-y-3">
              <%= for palette <- @preset_palettes do %>
                <div class="rounded-xl border border-gray-200 p-4">
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <h3 class="font-semibold text-gray-900">{palette.name}</h3>
                      <p class="mt-1 text-xs text-gray-500">
                        Duplicate to create an editable user palette.
                      </p>
                    </div>
                    <%= if @active_palette && @active_palette.name == palette.name do %>
                      <span class="rounded-full bg-blue-100 px-2 py-1 text-xs font-medium text-blue-800">
                        Active
                      </span>
                    <% end %>
                  </div>

                  <div class="mt-3 flex flex-wrap gap-2">
                    <%= for color <- Enum.take(palette.colors, 8) do %>
                      <div
                        class="h-8 w-8 rounded-md border border-gray-200"
                        title={color}
                        style={"background-color: #{color}"}
                      >
                      </div>
                    <% end %>
                    <%= if length(palette.colors) > 8 do %>
                      <div class="flex h-8 items-center text-xs text-gray-500">
                        +{length(palette.colors) - 8}
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-4 flex flex-wrap gap-2">
                    <button
                      phx-click="use_palette"
                      phx-value-palette={Jason.encode!(palette)}
                      class="rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700"
                    >
                      Use in Grid
                    </button>
                    <button
                      phx-click="duplicate_palette"
                      phx-value-palette={Jason.encode!(palette)}
                      class="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50"
                    >
                      Duplicate
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <div class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-gray-900">Your Palettes</h2>
              <span class="text-xs text-gray-500">{length(@saved_palettes)} saved</span>
            </div>

            <div :if={@saved_palettes == []} class="mt-4 rounded-xl border border-dashed border-gray-300 p-4 text-sm text-gray-500">
              No user palettes yet.
            </div>

            <div :if={@saved_palettes != []} class="mt-4 space-y-3">
              <%= for palette <- @saved_palettes do %>
                <div class="rounded-xl border border-gray-200 p-4">
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <h3 class="font-semibold text-gray-900">{palette.name}</h3>
                      <p class="mt-1 text-xs text-gray-500">
                        {length(palette.colors)} colors
                      </p>
                    </div>
                    <div class="flex gap-2">
                      <%= if @active_palette && @active_palette.name == palette.name do %>
                        <span class="rounded-full bg-blue-100 px-2 py-1 text-xs font-medium text-blue-800">
                          Active
                        </span>
                      <% end %>
                      <%= if @editing_palette && @editing_palette.name == palette.name do %>
                        <span class="rounded-full bg-amber-100 px-2 py-1 text-xs font-medium text-amber-800">
                          Editing
                        </span>
                      <% end %>
                    </div>
                  </div>

                  <div class="mt-3 flex flex-wrap gap-2">
                    <%= for color <- Enum.take(palette.colors, 8) do %>
                      <div
                        class="h-8 w-8 rounded-md border border-gray-200"
                        title={color}
                        style={"background-color: #{color}"}
                      >
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-4 flex flex-wrap gap-2">
                    <button
                      phx-click="use_palette"
                      phx-value-palette={Jason.encode!(palette)}
                      class="rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700"
                    >
                      Use in Grid
                    </button>
                    <button
                      phx-click="open_palette"
                      phx-value-palette={Jason.encode!(palette)}
                      class="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="duplicate_palette"
                      phx-value-palette={Jason.encode!(palette)}
                      class="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50"
                    >
                      Duplicate
                    </button>
                    <button
                      phx-click="delete_palette"
                      phx-value-name={palette.name}
                      class="rounded-lg border border-red-200 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>

        <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="text-lg font-semibold text-gray-900">Palette Editor</h2>
              <p class="mt-1 text-sm text-gray-600">
                Edit one color in any supported format and the others will update to match.
              </p>
            </div>
            <%= if @editing_palette do %>
              <button
                phx-click="use_palette"
                phx-value-palette={Jason.encode!(@editing_palette)}
                class="rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700"
              >
                Use in Grid
              </button>
            <% end %>
          </div>

          <%= if @editing_palette do %>
            <div class="mt-5 rounded-xl border border-gray-200 bg-gray-50 p-4">
              <form phx-submit="rename_palette" class="flex flex-col gap-3 md:flex-row md:items-end">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700">Palette name</label>
                  <input
                    type="text"
                    name="name"
                    value={@editing_name}
                    phx-change="update_editor_name_input"
                    class="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                  />
                </div>
                <button
                  type="submit"
                  class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
                >
                  Rename
                </button>
              </form>

              <form phx-submit="add_editor_color" class="mt-4 flex gap-2">
                <input
                  type="text"
                  name="color"
                  value={@new_color_value}
                  phx-change="update_new_color_value"
                  placeholder="#FFFFFF"
                  class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm font-mono"
                />
                <button
                  type="submit"
                  class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-semibold text-gray-700 hover:bg-white"
                >
                  Add Color
                </button>
              </form>
            </div>

            <div class="mt-5 space-y-4">
              <%= for {color, index} <- Enum.with_index(@editing_palette.colors) do %>
                <% row_key = Integer.to_string(index) %>
                <div class="rounded-2xl border border-gray-200 p-4">
                  <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
                    <div class="flex items-center gap-4">
                      <div
                        class="h-16 w-16 rounded-xl border border-gray-200"
                        style={"background-color: #{color}"}
                      >
                      </div>
                      <div>
                        <p class="text-sm font-semibold text-gray-900">Color {index + 1}</p>
                        <p class="mt-1 font-mono text-xs text-gray-500">{color}</p>
                      </div>
                    </div>

                    <div class="flex flex-wrap gap-2">
                      <button
                        phx-click="move_color"
                        phx-value-index={index}
                        phx-value-direction="up"
                        disabled={index == 0}
                        class="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 disabled:opacity-40"
                      >
                        Move Up
                      </button>
                      <button
                        phx-click="move_color"
                        phx-value-index={index}
                        phx-value-direction="down"
                        disabled={index == length(@editing_palette.colors) - 1}
                        class="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 disabled:opacity-40"
                      >
                        Move Down
                      </button>
                      <button
                        phx-click="remove_editor_color"
                        phx-value-index={index}
                        disabled={length(@editing_palette.colors) <= 1}
                        class="rounded-lg border border-red-200 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-40"
                      >
                        Remove
                      </button>
                    </div>
                  </div>

                  <div class="mt-4 grid gap-3 md:grid-cols-2">
                    <%= for {format, label} <- [{"hex", "HEX"}, {"rgb", "RGB"}, {"hsl", "HSL"}, {"hsv", "HSV"}] do %>
                      <div class="rounded-xl border border-gray-200 p-3">
                        <label class="block text-xs font-semibold uppercase tracking-wide text-gray-500">
                          {label}
                        </label>
                        <div class="mt-2 flex gap-2">
                          <input
                            type="text"
                            value={get_in(@editor_inputs, [row_key, format])}
                            phx-change="update_editor_field"
                            phx-value-index={row_key}
                            phx-value-format={format}
                            name="value"
                            class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm font-mono"
                          />
                          <button
                            phx-click="apply_color_format"
                            phx-value-index={row_key}
                            phx-value-format={format}
                            class="rounded-lg bg-zinc-900 px-3 py-2 text-xs font-semibold text-white hover:bg-zinc-700"
                          >
                            Apply
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <p :if={Map.get(@editor_errors, row_key)} class="mt-3 text-sm text-red-700">
                    {Map.get(@editor_errors, row_key)}
                  </p>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="mt-5 rounded-2xl border border-dashed border-gray-300 p-8 text-sm text-gray-500">
              Choose a user palette to edit, or duplicate a preset to start from a built-in set.
            </div>
          <% end %>
        </section>
      </div>
    </div>
    """
  end

  defp normalize_saved_palettes(palettes) do
    palettes
    |> Enum.map(&Palette.from_json_map/1)
    |> Enum.filter(&match?({:ok, _palette}, &1))
    |> Enum.map(fn {:ok, palette} -> palette end)
    |> Enum.reject(fn palette -> palette.is_preset end)
    |> Enum.sort_by(fn palette -> String.downcase(palette.name) end)
  end

  defp assign_editor(socket, %Palette{} = palette) do
    socket
    |> assign(:editing_palette, palette)
    |> assign(:editing_name, palette.name)
    |> assign(:editor_inputs, editor_inputs(palette.colors))
    |> assign(:editor_errors, %{})
  end

  defp editor_inputs(colors) do
    colors
    |> Enum.with_index()
    |> Map.new(fn {color, index} ->
      {Integer.to_string(index), color_input_values(color)}
    end)
  end

  defp color_input_values(color) do
    {:ok, rgb} = ColorFormat.hex_to_rgb(color)
    {:ok, hsl} = ColorFormat.hex_to_hsl(color)
    {:ok, hsv} = ColorFormat.hex_to_hsv(color)

    %{
      "hex" => color,
      "rgb" => ColorFormat.format_rgb(rgb),
      "hsl" => ColorFormat.format_hsl(hsl),
      "hsv" => ColorFormat.format_hsv(hsv)
    }
  end

  defp validate_user_palette_name(socket, name, opts \\ []) do
    except_name = Keyword.get(opts, :except_name)

    with {:ok, validated_name} <- PaletteStorage.validate_palette_name(name),
         false <- saved_palette_name_taken?(socket.assigns.saved_palettes, validated_name, except_name) do
      {:ok, validated_name}
    else
      true -> {:error, "Name already exists"}
      {:error, _reason} = error -> error
    end
  end

  defp saved_palette_name_taken?(palettes, name, except_name) do
    Enum.any?(palettes, fn palette ->
      palette.name == name and palette.name != except_name
    end)
  end

  defp parse_color_value("hex", value), do: ColorFormat.normalize_hex(value)

  defp parse_color_value("rgb", value) do
    with {:ok, rgb} <- ColorFormat.parse_rgb(value) do
      ColorFormat.rgb_to_hex(rgb)
    end
  end

  defp parse_color_value("hsl", value) do
    with {:ok, hsl} <- ColorFormat.parse_hsl(value) do
      ColorFormat.hsl_to_hex(hsl)
    end
  end

  defp parse_color_value("hsv", value) do
    with {:ok, hsv} <- ColorFormat.parse_hsv(value) do
      ColorFormat.hsv_to_hex(hsv)
    end
  end

  defp parse_color_value(_format, _value), do: {:error, "Unsupported color format"}

  defp replace_palette_color(%Palette{} = palette, index, color) do
    %{palette | colors: List.replace_at(palette.colors, String.to_integer(index), color)}
  end

  defp move_color(colors, index, "up") when index > 0 do
    item = Enum.at(colors, index)
    colors |> List.delete_at(index) |> List.insert_at(index - 1, item)
  end

  defp move_color(colors, index, "down") when index < length(colors) - 1 do
    item = Enum.at(colors, index)
    colors |> List.delete_at(index) |> List.insert_at(index + 1, item)
  end

  defp move_color(colors, _index, _direction), do: colors

  defp put_in_editor_input(socket, index, format, value) do
    current_row = Map.get(socket.assigns.editor_inputs, index, %{})
    updated_inputs = Map.put(socket.assigns.editor_inputs, index, Map.put(current_row, format, value))
    assign(socket, :editor_inputs, updated_inputs)
  end

  defp clear_editor_error(socket, index) do
    assign(socket, :editor_errors, Map.delete(socket.assigns.editor_errors, index))
  end

  defp put_editor_error(socket, index, error) do
    assign(socket, :editor_errors, Map.put(socket.assigns.editor_errors, index, error))
  end

  defp persist_palette(socket, %Palette{} = palette) do
    socket
    |> assign(:saved_palettes, upsert_saved_palette(socket.assigns.saved_palettes, palette))
    |> push_event("save_palette", %{
      name: palette.name,
      colors: palette.colors,
      created_at: palette.created_at
    })
    |> maybe_activate_after_edit(palette)
  end

  defp upsert_saved_palette(saved_palettes, %Palette{} = palette) do
    saved_palettes
    |> Enum.reject(&(&1.name == palette.name))
    |> Kernel.++([palette])
    |> Enum.sort_by(fn saved_palette -> String.downcase(saved_palette.name) end)
  end

  defp rename_saved_palette(saved_palettes, old_name, %Palette{} = renamed) do
    saved_palettes
    |> Enum.reject(&(&1.name == old_name))
    |> Kernel.++([renamed])
    |> Enum.sort_by(fn saved_palette -> String.downcase(saved_palette.name) end)
  end

  defp maybe_activate_after_edit(socket, %Palette{} = palette) do
    case socket.assigns.active_palette do
      %{name: name} when name == palette.name -> activate_palette(socket, palette)
      _other -> socket
    end
  end

  defp maybe_activate_after_rename(socket, %Palette{} = old_palette, %Palette{} = renamed_palette) do
    case socket.assigns.active_palette do
      %{name: name} when name == old_palette.name -> activate_palette(socket, renamed_palette)
      _other -> socket
    end
  end

  # A `name: nil` active palette represents the grid's custom unsaved
  # selection. Opening it in the editor would let the user "rename" or
  # "delete" something that has no entry in localStorage; downstream rename
  # events look up an existing palette by name, and `normalize_saved_palettes/1`
  # drops nameless entries, so those flows are silently broken. Treat nil
  # names as unsaved and only pre-populate the editor for real saved
  # palettes or for presets (where the editor is gated separately).
  defp maybe_assign_editor(socket, %Palette{name: nil} = _palette), do: socket
  defp maybe_assign_editor(socket, %Palette{is_preset: true}), do: socket
  defp maybe_assign_editor(socket, %Palette{} = palette), do: assign_editor(socket, palette)

  defp activate_palette(socket, %Palette{} = palette) do
    socket
    |> assign(:active_palette, palette_meta(palette))
    |> assign(:active_palette_colors, palette.colors)
    |> push_event("activate_palette", %{
      name: palette.name,
      colors: palette.colors,
      is_preset: palette.is_preset
    })
  end

  defp palette_meta(%Palette{} = palette) do
    %{name: palette.name, is_preset: palette.is_preset}
  end

  defp maybe_clear_editor(socket, name) do
    case socket.assigns.editing_palette do
      %Palette{name: ^name} ->
        socket
        |> assign(:editing_palette, nil)
        |> assign(:editing_name, "")
        |> assign(:editor_inputs, %{})
        |> assign(:editor_errors, %{})

      _other ->
        socket
    end
  end
end

defmodule ColorMatchingWeb.ColorPairLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.{ColorFormat, MeasuredColorPair, PrinterProfile}

  def mount(params, _session, socket) do
    printer_profiles = PrinterProfile.default_profiles()

    {:ok,
     socket
     |> assign(:pair_params, params)
     |> assign(:printer_profiles, printer_profiles)
     |> assign_pair(params, printer_profiles)}
  end

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
     |> assign_pair(socket.assigns.pair_params, printer_profiles)}
  end

  def handle_event("printer_profiles_loaded", _params, socket), do: {:noreply, socket}
  def handle_event("active_printer_profile_loaded", _params, socket), do: {:noreply, socket}

  defp assign_pair(socket, %{"a" => color_a, "b" => color_b} = params, printer_profiles) do
    with {:ok, first} <- build_color_details(color_a),
         {:ok, second} <- build_color_details(color_b) do
      printer_profile = PrinterProfile.from_query_params(params, printer_profiles)

      socket
      |> assign(:valid_pair?, true)
      |> assign(:colors, [first, second])
      |> assign(:measurement_context, build_measurement_context(params, printer_profile))
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        assign_invalid_pair(socket, reason)
    end
  end

  defp assign_pair(socket, _params, _printer_profiles) do
    assign_invalid_pair(socket, "Select a grid square to compare its color pair.")
  end

  defp assign_invalid_pair(socket, reason) do
    socket
    |> assign(:valid_pair?, false)
    |> assign(:colors, [])
    |> assign(:measurement_context, nil)
    |> assign(:error_message, reason)
  end

  defp build_color_details(color) do
    with {:ok, hex} <- ColorFormat.normalize_hex(color),
         {:ok, formats} <- ColorFormat.format_all(hex) do
      {:ok, %{hex: hex, formats: formats}}
    end
  end

  defp build_measurement_context(params, %PrinterProfile{} = printer_profile) do
    MeasuredColorPair.new(%{
      color_a: params["a"],
      color_b: params["b"],
      printer_profile: printer_profile,
      generated_sheet_id: params["sheet_id"]
    })
  end

  defp build_measurement_context(_params, _printer_profile), do: nil

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

  def render(assigns) do
    ~H"""
    <div
      id="pair-printer-profile-storage"
      class="mx-auto max-w-5xl p-6"
      phx-hook="PaletteStorage"
      data-load-palettes="false"
      data-load-printer-profiles="true"
    >
      <.link
        navigate={~p"/"}
        class="mb-6 inline-flex text-sm font-medium text-blue-700 hover:text-blue-900"
      >
        Back to grid
      </.link>

      <%= if @valid_pair? do %>
        <h1 class="mb-6 text-3xl font-bold text-gray-900">Color Pair</h1>

        <%= if @measurement_context do %>
          <section class="mb-6 rounded-lg border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-950">
            <div class="font-semibold">Measurement Context</div>
            <div>
              Printer profile: {PrinterProfile.display_name(@measurement_context.printer_profile)}
            </div>
            <div :if={@measurement_context.generated_sheet_id}>
              Generated sheet: {@measurement_context.generated_sheet_id}
            </div>
          </section>
        <% end %>

        <div class="mb-8 grid grid-cols-1 overflow-hidden rounded-lg border border-gray-200 md:grid-cols-2">
          <%= for color <- @colors do %>
            <div
              class="flex min-h-56 items-end p-5"
              style={"background-color: #{color.hex}"}
            >
              <span class="rounded bg-white/90 px-3 py-2 font-mono text-sm text-gray-950 shadow-sm">
                {color.hex}
              </span>
            </div>
          <% end %>
        </div>

        <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
          <%= for {color, index} <- Enum.with_index(@colors, 1) do %>
            <section class="rounded-lg border border-gray-200 bg-white">
              <div class="flex items-center gap-3 border-b border-gray-200 p-4">
                <div
                  class="h-10 w-10 rounded border border-gray-300"
                  style={"background-color: #{color.hex}"}
                >
                </div>
                <h2 class="text-lg font-semibold text-gray-900">Color {index}</h2>
              </div>

              <dl class="divide-y divide-gray-200">
                <%= for {label, value} <- color.formats do %>
                  <div class="grid grid-cols-[5rem_1fr] gap-4 p-4">
                    <dt class="text-sm font-medium text-gray-500">{label}</dt>
                    <dd class="break-all font-mono text-sm text-gray-900">{value}</dd>
                  </div>
                <% end %>
              </dl>
            </section>
          <% end %>
        </div>
      <% else %>
        <h1 class="mb-4 text-3xl font-bold text-gray-900">Color Pair</h1>
        <div class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          {@error_message}
        </div>
      <% end %>
    </div>
    """
  end
end

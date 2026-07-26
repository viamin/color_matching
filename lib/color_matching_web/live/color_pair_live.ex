defmodule ColorMatchingWeb.ColorPairLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.ColorFormat

  def mount(params, _session, socket) do
    {:ok, assign_pair(socket, params)}
  end

  defp assign_pair(socket, %{"a" => color_a, "b" => color_b}) do
    with {:ok, first} <- build_color_details(color_a),
         {:ok, second} <- build_color_details(color_b) do
      socket
      |> assign(:valid_pair?, true)
      |> assign(:colors, [first, second])
      |> assign(:error_message, nil)
    else
      {:error, reason} ->
        assign_invalid_pair(socket, reason)
    end
  end

  defp assign_pair(socket, _params) do
    assign_invalid_pair(socket, "Select a grid square to compare its color pair.")
  end

  defp assign_invalid_pair(socket, reason) do
    socket
    |> assign(:valid_pair?, false)
    |> assign(:colors, [])
    |> assign(:error_message, reason)
  end

  defp build_color_details(color) do
    with {:ok, hex} <- ColorFormat.normalize_hex(color),
         {:ok, formats} <- ColorFormat.format_all(hex) do
      {:ok, %{hex: hex, formats: formats}}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl p-6">
      <.link
        navigate={~p"/"}
        class="mb-6 inline-flex text-sm font-medium text-blue-700 hover:text-blue-900"
      >
        Back to grid
      </.link>

      <%= if @valid_pair? do %>
        <h1 class="mb-6 text-3xl font-bold text-gray-900">Color Pair</h1>

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

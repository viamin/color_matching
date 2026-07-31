defmodule ColorMatchingWeb.PrintedPairBrowserLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.PrintedPairBrowser

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Printed Pair Browser")}
  end

  def handle_params(params, _uri, socket) do
    filters = PrintedPairBrowser.normalize_filters(params)
    entries = PrintedPairBrowser.list_entries(filters)
    has_entries? = PrintedPairBrowser.any_active?()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:entries, entries)
     |> assign(:has_entries?, has_entries?)
     |> assign(:filter_options, PrintedPairBrowser.filter_options())}
  end

  def handle_event("change_filters", %{"filters" => params}, socket) do
    params = PrintedPairBrowser.to_query_params(params)

    {:noreply, push_patch(socket, to: ~p"/printed-pairs?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/printed-pairs")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl space-y-6 p-6">
      <div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <.link
            navigate={~p"/"}
            class="text-sm font-medium text-blue-700 hover:text-blue-900"
          >
            Back to grid
          </.link>
          <h1 class="mt-2 text-3xl font-bold text-gray-900">Printed Pair Browser</h1>
          <p class="mt-1 text-sm text-gray-600">
            Review manually classified printed pairs by illuminant, profile, palette, and sheet.
          </p>
        </div>
        <div class="rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-600 shadow-sm">
          Showing <span class="font-semibold text-gray-900">{length(@entries)}</span> result(s)
        </div>
      </div>

      <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
        <form id="printed-pair-filters" phx-change="change_filters" class="space-y-4">
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-6">
            <div>
              <label for="illuminant" class="block text-sm font-medium text-gray-700">
                Illuminant
              </label>
              <select
                id="illuminant"
                name="filters[illuminant]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">All illuminants</option>
                <%= for {label, value} <- @filter_options.illuminants do %>
                  <option value={value} selected={@filters.illuminant == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="classification" class="block text-sm font-medium text-gray-700">
                Classification
              </label>
              <select
                id="classification"
                name="filters[classification]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">All classifications</option>
                <%= for {label, value} <- @filter_options.classifications do %>
                  <option value={value} selected={@filters.classification == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="profile_id" class="block text-sm font-medium text-gray-700">
                Profile
              </label>
              <select
                id="profile_id"
                name="filters[profile_id]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">All profiles</option>
                <%= for {label, value} <- @filter_options.profiles do %>
                  <option value={value} selected={@filters.profile_id == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="palette_id" class="block text-sm font-medium text-gray-700">
                Palette
              </label>
              <select
                id="palette_id"
                name="filters[palette_id]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">All palettes</option>
                <%= for {label, value} <- @filter_options.palettes do %>
                  <option value={value} selected={@filters.palette_id == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="test_sheet_id" class="block text-sm font-medium text-gray-700">
                Test sheet
              </label>
              <select
                id="test_sheet_id"
                name="filters[test_sheet_id]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">All sheets</option>
                <%= for {label, value} <- @filter_options.test_sheets do %>
                  <option value={value} selected={@filters.test_sheet_id == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="sort" class="block text-sm font-medium text-gray-700">
                Sort
              </label>
              <select
                id="sort"
                name="filters[sort]"
                class="mt-1 block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <%= for {label, value} <- PrintedPairBrowser.sort_options() do %>
                  <option value={value} selected={@filters.sort == value}>{label}</option>
                <% end %>
              </select>
            </div>
          </div>

          <div class="flex items-center justify-end">
            <button
              type="button"
              phx-click="clear_filters"
              class="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Clear filters
            </button>
          </div>
        </form>
      </section>

      <%= cond do %>
        <% not @has_entries? -> %>
          <section class="rounded-2xl border border-dashed border-gray-300 bg-white p-6 text-sm text-gray-600 shadow-sm">
            <p class="font-semibold text-gray-900">No printed pair classifications yet.</p>
            <p class="mt-1">
              Classified printed pairs will appear here once a profile, illuminant, and manual
              classification have been recorded.
            </p>
          </section>
        <% @entries == [] -> %>
          <section class="rounded-2xl border border-dashed border-amber-300 bg-amber-50 p-6 text-sm text-amber-900 shadow-sm">
            <p class="font-semibold">No results match the current filters.</p>
            <p class="mt-1">Try clearing one or more filters to widen the browser.</p>
          </section>
        <% true -> %>
          <section class="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200 text-sm">
                <thead class="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                  <tr>
                    <th class="px-4 py-3">Pair</th>
                    <th class="px-4 py-3">Swatches</th>
                    <th class="px-4 py-3">Illuminant</th>
                    <th class="px-4 py-3">Profile</th>
                    <th class="px-4 py-3">Palette / Sheet</th>
                    <th class="px-4 py-3">Classification</th>
                    <th class="px-4 py-3">ΔE00</th>
                    <th class="px-4 py-3">Updated</th>
                    <th class="px-4 py-3">Notes</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200">
                  <%= for entry <- @entries do %>
                    <tr id={"printed-pair-#{entry.id}"} class="align-top">
                      <td class="px-4 py-4">
                        <p class="font-mono text-xs text-gray-900">{entry.pair_id}</p>
                        <p class="mt-1 text-xs text-gray-500">Row {entry.row}, Col {entry.col}</p>
                      </td>
                      <td class="px-4 py-4">
                        <div class="flex items-center gap-3">
                          <div class="flex items-center gap-2">
                            <span
                              class="h-6 w-6 rounded border border-gray-300"
                              style={"background-color: #{entry.swatch_a}"}
                            ></span>
                            <span class="font-mono text-xs text-gray-700">{entry.swatch_a}</span>
                          </div>
                          <div class="flex items-center gap-2">
                            <span
                              class="h-6 w-6 rounded border border-gray-300"
                              style={"background-color: #{entry.swatch_b}"}
                            ></span>
                            <span class="font-mono text-xs text-gray-700">{entry.swatch_b}</span>
                          </div>
                        </div>
                      </td>
                      <td class="px-4 py-4 text-gray-700">{entry.illuminant_label}</td>
                      <td class="px-4 py-4 text-gray-700">{entry.profile_name}</td>
                      <td class="px-4 py-4">
                        <p class="text-gray-900">{entry.palette_name}</p>
                        <p class="mt-1 font-mono text-xs text-gray-500">
                          {entry.test_sheet_lookup_code}
                        </p>
                      </td>
                      <td class="px-4 py-4">
                        <span class={classification_badge_class(entry.classification)}>
                          {entry.classification_label}
                        </span>
                      </td>
                      <td class="px-4 py-4 font-mono text-xs text-gray-700">{entry.delta_e_label}</td>
                      <td class="px-4 py-4 text-xs text-gray-600">
                        {format_datetime(entry.updated_at)}
                      </td>
                      <td class="px-4 py-4">
                        <%= if entry.notes? do %>
                          <details class="max-w-xs">
                            <summary class="cursor-pointer text-xs font-medium text-blue-700">
                              Notes available
                            </summary>
                            <p class="mt-2 whitespace-pre-wrap text-xs text-gray-600">
                              {entry.notes}
                            </p>
                          </details>
                        <% else %>
                          <span class="text-xs text-gray-400">No</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>
      <% end %>
    </div>
    """
  end

  defp classification_badge_class("strong_metamer") do
    "rounded-full bg-emerald-100 px-2 py-1 text-xs font-medium text-emerald-800"
  end

  defp classification_badge_class("weak_metamer") do
    "rounded-full bg-amber-100 px-2 py-1 text-xs font-medium text-amber-800"
  end

  defp classification_badge_class(_classification) do
    "rounded-full bg-rose-100 px-2 py-1 text-xs font-medium text-rose-800"
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp format_datetime(_datetime), do: "Unknown"
end

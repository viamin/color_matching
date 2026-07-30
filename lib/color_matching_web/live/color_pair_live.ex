defmodule ColorMatchingWeb.ColorPairLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.{ColorFormat, MeasuredColorPair, Persistence, PrinterProfile}
  alias ColorMatching.Persistence.PrintedPairClassification

  @illuminant_labels %{
    "lps" => "LPS",
    "red" => "Red",
    "green" => "Green",
    "blue" => "Blue"
  }
  @classification_labels %{
    "strong_metamer" => "Strong metamer",
    "weak_metamer" => "Weak metamer",
    "contrasting" => "Contrasting"
  }

  def mount(params, _session, socket) do
    printer_profiles = PrinterProfile.default_profiles()

    {:ok,
     socket
     |> assign(:pair_params, params)
     |> assign(:printer_profiles, printer_profiles)
     |> assign(:illuminants, PrintedPairClassification.illuminants())
     |> assign(:classification_options, classification_options())
     |> assign_pair(params, printer_profiles)}
  end

  def handle_event("printer_profiles_loaded", %{"profiles" => profiles}, socket)
      when is_list(profiles) do
    printer_profiles =
      profiles
      |> Enum.map(&PrinterProfile.from_map/1)
      |> Enum.reject(&is_nil/1)
      |> PrinterProfile.merge_with_defaults()

    {:noreply,
     socket
     |> assign(:printer_profiles, printer_profiles)
     |> assign_pair(socket.assigns.pair_params, printer_profiles)}
  end

  def handle_event("printer_profiles_loaded", _params, socket), do: {:noreply, socket}
  def handle_event("active_printer_profile_loaded", _params, socket), do: {:noreply, socket}

  def handle_event("save_classification", %{"classification" => params}, socket) do
    case classification_scope(socket, Map.get(params, "illuminant")) do
      {:ok, scope} ->
        save_classification(socket, scope, params)

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("clear_classification", %{"illuminant" => illuminant}, socket) do
    case classification_scope(socket, illuminant) do
      {:ok, scope} ->
        Persistence.clear_printed_pair_classification(
          scope.pair.id,
          scope.reproduction_profile.id,
          scope.illuminant
        )

        {:noreply,
         socket
         |> assign_classification_state()
         |> put_flash(:info, "Cleared #{illuminant_label(scope.illuminant)} classification")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp assign_pair(socket, %{"a" => color_a, "b" => color_b} = params, printer_profiles) do
    with {:ok, first} <- build_color_details(color_a),
         {:ok, second} <- build_color_details(color_b),
         {:ok, pair_metrics} <- ColorFormat.format_pair_metrics(first.hex, second.hex) do
      printer_profile = PrinterProfile.from_query_params(params, printer_profiles)
      classification_context = build_classification_context(params, first.hex, second.hex)

      socket
      |> assign(:valid_pair?, true)
      |> assign(:colors, [first, second])
      |> assign(:measurement_context, build_measurement_context(params, printer_profile))
      |> assign(:classification_context, classification_context)
      |> assign(:pair_metrics, pair_metrics)
      |> assign(:error_message, nil)
      |> assign_classification_state()
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
    |> assign(:classification_context, nil)
    |> assign(:classification_forms, %{})
    |> assign(:pair_metrics, [])
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

  defp build_classification_context(params, color_a_hex, color_b_hex) do
    sheet = persisted_sheet(params)
    pair = persisted_pair(params, sheet)
    reproduction_profile = persisted_reproduction_profile(params, sheet)

    if pair && reproduction_profile && pair_colors_match?(pair, color_a_hex, color_b_hex) do
      %{pair: pair, reproduction_profile: reproduction_profile}
    end
  end

  defp persisted_sheet(%{"sheet_id" => sheet_id}) when is_binary(sheet_id) and sheet_id != "" do
    Persistence.get_test_sheet_by_lookup_code(sheet_id)
  end

  defp persisted_sheet(_params), do: nil

  defp persisted_pair(%{"pair_id" => pair_id}, sheet)
       when is_binary(pair_id) and pair_id != "" and not is_nil(sheet) do
    Enum.find(sheet.pairs, &(&1.pair_id == pair_id))
  end

  defp persisted_pair(_params, _sheet), do: nil

  defp persisted_reproduction_profile(params, sheet) do
    case first_integer_param(params, ["reproduction_profile_id", "printer_profile_id"]) do
      {:ok, id} -> Persistence.get_printer_profile(id)
      :error -> sheet && sheet.printer_profile
    end
  end

  defp first_integer_param(params, keys) do
    Enum.reduce_while(keys, :error, fn key, _acc ->
      params
      |> Map.get(key)
      |> parse_integer_param()
      |> case do
        {:ok, id} -> {:halt, {:ok, id}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp parse_integer_param(value) when is_binary(value) and value != "" do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  defp parse_integer_param(_value), do: :error

  defp pair_colors_match?(pair, color_a_hex, color_b_hex) do
    pair.color_a_hex == color_a_hex and pair.color_b_hex == color_b_hex
  end

  defp assign_classification_state(socket) do
    forms =
      socket.assigns.illuminants
      |> Enum.map(fn illuminant ->
        {illuminant, classification_form(socket.assigns.classification_context, illuminant)}
      end)
      |> Map.new()

    assign(socket, :classification_forms, forms)
  end

  defp classification_form(nil, _illuminant), do: %{classification: "", notes: ""}

  defp classification_form(context, illuminant) do
    case Persistence.get_active_printed_pair_classification(
           context.pair.id,
           context.reproduction_profile.id,
           illuminant
         ) do
      nil ->
        %{classification: "", notes: ""}

      classification ->
        %{classification: classification.classification, notes: classification.notes || ""}
    end
  end

  defp classification_scope(socket, illuminant) do
    with %{pair: pair, reproduction_profile: reproduction_profile} <-
           socket.assigns.classification_context,
         true <- illuminant in socket.assigns.illuminants do
      {:ok, %{pair: pair, reproduction_profile: reproduction_profile, illuminant: illuminant}}
    else
      nil ->
        {:error,
         "Manual classification is available only for a persisted printed pair and reproduction profile."}

      false ->
        {:error, "Unknown illuminant"}
    end
  end

  defp save_classification(socket, scope, params) do
    case blank_to_nil(Map.get(params, "classification")) do
      nil ->
        Persistence.clear_printed_pair_classification(
          scope.pair.id,
          scope.reproduction_profile.id,
          scope.illuminant
        )

        {:noreply,
         socket
         |> assign_classification_state()
         |> put_flash(:info, "Cleared #{illuminant_label(scope.illuminant)} classification")}

      classification ->
        attrs = %{
          test_sheet_pair_id: scope.pair.id,
          reproduction_profile_id: scope.reproduction_profile.id,
          illuminant: scope.illuminant,
          classification: classification,
          notes: blank_to_nil(Map.get(params, "notes"))
        }

        case Persistence.set_printed_pair_classification(attrs) do
          {:ok, _classification} ->
            {:noreply,
             socket
             |> assign_classification_state()
             |> put_flash(:info, "Saved #{illuminant_label(scope.illuminant)} classification")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, classification_error_message(changeset))}
        end
    end
  end

  defp classification_error_message(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _rest] -> "#{field} #{message}"
      [] -> "Could not save classification"
    end
  end

  defp classification_options do
    [
      {"Unset", ""},
      {"Strong metamer", "strong_metamer"},
      {"Weak metamer", "weak_metamer"},
      {"Contrasting", "contrasting"}
    ]
  end

  defp illuminant_label(illuminant), do: Map.fetch!(@illuminant_labels, illuminant)

  defp classification_label(nil), do: "Unset"
  defp classification_label(""), do: "Unset"

  defp classification_label(classification),
    do: Map.fetch!(@classification_labels, classification)

  defp reproduction_profile_name(profile) do
    "#{profile.printer_make_model} on #{profile.paper_type}"
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

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

        <section class="mb-6 rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
          <div class="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
            <div>
              <h2 class="text-lg font-semibold text-gray-900">Manual Illuminant Classification</h2>
              <p class="text-sm text-gray-600">
                Classify the pair's apparent brightness response for each illuminant. Saving
                updates the active classification for this pair and physical reproduction profile
                without leaving the page.
              </p>
            </div>
            <%= if @classification_context do %>
              <div class="rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-950">
                <div class="font-semibold">Reproduction profile for classification</div>
                <div>{reproduction_profile_name(@classification_context.reproduction_profile)}</div>
                <div class="text-sky-800">
                  Ink: {@classification_context.reproduction_profile.ink_type}
                </div>
              </div>
            <% end %>
          </div>

          <%= if @classification_context do %>
            <div class="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
              <%= for illuminant <- @illuminants do %>
                <% form = Map.fetch!(@classification_forms, illuminant) %>
                <article
                  id={"classification-#{illuminant}"}
                  class="rounded-lg border border-gray-200 bg-gray-50 p-4"
                >
                  <div class="flex items-center justify-between gap-3">
                    <h3 class="text-sm font-semibold text-gray-900">
                      {illuminant_label(illuminant)}
                    </h3>
                    <span class="rounded-full bg-white px-2 py-1 text-xs font-medium text-gray-700">
                      {classification_label(form.classification)}
                    </span>
                  </div>

                  <.form for={%{}} as={:classification} phx-submit="save_classification" class="mt-3">
                    <input type="hidden" name="classification[illuminant]" value={illuminant} />

                    <label class="block text-xs font-semibold uppercase tracking-wide text-gray-500">
                      Illuminant response
                    </label>
                    <select
                      name="classification[classification]"
                      class="mt-1 block w-full rounded-md border border-gray-300 bg-white text-sm shadow-sm focus:border-zinc-400 focus:ring-0"
                    >
                      <%= for {label, value} <- @classification_options do %>
                        <option value={value} selected={form.classification == value}>
                          {label}
                        </option>
                      <% end %>
                    </select>

                    <label class="mt-3 block text-xs font-semibold uppercase tracking-wide text-gray-500">
                      Notes (optional)
                    </label>
                    <input
                      type="text"
                      name="classification[notes]"
                      value={form.notes}
                      placeholder="Observed brightness shift, flare, edge tint, etc."
                      class="mt-1 block w-full rounded-md border border-gray-300 bg-white text-sm shadow-sm focus:border-zinc-400 focus:ring-0"
                    />

                    <div class="mt-3 flex items-center gap-2">
                      <button
                        type="submit"
                        class="rounded-md bg-gray-900 px-3 py-2 text-sm font-medium text-white hover:bg-gray-800"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        phx-click="clear_classification"
                        phx-value-illuminant={illuminant}
                        class="rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100"
                      >
                        Clear
                      </button>
                    </div>
                  </.form>
                </article>
              <% end %>
            </div>
          <% else %>
            <div class="mt-4 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
              Manual classification becomes available when this page is opened for a persisted
              printed pair and reproduction profile.
            </div>
          <% end %>
        </section>

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

        <section class="mt-6 rounded-lg border border-gray-200 bg-white">
          <div class="border-b border-gray-200 p-4">
            <h2 class="text-lg font-semibold text-gray-900">Pair Metrics</h2>
          </div>

          <dl class="divide-y divide-gray-200">
            <%= for {label, value} <- @pair_metrics do %>
              <div class="grid grid-cols-[11rem_1fr] gap-4 p-4">
                <dt class="text-sm font-medium text-gray-500">{label}</dt>
                <dd class="break-all font-mono text-sm text-gray-900">{value}</dd>
              </div>
            <% end %>
          </dl>
        </section>
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

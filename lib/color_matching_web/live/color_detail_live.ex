defmodule ColorMatchingWeb.ColorDetailLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.Persistence
  alias ColorMatching.Persistence.{IlluminantMeasurement, PaletteColor, PrinterProfile}
  alias ColorMatching.ResponseVector

  @light_source_labels %{
    "white" => "White",
    "red" => "Red",
    "green" => "Green",
    "blue" => "Blue",
    "lps" => "LPS"
  }

  def mount(params, _session, socket) do
    case load_color(params) do
      {:ok, palette_color} ->
        printer_profiles = Persistence.list_printer_profiles()
        initial_printer_profile = initial_printer_profile(params, printer_profiles)

        {:ok,
         socket
         |> assign(:page_title, color_page_title(palette_color))
         |> assign(:palette_color, palette_color)
         |> assign(:printer_profiles, printer_profiles)
         |> assign(:printer_profile, initial_printer_profile)
         |> assign(:response_vector, build_response_vector(palette_color, initial_printer_profile))
         |> assign(:latest_measurements, build_latest_measurements(palette_color, initial_printer_profile))
         |> assign(:light_source_labels, @light_source_labels)
         |> assign(:measurement_form, empty_measurement_form())
         |> assign(:form_errors, %{})
         |> assign(:not_found, false)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:page_title, "Color not found")
         |> assign(:not_found, true)
         |> put_flash(:error, "Color not found")}
    end
  end

  def handle_event("select_printer_profile", %{"printer_profile_id" => raw_id}, socket) do
    with {:ok, printer_profile_id} <- parse_printer_profile_id(raw_id),
         %PrinterProfile{} = printer_profile <-
           Enum.find(socket.assigns.printer_profiles, &(&1.id == printer_profile_id)) do
      palette_color = socket.assigns.palette_color

      {:noreply,
       socket
       |> assign(:printer_profile, printer_profile)
       |> assign(:response_vector, build_response_vector(palette_color, printer_profile))
       |> assign(:latest_measurements, build_latest_measurements(palette_color, printer_profile))}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid printer profile id")}

      nil ->
        {:noreply, put_flash(socket, :error, "Unknown printer profile")}
    end
  end

  def handle_event("update_measurement_brightness", params, socket) do
    value = input_value(params, "brightness")

    {:noreply,
     socket
     |> put_in_measurement_form(value)
     |> clear_form_error()}
  end

  def handle_event("submit_measurement", %{"light_source" => light_source} = params, socket)
      when light_source in Map.keys(@light_source_labels) do
    palette_color = socket.assigns.palette_color
    printer_profile = socket.assigns.printer_profile

    attrs = build_measurement_attrs(palette_color, printer_profile, light_source, params)

    case Persistence.create_illuminant_measurement(attrs) do
      {:ok, _measurement} ->
        {:noreply,
         socket
         |> assign(:response_vector, build_response_vector(palette_color, printer_profile))
         |> assign(:latest_measurements, build_latest_measurements(palette_color, printer_profile))
         |> assign(:measurement_form, empty_measurement_form())
         |> put_flash(:info, "Recorded #{light_source_label(light_source)} measurement")}

      {:error, changeset} ->
        {:noreply, put_form_errors(socket, light_source, changeset)}
    end
  end

  def handle_event("submit_measurement", _params, socket) do
    {:noreply, put_flash(socket, :error, "Pick a light source before recording a measurement")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl space-y-6 p-6">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <.link
          navigate={~p"/palettes"}
          class="text-sm font-medium text-blue-700 hover:text-blue-900"
        >
          Back to palettes
        </.link>
        <h1 class="text-3xl font-bold text-gray-900">Color Detail</h1>
      </div>

      <div
        :if={@not_found}
        class="rounded-2xl border border-red-200 bg-red-50 p-5 text-sm text-red-800 shadow-sm"
      >
        <p class="font-semibold">Color not found.</p>
        <p class="mt-1">
          The requested palette color could not be located. Return to the palettes page to choose
          a different color.
        </p>
      </div>

      <%= if !@not_found do %>
        <section class="flex flex-col gap-4 rounded-2xl border border-gray-200 bg-white p-5 shadow-sm md:flex-row md:items-center">
        <div
          class="h-24 w-24 shrink-0 rounded-xl border border-gray-200"
          style={"background-color: #{@palette_color.hex_color}"}
        >
        </div>
        <div class="flex-1">
          <p class="font-mono text-lg text-gray-900">{@palette_color.hex_color}</p>
          <%= if @palette_color.display_label do %>
            <p class="mt-1 text-sm text-gray-700">{@palette_color.display_label}</p>
          <% end %>
          <p class="mt-1 text-sm text-gray-500">
            Palette: <span class="font-medium text-gray-700">{palette_name(@palette_color)}</span>
          </p>
        </div>
      </section>

      <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
        <h2 class="text-lg font-semibold text-gray-900">Printer Profile</h2>
        <p class="mt-1 text-sm text-gray-600">
          The response profile below is specific to the selected printer profile. Different profiles
          can produce different brightness readings for the same swatch.
        </p>

        <div class="mt-4">
          <label for="printer_profile_id" class="block text-sm font-medium text-gray-700">
            Active profile
          </label>
          <select
            id="printer_profile_id"
            name="printer_profile_id"
            phx-change="select_printer_profile"
            class="mt-1 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
          >
            <%= for profile <- @printer_profiles do %>
              <option value={profile.id} selected={profile.id == @printer_profile.id}>
                {printer_profile_display_name(profile)}
              </option>
            <% end %>
          </select>
        </div>

        <%= if @printer_profile do %>
          <dl class="mt-4 grid grid-cols-1 gap-3 text-sm text-gray-700 md:grid-cols-2">
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500">Paper</dt>
              <dd>{@printer_profile.paper_type}</dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500">Ink</dt>
              <dd>{@printer_profile.ink_type}</dd>
            </div>
            <div :if={@printer_profile.icc_profile}>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500">ICC profile</dt>
              <dd>{@printer_profile.icc_profile}</dd>
            </div>
            <div :if={@printer_profile.calibration_date}>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500">Calibrated</dt>
              <dd>{@printer_profile.calibration_date}</dd>
            </div>
          </dl>
        <% end %>
      </section>

      <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
        <h2 class="text-lg font-semibold text-gray-900">Illuminant Response Profile</h2>
        <p class="mt-1 text-sm text-gray-600">
          Latest measured brightness for each initial light source. Missing entries are shown
          explicitly because a zero reading and a missing reading are not the same thing.
        </p>

        <div class="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
          <%= for {source, brightness} <- @response_vector.brightness_map() do %>
            <% label = light_source_label(source) %>
            <article class="rounded-xl border border-gray-200 p-4">
              <header class="flex items-center justify-between">
                <h3 class="text-sm font-semibold text-gray-900">{label}</h3>
                <%= case brightness do %>
                  <% :missing -> %>
                    <span class="rounded-full bg-amber-100 px-2 py-1 text-xs font-medium text-amber-800">
                      Missing
                    </span>
                  <% value when is_float(value) -> %>
                    <span class="rounded-full bg-emerald-100 px-2 py-1 text-xs font-medium text-emerald-800">
                      {format_brightness(value)}
                    </span>
                <% end %>
              </header>

              <%= case Map.get(@latest_measurements, Atom.to_string(source)) do %>
                <% %IlluminantMeasurement{} = measurement -> %>
                  <dl class="mt-3 space-y-1 text-xs text-gray-600">
                    <%= if measurement.measured_at do %>
                      <div class="flex justify-between gap-3">
                        <dt class="text-gray-500">Measured at</dt>
                        <dd class="text-right text-gray-800">
                          {format_datetime(measurement.measured_at)}
                        </dd>
                      </div>
                    <% end %>
                    <%= if measurement.measurement_method do %>
                      <div class="flex justify-between gap-3">
                        <dt class="text-gray-500">Method</dt>
                        <dd class="text-right text-gray-800">{measurement.measurement_method}</dd>
                      </div>
                    <% end %>
                    <%= if measurement.measurement_device do %>
                      <div class="flex justify-between gap-3">
                        <dt class="text-gray-500">Device</dt>
                        <dd class="text-right text-gray-800">{measurement.measurement_device}</dd>
                      </div>
                    <% end %>
                    <%= if measurement.test_run_id do %>
                      <div class="flex justify-between gap-3">
                        <dt class="text-gray-500">Test run</dt>
                        <dd class="text-right font-mono text-gray-800">{measurement.test_run_id}</dd>
                      </div>
                    <% end %>
                    <%= if measurement.notes do %>
                      <div class="flex justify-between gap-3">
                        <dt class="text-gray-500">Notes</dt>
                        <dd class="text-right text-gray-800">{measurement.notes}</dd>
                      </div>
                    <% end %>
                  </dl>
                <% nil -> %>
                  <p class="mt-3 text-xs text-gray-500">
                    No measurement recorded for {label} on this profile yet.
                  </p>
              <% end %>
            </article>
          <% end %>
        </div>
      </section>

      <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
        <h2 class="text-lg font-semibold text-gray-900">Record Measurement</h2>
        <p class="mt-1 text-sm text-gray-600">
          Enter a brightness reading between 0.0 and 1.0 for any supported light source.
        </p>

        <form phx-submit="submit_measurement" class="mt-4 space-y-4">
          <div>
            <label for="measurement-light-source" class="block text-sm font-medium text-gray-700">
              Light source
            </label>
            <select
              id="measurement-light-source"
              name="light_source"
              class="mt-1 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
            >
              <%= for source <- IlluminantMeasurement.supported_light_sources() do %>
                <option value={source} selected={source == @measurement_form.light_source}>
                  {light_source_label(source)}
                </option>
              <% end %>
            </select>
          </div>

          <div>
            <label for="measurement-brightness" class="block text-sm font-medium text-gray-700">
              Brightness
            </label>
            <input
              id="measurement-brightness"
              type="number"
              name="brightness"
              step="0.01"
              min="0"
              max="1"
              value={@measurement_form.brightness}
              phx-change="update_measurement_brightness"
              class="mt-1 block w-full rounded-md border border-gray-300 shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
            />
            <%= case Map.get(@form_errors, "other") do %>
              <% errors when is_list(errors) -> %>
                <p :for={message <- errors} class="mt-1 text-xs text-red-700">
                  {message}
                </p>
              <% nil -> %>
            <% end %>
          </div>

          <button
            type="submit"
            disabled={@printer_profile == nil}
            class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700 disabled:opacity-40"
          >
            Record measurement
          </button>
        </form>
      </section>
      <% end %>
    </div>
    """
  end

  defp load_color(%{"palette_id" => palette_id, "color_id" => color_id}) do
    with {:ok, palette_id_int} <- parse_integer(palette_id),
         {:ok, color_id_int} <- parse_integer(color_id),
         %PaletteColor{} = palette_color <- find_palette_color(palette_id_int, color_id_int) do
      {:ok, palette_color}
    else
      _ -> {:error, :not_found}
    end
  end

  defp load_color(_params), do: {:error, :not_found}

  defp find_palette_color(palette_id, color_id) do
    case Persistence.get_palette_color(color_id) do
      %PaletteColor{palette_id: ^palette_id} = palette_color -> palette_color
      _other -> nil
    end
  end

  defp initial_printer_profile(_params, []), do: nil

  defp initial_printer_profile(%{"printer_profile_id" => raw_id}, printer_profiles) do
    case parse_printer_profile_id(raw_id) do
      {:ok, printer_profile_id} ->
        Enum.find(printer_profiles, &(&1.id == printer_profile_id))

      :error ->
        List.first(printer_profiles)
    end
  end

  defp initial_printer_profile(_params, printer_profiles), do: List.first(printer_profiles)

  defp parse_printer_profile_id(raw_id) when is_binary(raw_id) do
    case Integer.parse(raw_id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_printer_profile_id(raw_id) when is_integer(raw_id), do: {:ok, raw_id}

  defp parse_printer_profile_id(_raw_id), do: :error

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(_value), do: :error

  defp input_value(params, field) do
    Map.get(params, field) || Map.get(params, "value") || ""
  end

  defp build_response_vector(palette_color, %PrinterProfile{} = printer_profile) do
    Persistence.response_vector(palette_color, printer_profile)
  end

  defp build_response_vector(_palette_color, _printer_profile) do
    %ResponseVector{hex_color: "", printer_profile_id: nil}
  end

  defp build_latest_measurements(palette_color, %PrinterProfile{} = printer_profile) do
    palette_color.id
    |> Persistence.latest_illuminant_measurements_by_light_source(printer_profile.id)
  end

  defp build_latest_measurements(_palette_color, _printer_profile), do: %{}

  defp build_measurement_attrs(palette_color, printer_profile, light_source, params) do
    raw_brightness = Map.get(params, "brightness", "")

    %{
      palette_color_id: palette_color.id,
      printer_profile_id: printer_profile.id,
      light_source: light_source,
      normalized_brightness: raw_brightness
    }
  end

  defp empty_measurement_form do
    %{"light_source" => "white", "brightness" => ""}
  end

  defp put_in_measurement_form(socket, value) do
    # Only the brightness field is editable inline via phx-change, so
    # `light_source` and the other keys are intentionally preserved.
    updated = Map.put(socket.assigns.measurement_form, "brightness", value)
    assign(socket, :measurement_form, updated)
  end

  defp clear_form_error(socket) do
    assign(socket, :form_errors, Map.delete(socket.assigns.form_errors, "other"))
  end

  defp put_form_errors(socket, _light_source, changeset) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
      |> externalize_measurement_errors()

    assign(socket, :form_errors, errors)
  end

  defp externalize_measurement_errors(errors) do
    Map.new(errors, fn {key, value} -> {external_measurement_error_key(key), value} end)
  end

  defp external_measurement_error_key(:normalized_brightness), do: "other"
  defp external_measurement_error_key(:palette_color_id), do: "color_id"
  defp external_measurement_error_key(key), do: to_string(key)

  defp color_page_title(%PaletteColor{} = palette_color) do
    "Color · #{palette_color.hex_color}"
  end

  defp palette_name(%PaletteColor{palette: %{name: name}}) when is_binary(name), do: name
  defp palette_name(_palette_color), do: "Untitled"

  defp printer_profile_display_name(%PrinterProfile{} = profile) do
    parts =
      [profile.printer_make_model, profile.paper_type]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "Printer profile ##{profile.id}"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp light_source_label(source) when is_atom(source) do
    Map.fetch!(@light_source_labels, Atom.to_string(source))
  end

  defp light_source_label(source) when is_binary(source) do
    Map.fetch!(@light_source_labels, source)
  end

  defp format_brightness(value) when is_float(value) or is_integer(value) do
    :io_lib.format("~.3f", [value / 1]) |> IO.iodata_to_binary()
  end

  defp format_datetime(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_datetime(_datetime), do: "—"
end

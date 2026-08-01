defmodule ColorMatchingWeb.PrinterProfilesLive do
  use ColorMatchingWeb, :live_view

  alias ColorMatching.{Persistence, PrinterProfile}

  def mount(_params, _session, socket) do
    printer_profiles = persisted_printer_profiles()

    {:ok,
     socket
     |> assign(:printer_profiles, printer_profiles)
     |> assign(:active_printer_profile_id, List.first(printer_profiles).id)
     |> assign(:editing_profile_id, nil)
     |> assign(:printer_profile_form, empty_printer_profile_form())}
  end

  def handle_event("new_printer_profile", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_profile_id, nil)
     |> assign(:printer_profile_form, empty_printer_profile_form())}
  end

  def handle_event("edit_printer_profile", %{"profile_id" => profile_id}, socket) do
    profile = find_profile(socket.assigns.printer_profiles, profile_id)

    if profile && not PrinterProfile.default_profile?(profile) do
      {:noreply,
       socket
       |> assign(:editing_profile_id, profile.id)
       |> assign(:printer_profile_form, form_for(profile))}
    else
      {:noreply, put_flash(socket, :error, "Default printer profiles are read-only")}
    end
  end

  def handle_event("save_printer_profile", %{"profile" => params}, socket) do
    case editing_profile(socket) do
      %PrinterProfile{} = profile ->
        if PrinterProfile.persisted_profile?(profile) do
          update_persisted_profile(socket, profile, params)
        else
          save_browser_local_profile(socket, params, profile.id, "Updated")
        end

      nil ->
        save_browser_local_profile(socket, params, nil, "Created")
    end
  end

  def handle_event("select_active_printer_profile", %{"profile_id" => profile_id}, socket) do
    if find_profile(socket.assigns.printer_profiles, profile_id) do
      {:noreply,
       socket
       |> assign(:active_printer_profile_id, profile_id)
       |> persist_active_printer_profile()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("printer_profiles_loaded", %{"profiles" => profiles}, socket)
      when is_list(profiles) do
    printer_profiles =
      profiles
      |> Enum.map(&PrinterProfile.from_map/1)
      |> Enum.reject(&is_nil/1)
      |> merge_printer_profiles(persisted_printer_profiles())

    {:noreply, assign(socket, :printer_profiles, printer_profiles)}
  end

  def handle_event("printer_profiles_loaded", _params, socket), do: {:noreply, socket}

  def handle_event("active_printer_profile_loaded", %{"profile_id" => profile_id}, socket)
      when is_binary(profile_id) and profile_id != "" do
    active_printer_profile_id =
      if find_profile(socket.assigns.printer_profiles, profile_id), do: profile_id, else: nil

    {:noreply, assign(socket, :active_printer_profile_id, active_printer_profile_id)}
  end

  def handle_event("active_printer_profile_loaded", _params, socket), do: {:noreply, socket}

  defp save_browser_local_profile(socket, params, profile_id, action) do
    attrs = if profile_id, do: Map.put(params, "id", profile_id), else: params

    case PrinterProfile.validate(attrs) do
      {:ok, printer_profile} ->
        printer_profiles =
          upsert_printer_profile(socket.assigns.printer_profiles, printer_profile)

        {:noreply,
         socket
         |> assign(:printer_profiles, printer_profiles)
         |> assign(:active_printer_profile_id, printer_profile.id)
         |> assign(:editing_profile_id, printer_profile.id)
         |> assign(:printer_profile_form, form_for(printer_profile))
         |> persist_printer_profiles()
         |> persist_active_printer_profile()
         |> put_flash(
           :info,
           "#{action} printer profile #{PrinterProfile.display_name(printer_profile)}"
         )}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:printer_profile_form, normalize_printer_profile_form(params))
         |> put_flash(:error, message)}
    end
  end

  defp update_persisted_profile(socket, profile, params) do
    persisted_profile_id = PrinterProfile.persisted_record_id(profile)
    persisted_profile = Persistence.get_printer_profile!(persisted_profile_id)

    case Persistence.update_printer_profile(persisted_profile, params) do
      {:ok, updated_profile} ->
        printer_profile = PrinterProfile.from_persistence(updated_profile)

        printer_profiles =
          upsert_printer_profile(socket.assigns.printer_profiles, printer_profile)

        {:noreply,
         socket
         |> assign(:printer_profiles, printer_profiles)
         |> assign(:active_printer_profile_id, printer_profile.id)
         |> assign(:editing_profile_id, printer_profile.id)
         |> assign(:printer_profile_form, form_for(printer_profile))
         |> persist_active_printer_profile()
         |> put_flash(
           :info,
           "Updated printer profile #{PrinterProfile.display_name(printer_profile)}"
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:printer_profile_form, normalize_printer_profile_form(params))
         |> put_flash(:error, changeset_error(changeset))}
    end
  end

  defp changeset_error(changeset) do
    {_field, {message, _opts}} = List.first(changeset.errors)
    String.capitalize(message)
  end

  defp persist_printer_profiles(socket) do
    push_event(socket, "save_printer_profiles", %{
      profiles:
        socket.assigns.printer_profiles
        |> Enum.filter(&PrinterProfile.browser_local_profile?/1)
        |> Enum.map(&Map.from_struct/1)
    })
  end

  defp persist_active_printer_profile(socket) do
    push_event(socket, "set_active_printer_profile", %{
      profile_id: socket.assigns.active_printer_profile_id
    })
  end

  defp persisted_printer_profiles do
    persisted_profiles =
      Persistence.list_printer_profiles()
      |> Enum.map(&PrinterProfile.from_persistence/1)

    merge_printer_profiles([], persisted_profiles)
  end

  defp merge_printer_profiles(local_profiles, persisted_profiles) do
    [local_profiles, persisted_profiles]
    |> PrinterProfile.merge_profiles()
    |> PrinterProfile.merge_with_defaults()
  end

  defp upsert_printer_profile(printer_profiles, printer_profile) do
    if Enum.any?(printer_profiles, &(&1.id == printer_profile.id)) do
      Enum.map(printer_profiles, fn
        %{id: id} when id == printer_profile.id -> printer_profile
        profile -> profile
      end)
    else
      [printer_profile | printer_profiles]
    end
  end

  defp find_profile(printer_profiles, profile_id) do
    Enum.find(printer_profiles, &(&1.id == profile_id))
  end

  defp editing_profile(socket) do
    find_profile(socket.assigns.printer_profiles, socket.assigns.editing_profile_id)
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

  defp normalize_printer_profile_form(params) when is_map(params) do
    Enum.reduce(empty_printer_profile_form(), %{}, fn {key, _default}, acc ->
      Map.put(acc, key, Map.get(params, Atom.to_string(key), Map.get(params, key, "")))
    end)
  end

  defp form_for(%PrinterProfile{} = profile) do
    profile
    |> Map.from_struct()
    |> Map.take(Map.keys(empty_printer_profile_form()))
    |> normalize_printer_profile_form()
  end

  defp active_profile?(assigns, profile) do
    assigns.active_printer_profile_id == profile.id
  end

  defp submit_label(assigns) do
    case find_profile(assigns.printer_profiles, assigns.editing_profile_id) do
      %PrinterProfile{} = profile ->
        if PrinterProfile.persisted_profile?(profile) do
          "Save Persisted Profile"
        else
          "Save Browser-local Profile"
        end

      nil ->
        "Create Browser-local Profile"
    end
  end

  defp form_heading(assigns) do
    case find_profile(assigns.printer_profiles, assigns.editing_profile_id) do
      %PrinterProfile{} = profile ->
        if PrinterProfile.persisted_profile?(profile) do
          "Edit Persisted Profile"
        else
          "Edit Browser-local Profile"
        end

      nil ->
        "Create Browser-local Profile"
    end
  end

  def render(assigns) do
    ~H"""
    <div
      class="mx-auto max-w-6xl p-6"
      phx-hook="PaletteStorage"
      id="printer-profile-storage"
      data-load-palettes="false"
      data-load-printer-profiles="true"
    >
      <div class="mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Printer Profiles</h1>
          <p class="mt-2 max-w-3xl text-sm text-gray-600">
            Manage browser-local and persisted printer profiles here, then return to the grid to
            keep the active selector compact.
          </p>
        </div>
        <.link
          navigate={~p"/"}
          class="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-white"
        >
          Back to Grid
        </.link>
      </div>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
        <section class="rounded-lg border border-gray-200 bg-white p-4">
          <div class="mb-4 flex items-center justify-between">
            <div>
              <h2 class="text-xl font-semibold text-gray-900">Available Profiles</h2>
              <p class="mt-1 text-sm text-gray-600">
                Default profiles are read-only. Browser-local profiles stay in this browser.
              </p>
            </div>
            <button
              type="button"
              phx-click="new_printer_profile"
              class="rounded-lg bg-emerald-700 px-3 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
            >
              New Browser-local Profile
            </button>
          </div>

          <div class="space-y-3">
            <%= for profile <- @printer_profiles do %>
              <article class="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div>
                    <div class="flex flex-wrap items-center gap-2">
                      <h3 class="text-base font-semibold text-gray-900">
                        {PrinterProfile.display_name(profile)}
                      </h3>
                      <span class="rounded-full bg-white px-2 py-1 text-xs font-medium text-gray-600">
                        {PrinterProfile.source_label(profile)}
                      </span>
                      <%= if active_profile?(assigns, profile) do %>
                        <span class="rounded-full bg-emerald-100 px-2 py-1 text-xs font-medium text-emerald-700">
                          Active
                        </span>
                      <% end %>
                    </div>
                    <p class="mt-2 text-sm text-gray-600">
                      Ink: {profile.ink_type}. ICC: {profile.icc_profile || "Not specified"}.
                      Driver: {profile.driver_name || "Not specified"}.
                    </p>
                    <p class="mt-1 text-sm text-gray-600">
                      Calibration: {profile.calibration_version || "Not specified"}.
                      Notes: {profile.notes || "None"}.
                    </p>
                  </div>

                  <div class="flex gap-2">
                    <button
                      type="button"
                      phx-click="select_active_printer_profile"
                      phx-value-profile_id={profile.id}
                      class="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-white"
                    >
                      Set Active
                    </button>
                    <%= unless PrinterProfile.default_profile?(profile) do %>
                      <button
                        type="button"
                        phx-click="edit_printer_profile"
                        phx-value-profile_id={profile.id}
                        class="rounded-lg border border-emerald-700 px-3 py-2 text-sm font-medium text-emerald-800 hover:bg-white"
                      >
                        Edit
                      </button>
                    <% end %>
                  </div>
                </div>
              </article>
            <% end %>
          </div>
        </section>

        <section class="rounded-lg border border-emerald-200 bg-emerald-50 p-4">
          <h2 class="text-xl font-semibold text-gray-900">{form_heading(assigns)}</h2>
          <p class="mt-1 text-sm text-gray-600">
            Use this form to create browser-local profiles or update an existing persisted or
            browser-local profile.
          </p>

          <form id="printer-profile-form" phx-submit="save_printer_profile" class="mt-4">
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
              class="mt-4 rounded-lg bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
            >
              {submit_label(assigns)}
            </button>
          </form>
        </section>
      </div>
    </div>
    """
  end
end

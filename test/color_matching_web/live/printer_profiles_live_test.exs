defmodule ColorMatchingWeb.PrinterProfilesLiveTest do
  use ColorMatchingWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ColorMatching.Persistence

  describe "PrinterProfilesLive" do
    test "renders the dedicated management page and keeps defaults read-only", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/printer-profiles")

      assert html =~ "Printer Profiles"
      assert html =~ "Back to Grid"
      assert html =~ ~s(data-load-palettes="false")
      assert html =~ ~s(data-load-printer-profiles="true")
      assert html =~ "Epson SureColor P900 on Ultra Premium Luster"
      assert html =~ "Default"
      refute html =~ "Edit Persisted Profile"
    end

    test "creates a browser-local profile and persists it for future visits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/printer-profiles")

      view
      |> form("#printer-profile-form", %{
        "profile" => %{
          "printer_make_model" => "HP DesignJet Z9+",
          "paper_type" => "Photo Rag",
          "ink_type" => "OEM pigment",
          "icc_profile" => "Z9 Photo Rag",
          "print_settings" => "Best",
          "driver_name" => "HP Driver",
          "driver_version" => "61.3",
          "calibration_date" => "2026-07-10",
          "calibration_version" => "rag-1",
          "notes" => "Studio profile"
        }
      })
      |> render_submit()

      assert_push_event(view, "save_printer_profiles", %{profiles: profiles})
      assert_push_event(view, "set_active_printer_profile", %{profile_id: active_profile_id})

      html = render(view)
      assert html =~ "HP DesignJet Z9+ on Photo Rag"
      assert html =~ "Browser local"
      assert html =~ "Active"

      custom_profile =
        Enum.find(profiles, fn profile ->
          (Map.get(profile, "printer_make_model") || Map.get(profile, :printer_make_model)) ==
            "HP DesignJet Z9+"
        end)

      assert active_profile_id == (Map.get(custom_profile, "id") || Map.get(custom_profile, :id))
    end

    test "edits a browser-local profile loaded from storage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/printer-profiles")

      browser_local_profile = %{
        "id" => "profile-studio-rag",
        "printer_make_model" => "HP DesignJet Z9+",
        "paper_type" => "Photo Rag",
        "ink_type" => "OEM pigment",
        "icc_profile" => "Z9 Photo Rag",
        "print_settings" => "Best",
        "driver_name" => "HP Driver",
        "driver_version" => "61.3",
        "calibration_date" => "2026-07-10",
        "calibration_version" => "rag-1",
        "notes" => "Studio profile"
      }

      render_hook(view, "printer_profiles_loaded", %{"profiles" => [browser_local_profile]})

      view
      |> element(
        "button[phx-click='edit_printer_profile'][phx-value-profile_id='profile-studio-rag']"
      )
      |> render_click()

      view
      |> form("#printer-profile-form", %{
        "profile" => %{
          "printer_make_model" => "HP DesignJet Z9+",
          "paper_type" => "Photo Rag Bright White",
          "ink_type" => "OEM pigment",
          "icc_profile" => "Z9 Photo Rag",
          "print_settings" => "Best",
          "driver_name" => "HP Driver",
          "driver_version" => "61.3",
          "calibration_date" => "2026-07-10",
          "calibration_version" => "rag-2",
          "notes" => "Updated studio profile"
        }
      })
      |> render_submit()

      assert_push_event(view, "save_printer_profiles", %{profiles: profiles})

      html = render(view)
      assert html =~ "HP DesignJet Z9+ on Photo Rag Bright White"
      assert html =~ "rag-2"
      assert html =~ "Updated studio profile"

      updated_profile =
        Enum.find(profiles, fn profile ->
          (Map.get(profile, "id") || Map.get(profile, :id)) == "profile-studio-rag"
        end)

      assert (Map.get(updated_profile, "paper_type") || Map.get(updated_profile, :paper_type)) ==
               "Photo Rag Bright White"
    end

    test "edits a persisted profile on the dedicated page", %{conn: conn} do
      assert {:ok, persisted_profile} =
               Persistence.create_printer_profile(%{
                 printer_make_model: "Canon PRO-310",
                 paper_type: "Fine Art Smooth",
                 ink_type: "OEM Lucia Pro II",
                 icc_profile: "PRO-310 Smooth",
                 calibration_version: "smooth-1",
                 notes: "Baseline profile"
               })

      {:ok, view, _html} = live(conn, ~p"/printer-profiles")

      view
      |> element(
        "button[phx-click='edit_printer_profile'][phx-value-profile_id='persisted-#{persisted_profile.id}']"
      )
      |> render_click()

      view
      |> form("#printer-profile-form", %{
        "profile" => %{
          "printer_make_model" => "Canon PRO-310",
          "paper_type" => "Fine Art Smooth",
          "ink_type" => "OEM Lucia Pro II",
          "icc_profile" => "PRO-310 Smooth v2",
          "print_settings" => "Highest",
          "driver_name" => "Canon IJ",
          "driver_version" => "17.1",
          "calibration_date" => "2026-07-14",
          "calibration_version" => "smooth-2",
          "notes" => "Updated baseline profile"
        }
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Edit Persisted Profile"
      assert html =~ "PRO-310 Smooth v2"
      assert html =~ "Updated baseline profile"

      updated_profile = Persistence.get_printer_profile!(persisted_profile.id)
      assert updated_profile.icc_profile == "PRO-310 Smooth v2"
      assert updated_profile.calibration_version == "smooth-2"
      assert updated_profile.notes == "Updated baseline profile"
    end
  end
end

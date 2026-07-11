defmodule ColorMatchingWeb.CoreComponentsTest do
  use ColorMatchingWeb.ConnCase, async: true

  import ColorMatchingWeb.CoreComponents
  import Phoenix.Component
  import Phoenix.LiveViewTest

  test "icon renders an embedded SVG with escaped classes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.icon name="hero-x-mark-solid" class={"h-5 w-5 \"quoted\""} />
      """)

    assert html =~ "<svg "
    assert html =~ ~s(class="inline-block align-middle h-5 w-5 &quot;quoted&quot;")
    assert html =~ ~s(viewBox="0 0 24 24")
    refute html =~ "<span"
  end
end

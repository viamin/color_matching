---
title: LiveView input phx-change handlers must accept form field payloads
date: 2026-07-25
category: ui-bugs
module: ColorMatchingWeb.PalettesLive
problem_type: ui_bug
component: tooling
symptoms:
  - "Typing in the palette name field crashed the PalettesLive process"
  - "The Create button became disabled again after hydration"
  - "Server logs showed FunctionClauseError for update_new_palette_name"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [liveview, phx-change, palettes, form-payloads]
---

# LiveView input phx-change handlers must accept form field payloads

## Problem

The palette management page appeared to hydrate correctly during the incident, but typing into the create-palette name field repeatedly crashed and remounted the LiveView. Each remount reset `active_palette_hydrated` to false, so the `Create` button became disabled again even though it had initially enabled.

## Symptoms

- Browser interactions looked like repeated page loads while typing a palette name.
- The incident server console logged `FunctionClauseError` for `ColorMatchingWeb.PalettesLive.handle_event/3`.
- The failing event was `update_new_palette_name`, with params shaped like `%{"name" => value}` rather than `%{"value" => value}`.
- The create button is gated by `disabled={!@active_palette_hydrated}` in [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L374), so every crash/remount re-disabled it.

## What Didn't Work

- A separate hydration issue was addressed by ensuring the palette-storage hook has a page-specific id, but that did not address crashes after the page was hydrated. The incident server logs showed the LiveView process was dying during `phx-change`, not failing to mount the `PaletteStorage` hook.
- Previous tests in the incident branch passed `%{"value" => value}` to input-level `phx-change` handlers. That did not reproduce the browser-shaped payload, so the incorrect handler shape survived.

## Solution

Make each input-level change handler accept the real browser form payload and keep the old `"value"` fallback for test helpers or non-browser callers:

```elixir
def handle_event("update_new_palette_name", params, socket) do
  {:noreply, assign(socket, :new_palette_name, input_value(params, "name"))}
end

def handle_event("update_editor_name_input", params, socket) do
  {:noreply, assign(socket, :editing_name, input_value(params, "name"))}
end

def handle_event("update_new_color_value", params, socket) do
  {:noreply, assign(socket, :new_color_value, input_value(params, "color"))}
end

defp input_value(params, field) do
  Map.get(params, field) || Map.get(params, "value") || ""
end
```

The current handlers live in [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L60), [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L186), and [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L255). The shared extractor lives in [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L846).

Update regression tests to use the browser-shaped payloads:

```elixir
view
|> element("input[name='name'][phx-change='update_new_palette_name']")
|> render_change(%{"name" => "Draft Name"})
```

The regression coverage now checks create-name, editor-color, and rename-name input changes in [palettes_live_test.exs](../../../test/color_matching_web/live/palettes_live_test.exs#L222), [palettes_live_test.exs](../../../test/color_matching_web/live/palettes_live_test.exs#L235), and [palettes_live_test.exs](../../../test/color_matching_web/live/palettes_live_test.exs#L256).

## Why This Works

The create form defines an input named `"name"` with `phx-change="update_new_palette_name"` in [PalettesLive](../../../lib/color_matching_web/live/palettes_live.ex#L365). The regression test models the browser payload for that input as `%{"name" => value}`. Matching only `%{"value" => value}` is the wrong API contract for this event shape.

Accepting params and extracting either the named field or `"value"` prevents a `FunctionClauseError`, keeps the LiveView process alive, and preserves the hydrated state that controls the create button.

## Prevention

- When an input has a `name`, write LiveView change handlers to accept that named field in params.
- Keep tests aligned with browser payloads: `render_change(%{"name" => "..."})` for `name="name"` and `render_change(%{"color" => "..."})` for `name="color"`.
- Add fallback extraction only as compatibility glue; do not make `%{"value" => value}` the only accepted payload unless the event source is proven to send that shape.
- When a LiveView interaction looks like a page reload, inspect the server console for process crashes before continuing to debug hydration or navigation.

## Related Issues

- This is currently the only `docs/solutions/` entry in the repo.

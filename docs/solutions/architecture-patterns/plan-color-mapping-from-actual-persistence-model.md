---
title: Plan color mapping from the actual persistence model
date: 2026-07-26
category: architecture-patterns
module: ColorMatching palette persistence and color mapping planning
problem_type: architecture_pattern
component: database
severity: medium
applies_when:
  - Planning illuminant response measurements or multi-image color mapping
  - Sequencing work that depends on persisted palettes, colors, printer profiles, measurements, response vectors, mapper services, API export, or later UI
  - Checking whether a feature idea assumes database-backed color state
tags: [persistence, ecto, sqlite, localstorage, printer-profiles, measurements, color-mapping]
related_components: [phoenix-liveview, palette-storage, browser-localstorage, github-issues]
---

# Plan color mapping from the actual persistence model

## Context

The illuminant response and multi-image color mapping feature idea implicitly assumed the app already had persisted colors, persisted measurements, printer profiles, and API surfaces to build on. Before filing issues, the useful move was to inspect the current codebase and separate desired product behavior from missing platform foundation.

The current app does not have that foundation yet. `ColorMatching.Palette` is the canonical palette shape shared by the grid page, palette management page, server-side presets, and client-side `localStorage` user palettes (`lib/color_matching/palette.ex:1`, `lib/color_matching/palette.ex:3`, `lib/color_matching/palette.ex:5`, `lib/color_matching/palette.ex:7`). `ColorMatching.PaletteStorage` explicitly documents that the app has no database and stores palette data in browser `localStorage` keys managed by the JavaScript hook (`lib/color_matching/palette_storage.ex:7`, `lib/color_matching/palette_storage.ex:8`, `lib/color_matching/palette_storage.ex:11`, `lib/color_matching/palette_storage.ex:14`).

The dependency list confirms this is still a no-database Phoenix app: it includes Phoenix, LiveView, asset tooling, Jason, Bandit, and quality tools, but no Ecto or SQLite dependency (`mix.exs:50`, `mix.exs:52`, `mix.exs:55`, `mix.exs:59`, `mix.exs:60`, `mix.exs:73`, `mix.exs:75`, `mix.exs:82`). The browser hook loads and saves saved palettes and the active palette through `localStorage` (`assets/js/app.js:28`, `assets/js/app.js:55`, `assets/js/app.js:57`, `assets/js/app.js:59`, `assets/js/app.js:70`, `assets/js/app.js:72`, `assets/js/app.js:74`, `assets/js/app.js:81`, `assets/js/app.js:83`, `assets/js/app.js:89`, `assets/js/app.js:104`). The router has a JSON pipeline but only a commented API scope scaffold, so endpoint work must enable actual API routes before API features can land (`lib/color_matching_web/router.ex:13`, `lib/color_matching_web/router.ex:26`, `lib/color_matching_web/router.ex:27`, `lib/color_matching_web/router.ex:28`).

Session history showed the same boundary from earlier work: prior palette fixes stayed inside LiveView/browser-storage mechanics, and a separate planning issue had already identified printer profiles as the context needed to keep measurements comparable (session history). That reinforces the ordering: server persistence and printer-profile identity are prerequisites, not downstream implementation details.

The solved work was planning and issue creation, not implementing the feature. Issues #39 through #45 were created to reflect the architectural dependency chain instead of treating UI or mapping behavior as immediately buildable.

## Guidance

When turning a large feature idea into GitHub issues, verify the current repo architecture before decomposing the work. Identify which parts of the idea are product behavior and which parts require missing foundations.

For this app, the durable sequence starts with persistence and domain records, then builds the measurement and mapping layers on top:

1. Add SQLite/Ecto persistence for palettes, colors, and printer profiles (#39).
2. Store illuminant brightness measurements per color and printer profile (#40).
3. Add API endpoints for entering and bulk importing illuminant measurements (#41).
4. Add color response vectors and weighted illuminant scoring (#42).
5. Add multi-image grayscale-to-palette mapping service (#43).
6. Expose multi-image color mapping through an API with PNG export (#44).
7. Add UI for color illuminant response profiles and measurement entry (#45).

Use dependency wording that names the missing substrate directly:

```text
Depends on #39 because measurements need persisted colors and printer profiles,
not transient localStorage palettes.

Depends on #40 because response vectors require stored brightness samples across
illuminants before scoring can be computed.

Depends on #43 because the export API should expose a tested mapping service
rather than embedding mapping logic in the controller.
```

Avoid opening the UI issue first unless it is explicitly framed as a prototype over mocked data. In this repo, production UI for illuminant profiles should come after persistence, measurement storage, scoring, and mapping APIs exist.

## Why This Matters

Large feature ideas often contain hidden architecture assumptions. If those assumptions are not checked against source, issue decomposition can produce tickets that look reasonable but are impossible to implement cleanly in order.

Here, jumping straight to illuminant profiles, measurement entry, or multi-image export would have skipped the fact that palette state is currently a struct plus browser storage rather than server data. That would force later issues to either invent storage ad hoc, duplicate data models, or build UI around state that cannot support bulk entry, printer-specific measurements, API import, scoring history, or reproducible mapping exports.

Grounding the plan in the current architecture produced a cleaner dependency graph: database and printer profiles first, measurements second, scoring third, mapping fourth, API/export fifth, UI last.

## When to Apply

- A feature introduces persisted user data where the app may currently use client-side state.
- A feature depends on measurements, analytics, scoring, imports, exports, or auditability.
- A feature needs APIs in an app that may only have browser routes.
- A feature introduces domain entities that need stable IDs or relationships.
- UI work depends on backend workflows not yet represented in code.

For this codebase specifically, apply this before planning work that assumes palettes, colors, printer profiles, illuminant samples, mapping jobs, or generated outputs are persisted server-side.

## Examples

Poor decomposition:

1. Build illuminant response UI.
2. Add multi-image mapper.
3. Add API later.
4. Figure out storage while implementing.

This order hides the architectural blocker. The app currently normalizes palettes into `ColorMatching.Palette` and stores user palette state through the browser hook, so measurement and mapping features need persistence before they need UI.

Better decomposition:

1. `#39 Add SQLite/Ecto persistence for palettes, colors, and printer profiles`
   Dependency wording: `Creates the server-side records that later illuminant measurements and mapping jobs can reference.`
2. `#40 Store illuminant brightness measurements per color and printer profile`
   Dependency wording: `Depends on #39 because each measurement needs persisted color and printer-profile foreign keys.`
3. `#41 Add API endpoints for entering and bulk importing illuminant measurements`
   Dependency wording: `Depends on #40 because the API should validate and write the measurement schema, and router API scope work must be enabled from the current commented scaffold.`
4. `#42 Add color response vectors and weighted illuminant scoring`
   Dependency wording: `Depends on #40 because vectors are derived from stored per-illuminant brightness measurements.`
5. `#43 Add multi-image grayscale-to-palette mapping service`
   Dependency wording: `Depends on #42 because mapping needs response vectors and scoring to choose palette colors across image layers.`
6. `#44 Expose multi-image color mapping through an API with PNG export`
   Dependency wording: `Depends on #43 because the API should wrap the mapper service and export generated PNGs rather than own mapping logic.`
7. `#45 Add UI for color illuminant response profiles and measurement entry`
   Dependency wording: `Depends on #39 through #42 for real persisted profiles, measurements, and scores; UI can then manage actual domain data instead of mocked local state.`

## Related

- [#39 Add SQLite/Ecto persistence for palettes, colors, and printer profiles](https://github.com/viamin/color_matching/issues/39)
- [#40 Store illuminant brightness measurements per color and printer profile](https://github.com/viamin/color_matching/issues/40)
- [#41 Add API endpoints for entering and bulk importing illuminant measurements](https://github.com/viamin/color_matching/issues/41)
- [#42 Add color response vectors and weighted illuminant scoring](https://github.com/viamin/color_matching/issues/42)
- [#43 Add multi-image grayscale-to-palette mapping service](https://github.com/viamin/color_matching/issues/43)
- [#44 Expose multi-image color mapping through an API with PNG export](https://github.com/viamin/color_matching/issues/44)
- [#45 Add UI for color illuminant response profiles and measurement entry](https://github.com/viamin/color_matching/issues/45)
- [#36 Treat printer profiles as first-class objects](https://github.com/viamin/color_matching/issues/36)
- [#4 Add shared palette state and storage foundation](https://github.com/viamin/color_matching/issues/4)

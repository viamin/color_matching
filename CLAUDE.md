# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- **Setup**: `mix setup` - Install dependencies and setup assets
- **Setup git hooks**: `bin/setup-git-hooks` - Install pre-commit formatting hooks
- **Start server**: `mix phx.server` or `iex -S mix phx.server` (with interactive shell)
- **Compile**: `mix compile`
- **Run tests**: `mix test`
- **Run single test file**: `mix test test/path/to/test_file.exs`
- **Asset commands**:
  - `mix assets.build` - Build CSS/JS assets
  - `mix assets.deploy` - Build and minify assets for production

## Code Quality Tools

- **Format code**: `mix format` - Auto-format Elixir code
- **Static analysis**: `mix credo` - Code quality and style analysis
- **Type checking**: `mix dialyzer` - Static type analysis
- **Security scan**: `mix sobelow --config` - Security vulnerability scanning
- **Test coverage**: `mix coveralls` - Generate test coverage report
- **Test coverage HTML**: `mix coveralls.html` - Generate HTML coverage report

## Application Architecture

This is a Phoenix LiveView application for color matching visualization without a database (--no-ecto).

### Core Modules

**ColorMatching.Grid** (`lib/color_matching/grid.ex`)
- Central data structure that generates the triangular color grid
- Creates grids where top-left triangles use selected colors, bottom-right triangles use mathematically inverted colors
- Each row shares the same top-left color, each column shares the same bottom-right color
- Key function: `Grid.new(colors, size)` returns a struct with the generated grid

**ColorMatching.ColorUtils** (`lib/color_matching/color_utils.ex`)
- Utility functions for color manipulation
- `invert_color/1`: Mathematically inverts hex colors by inverting RGB components (#FF0000 → #00FFFF)
- `random_color/1`: Generates random hex colors for automatic grid expansion

**ColorMatchingWeb.ColorGridLive** (`lib/color_matching_web/live/color_grid_live.ex`)
- Main LiveView handling the interactive interface
- Manages color selection, grid size changes, and real-time updates
- Automatically adds random colors when grid size expands beyond available colors
- Key state: `:colors` list, `:grid_size` integer, `:grid` struct from ColorMatching.Grid

### Routing
- Root route (`/`) serves the ColorGridLive interface
- `/home` serves standard Phoenix controller for fallback
- `/dev/dashboard` provides LiveDashboard in development

### Styling
- Uses Tailwind CSS with custom triangle CSS classes in `assets/css/app.css`
- `.triangle-top-left` and `.triangle-bottom-right` use CSS clip-path for split triangular squares
- No custom JavaScript beyond Phoenix LiveView

### Key Features
- **Dynamic grid generation**: Grid automatically redraws when colors or size change
- **Inverse color system**: Bottom-right triangles show mathematical color inversions, doubling unique combinations
- **Smart expansion**: When grid size increases, random colors are automatically added if needed
- **Real-time preview**: Color management shows both original and inverse colors side-by-side

## Test Structure
Standard Phoenix test structure with ExUnit. Tests are minimal as this was a demonstration project.

## Development Notes
- No database configuration (created with --no-ecto flag)
- Uses Bandit as the HTTP server
- All color logic is client-side with LiveView handling state management
- CSS triangles are achieved with clip-path rather than complex SVG or canvas solutions
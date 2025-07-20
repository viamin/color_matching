# Color Matching Grid

An interactive Elixir Phoenix LiveView application for exploring color combinations through a dynamic triangular grid system. Perfect for color theory experiments, metamerism studies, and finding color pairings that behave differently under various lighting conditions.

## What it does

The Color Matching Grid creates a visual matrix where each square is split diagonally into two triangles, with the grid divided by the main diagonal to eliminate duplicate combinations:

### Below the Main Diagonal (\)
- **Top-left triangles**: Colors from your palette (by row)
- **Bottom-right triangles**: Colors from your palette (by column)
- Shows all unique **original color combinations**

### Above the Main Diagonal (\)  
- **Top-left triangles**: Colors from your palette (by row)
- **Bottom-right triangles**: **Inverted** colors from your palette (by column)
- Shows **high-contrast combinations** for maximum visual difference

### On the Main Diagonal
- **Top-left triangles**: Original palette colors
- **Bottom-right triangles**: Split diagonally - original color below, inverted color above

This design eliminates duplicate combinations while providing both subtle (original) and high-contrast (inverted) color pairings in a systematic layout.

### Key Features

- **Interactive color management**: Add colors via color picker or hex input, remove unwanted colors
- **Dynamic grid sizing**: Adjust from 6×6 to 12×12 grids with a slider
- **Smart expansion**: When you increase grid size, random colors are automatically added as needed
- **Palette presets**: Includes specialized palettes like "Sodium Metamers" for low-pressure sodium lamp experiments
- **All combinations**: See every possible pairing within your color selection
- **Print-friendly**: Optimized layouts for physical reference prints

### Special Use Cases

- **Sodium Lamp Experiments**: Use the "Sodium Metamers A/B" presets to find colors that look different in normal light but appear similar under 589nm monochromatic sodium lighting
- **Color Theory Studies**: Explore how different color combinations interact visually
- **Design Work**: Find harmonious or contrasting color pairings within a specific palette

## Getting Started

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix

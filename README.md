# Color Matching Grid

An interactive Elixir Phoenix LiveView application for exploring color combinations through a dynamic triangular grid system.

## What it does

The Color Matching Grid creates a visual matrix where each square is split diagonally into two triangles:

- **Top-left triangles** display your selected colors
- **Bottom-right triangles** display the mathematical inverse of those colors
- Each row shares the same top-left color, each column shares the same bottom-right color
- This creates a grid showing how every color pairs with the inverse of every other color

### Key Features

- **Interactive color management**: Add colors via color picker or hex input, remove unwanted colors
- **Dynamic grid sizing**: Adjust from 3×3 to 10×10 grids with a slider
- **Smart expansion**: When you increase grid size, random colors are automatically added as needed
- **Real-time preview**: See both original and inverse colors side-by-side before they appear in the grid
- **Maximum contrast combinations**: By using color inversions, you get high-contrast pairings and double the unique combinations

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

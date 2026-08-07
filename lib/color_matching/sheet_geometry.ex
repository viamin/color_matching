defmodule ColorMatching.SheetGeometry do
  @moduledoc """
  Computes printable-sheet geometry for the iOS manifest contract.

  Sheets are diagonal comparison grids (see `ColorMatching.Grid`): each cell
  pairs two colors split along the cell diagonal — the top-left triangle is the
  first color and the bottom-right triangle is the second. This module derives
  the axis-aligned rectangles the manifest contract exposes to the iOS client:

    * a centered grid of square cells from `patch_layout`,
    * two sampling patches per cell (top-left and bottom-right quadrants),
    * four corner registration markers from `reg_marker_layout`.

  Coordinates are in the sheet's page units (millimetres), origin at the
  top-left corner of the page, +x to the right and +y downward — matching the
  manifest contract and the iOS coordinate convention.
  """

  alias ColorMatching.Persistence.TestSheet

  @default_patch_inset_mm 1.5
  @default_cell_size_mm 20.0
  @default_gap_mm 2.0
  @default_grid_size 3
  @default_marker_radius_mm 5.0

  @type rect :: %{x: float(), y: float(), width: float(), height: float()}
  @type marker :: %{role: String.t(), rect: rect()}
  @type t :: %__MODULE__{
          units: String.t(),
          page_width: float(),
          page_height: float(),
          cell_size: float(),
          gap: float(),
          grid_size: non_neg_integer(),
          origin_x: float(),
          origin_y: float(),
          marker_radius: float(),
          marker_margin: float(),
          patch_inset: float(),
          markers: [marker()]
        }

  defstruct [
    :units,
    :page_width,
    :page_height,
    :cell_size,
    :gap,
    :grid_size,
    :origin_x,
    :origin_y,
    :marker_radius,
    :marker_margin,
    :patch_inset,
    :markers
  ]

  @spec build(TestSheet.t()) :: t()
  def build(%TestSheet{} = sheet) do
    layout = decode(sheet.patch_layout) || %{}
    reg = decode(sheet.reg_marker_layout) || %{}

    cell_size = to_float(fetch(layout, "cell_size_mm", @default_cell_size_mm))
    gap = to_float(fetch(layout, "gap_mm", @default_gap_mm))
    grid_size = to_int(fetch(layout, "grid_size", @default_grid_size))

    page_width = to_float(sheet.page_width_mm || 0.0)
    page_height = to_float(sheet.page_height_mm || 0.0)
    units = sheet.page_units || "mm"

    marker_radius = to_float(fetch(reg, "radius_mm", @default_marker_radius_mm))
    # Registration markers sit just inside the printable area; reuse the sheet's
    # page safe-inset as the corner margin when present.
    marker_margin = to_float(sheet.safe_inset_mm || marker_radius)

    grid_extent = grid_size * cell_size + max(grid_size - 1, 0) * gap
    origin_x = (page_width - grid_extent) / 2
    origin_y = (page_height - grid_extent) / 2

    markers = corner_markers(page_width, page_height, marker_radius, marker_margin)

    %__MODULE__{
      units: units,
      page_width: page_width,
      page_height: page_height,
      cell_size: cell_size,
      gap: gap,
      grid_size: grid_size,
      origin_x: origin_x,
      origin_y: origin_y,
      marker_radius: marker_radius,
      marker_margin: marker_margin,
      patch_inset: @default_patch_inset_mm,
      markers: markers
    }
  end

  @spec cell_rect(t(), non_neg_integer(), non_neg_integer()) :: rect()
  def cell_rect(%__MODULE__{} = geometry, row, col) do
    x = geometry.origin_x + col * (geometry.cell_size + geometry.gap)
    y = geometry.origin_y + row * (geometry.cell_size + geometry.gap)
    %{x: x, y: y, width: geometry.cell_size, height: geometry.cell_size}
  end

  @doc """
  Returns the two sampling patch rects for a cell, in pair-side order:

    * first — top-left quadrant (first color),
    * second — bottom-right quadrant (second color).

  The iOS client applies `patch_inset` within each rect when sampling, so the
  quadrants are reported at full size and the inset is exposed separately.
  """
  @spec patch_rects(rect()) :: [rect()]
  def patch_rects(%{x: x, y: y, width: width}) do
    half = width / 2

    [
      %{x: x, y: y, width: half, height: half},
      %{x: x + half, y: y + half, width: half, height: half}
    ]
  end

  defp corner_markers(page_width, page_height, radius, margin) do
    side = radius * 2

    [
      %{role: "top_left", rect: %{x: margin, y: margin, width: side, height: side}},
      %{
        role: "top_right",
        rect: %{x: page_width - margin - side, y: margin, width: side, height: side}
      },
      %{
        role: "bottom_right",
        rect: %{
          x: page_width - margin - side,
          y: page_height - margin - side,
          width: side,
          height: side
        }
      },
      %{
        role: "bottom_left",
        rect: %{x: margin, y: page_height - margin - side, width: side, height: side}
      }
    ]
  end

  defp fetch(map, key, default) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> fetch_atom_key(map, key, default)
    end
  end

  defp fetch_atom_key(map, key, default) do
    Map.get(map, String.to_existing_atom(key), default)
  rescue
    ArgumentError -> default
  end

  defp decode(nil), do: nil

  defp decode(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> nil
    end
  end

  defp decode(map) when is_map(map), do: map

  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n * 1.0

  defp to_float(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: trunc(n)

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_int(_), do: 0
end

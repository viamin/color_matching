defmodule ColorMatching.PrintedPairBrowser do
  @moduledoc """
  Browser-oriented listing, filtering, and sorting for printed pair
  classifications.
  """

  import Ecto.Query

  alias ColorMatching.ColorSpace
  alias ColorMatching.Persistence.{
    Palette,
    PrintedPairClassification,
    PrinterProfile,
    TestSheet,
    TestSheetPair
  }

  alias ColorMatching.Repo

  @default_sort "recent"
  @sorts ~w[recent illuminant profile pair_id delta_e]
  @illuminant_labels %{
    "lps" => "LPS",
    "red" => "Red",
    "green" => "Green",
    "blue" => "Blue"
  }
  @classification_labels %{
    "strong_metamer" => "Strong metamer",
    "weak_metamer" => "Weak metamer",
    "contrasting" => "Contrasting"
  }

  @type filters :: %{
          optional(:illuminant) => String.t() | nil,
          optional(:classification) => String.t() | nil,
          optional(:profile_id) => integer() | nil,
          optional(:palette_id) => integer() | nil,
          optional(:test_sheet_id) => integer() | nil,
          optional(:sort) => String.t()
        }

  @type entry :: %{
          id: integer(),
          pair_id: String.t(),
          swatch_a: String.t(),
          swatch_b: String.t(),
          illuminant: String.t(),
          illuminant_label: String.t(),
          classification: String.t(),
          classification_label: String.t(),
          profile_id: integer(),
          profile_name: String.t(),
          palette_id: integer(),
          palette_name: String.t(),
          test_sheet_id: integer(),
          test_sheet_lookup_code: String.t(),
          row: integer(),
          col: integer(),
          notes: String.t() | nil,
          notes?: boolean(),
          updated_at: DateTime.t() | NaiveDateTime.t() | nil,
          delta_e: float() | nil,
          delta_e_label: String.t()
        }

  @spec any_active?() :: boolean()
  def any_active? do
    PrintedPairClassification
    |> where([classification], classification.active == true)
    |> select([classification], classification.id)
    |> limit(1)
    |> Repo.exists?()
  end

  @spec list_entries(keyword() | map()) :: [entry()]
  def list_entries(filters \\ %{}) do
    filters = normalize_filters(filters)

    filters
    |> base_query()
    |> order_by_query(filters.sort)
    |> preload([:reproduction_profile, test_sheet_pair: [test_sheet: :palette]])
    |> Repo.all()
    |> Enum.map(&to_entry/1)
    |> sort_entries(filters.sort)
  end

  @spec filter_options() :: map()
  def filter_options do
    %{
      illuminants:
        Enum.map(PrintedPairClassification.illuminants(), fn illuminant ->
          {illuminant_label(illuminant), illuminant}
        end),
      classifications:
        Enum.map(PrintedPairClassification.classifications(), fn classification ->
          {classification_label(classification), classification}
        end),
      profiles: profile_options(),
      palettes: palette_options(),
      test_sheets: test_sheet_options()
    }
  end

  @spec normalize_filters(keyword() | map()) :: filters()
  def normalize_filters(filters) when is_list(filters) do
    filters |> Enum.into(%{}) |> normalize_filters()
  end

  def normalize_filters(%{"filters" => nested}), do: normalize_filters(nested)

  def normalize_filters(filters) when is_map(filters) do
    %{
      illuminant:
        normalize_string(Map.get(filters, "illuminant") || Map.get(filters, :illuminant)),
      classification:
        normalize_string(Map.get(filters, "classification") || Map.get(filters, :classification)),
      profile_id:
        normalize_integer(Map.get(filters, "profile_id") || Map.get(filters, :profile_id)),
      palette_id:
        normalize_integer(Map.get(filters, "palette_id") || Map.get(filters, :palette_id)),
      test_sheet_id:
        normalize_integer(Map.get(filters, "test_sheet_id") || Map.get(filters, :test_sheet_id)),
      sort: normalize_sort(Map.get(filters, "sort") || Map.get(filters, :sort))
    }
  end

  @spec to_query_params(filters()) :: map()
  def to_query_params(filters) do
    filters
    |> normalize_filters()
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == @default_sort end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  @spec sort_options() :: [{String.t(), String.t()}]
  def sort_options do
    [
      {"Most recent", "recent"},
      {"Illuminant", "illuminant"},
      {"Profile", "profile"},
      {"Pair ID", "pair_id"},
      {"Closest pair (ΔE00)", "delta_e"}
    ]
  end

  @spec illuminant_label(String.t()) :: String.t()
  def illuminant_label(illuminant), do: Map.get(@illuminant_labels, illuminant, illuminant)

  @spec classification_label(String.t()) :: String.t()
  def classification_label(classification) do
    Map.get(@classification_labels, classification, classification)
  end

  # Filtering is pushed into SQL so the query only loads the rows the
  # browser actually needs. Filter context lives on joined tables
  # (test_sheet_pairs, test_sheets), so the same `base_query` covers every
  # filter the UI exposes without scanning the full classification history.
  defp base_query(filters) do
    base = from(c in PrintedPairClassification, where: c.active == true)

    base
    |> join(:inner, [classification], pair in TestSheetPair,
      on: pair.id == classification.test_sheet_pair_id
    )
    |> join(:inner, [_classification, pair], sheet in TestSheet,
      on: sheet.id == pair.test_sheet_id
    )
    |> maybe_filter(filters.illuminant, &illuminant_filter/2)
    |> maybe_filter(filters.classification, &classification_filter/2)
    |> maybe_filter(filters.profile_id, &profile_filter/2)
    |> maybe_filter(filters.palette_id, &palette_filter/2)
    |> maybe_filter(filters.test_sheet_id, &test_sheet_filter/2)
  end

  defp illuminant_filter(query, illuminant) do
    where(query, [classification, _pair, _sheet], classification.illuminant == ^illuminant)
  end

  defp classification_filter(query, classification) do
    where(query, [classification, _pair, _sheet],
      classification.classification == ^classification
    )
  end

  defp profile_filter(query, profile_id) do
    where(query, [classification, _pair, _sheet],
      classification.reproduction_profile_id == ^profile_id
    )
  end

  defp palette_filter(query, palette_id) do
    where(query, [_classification, _pair, sheet], sheet.palette_id == ^palette_id)
  end

  defp test_sheet_filter(query, test_sheet_id) do
    where(query, [_classification, _pair, sheet], sheet.id == ^test_sheet_id)
  end

  defp maybe_filter(query, nil, _fun), do: query
  defp maybe_filter(query, value, fun), do: fun.(query, value)

  # Secondary sort always falls back to recent activity and id so identical
  # primary keys keep a stable order across requests.
  defp order_by_query(query, "illuminant") do
    order_by(query, [classification, pair, _sheet],
      asc: classification.illuminant,
      asc: pair.pair_id,
      desc: classification.updated_at,
      desc: classification.id
    )
  end

  defp order_by_query(query, "pair_id") do
    order_by(query, [_classification, pair, _sheet],
      asc: pair.pair_id,
      desc: classification.updated_at,
      desc: classification.id
    )
  end

  # Profile sort needs the printer profile columns; join once and reuse the
  # binding for the ORDER BY.
  defp order_by_query(query, "profile") do
    joined =
      join(query, :inner, [classification, _pair, _sheet], profile in PrinterProfile,
        on: profile.id == classification.reproduction_profile_id
      )

    order_by(joined, [_classification, _pair, _sheet, profile],
      asc: profile.printer_make_model,
      asc: profile.paper_type,
      asc: classification.illuminant,
      desc: classification.updated_at,
      desc: classification.id
    )
  end

  # Delta E is computed per row from the pair's hex colors, so SQL can only
  # provide a stable secondary ordering. The primary sort happens in Elixir
  # once the result rows are materialized.
  defp order_by_query(query, "delta_e") do
    stable_secondary_order_by(query)
  end

  defp order_by_query(query, _sort) do
    order_by(query, [_classification, _pair, _sheet],
      desc: classification.updated_at,
      desc: classification.id
    )
  end

  # SQL cannot compute delta_e itself, so the query layer only orders rows
  # well enough that the post-query Elixir sort produces deterministic
  # results. `sort_entries/2` then applies the real metric ordering.
  defp stable_secondary_order_by(query) do
    order_by(query, [_classification, pair, _sheet],
      asc: pair.pair_id,
      desc: classification.updated_at,
      desc: classification.id
    )
  end

  defp to_entry(classification) do
    pair = classification.test_sheet_pair
    sheet = pair.test_sheet
    palette = sheet.palette
    profile = classification.reproduction_profile

    delta_e =
      case ColorSpace.ciede2000(pair.color_a_hex, pair.color_b_hex) do
        {:ok, value} -> value
        {:error, _reason} -> nil
      end

    %{
      id: classification.id,
      pair_id: pair.pair_id,
      swatch_a: pair.color_a_hex,
      swatch_b: pair.color_b_hex,
      illuminant: classification.illuminant,
      illuminant_label: illuminant_label(classification.illuminant),
      classification: classification.classification,
      classification_label: classification_label(classification.classification),
      profile_id: profile.id,
      profile_name: profile_name(profile.printer_make_model, profile.paper_type),
      palette_id: palette.id,
      palette_name: palette.name,
      test_sheet_id: sheet.id,
      test_sheet_lookup_code: sheet.lookup_code,
      row: pair.row,
      col: pair.col,
      notes: classification.notes,
      notes?: present_text?(classification.notes),
      updated_at: classification.updated_at,
      delta_e: delta_e,
      delta_e_label: format_delta_e(delta_e)
    }
  end

  # Delta E sort must run in Elixir because the metric depends on the pair's
  # two hex colors. Other sorts are already enforced by SQL, so this is a
  # no-op for everything except `:delta_e`.
  defp sort_entries(entries, "delta_e") do
    Enum.sort_by(entries, &{&1.delta_e || 9_999.0, &1.pair_id})
  end

  defp sort_entries(entries, _sort), do: entries

  defp profile_options do
    PrinterProfile
    |> join(:inner, [profile], classification in PrintedPairClassification,
      on:
        classification.reproduction_profile_id == profile.id and
          classification.active == true
    )
    |> select([profile], {profile.id, profile.printer_make_model, profile.paper_type})
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(fn {id, make_model, paper_type} ->
      {profile_name(make_model, paper_type), id}
    end)
    |> Enum.sort()
  end

  defp palette_options do
    Palette
    |> join(:inner, [palette], sheet in TestSheet,
      on: sheet.palette_id == palette.id
    )
    |> join(:inner, [_palette, sheet], pair in TestSheetPair,
      on: pair.test_sheet_id == sheet.id
    )
    |> join(:inner, [_palette, _sheet, pair], classification in PrintedPairClassification,
      on:
        classification.test_sheet_pair_id == pair.id and
          classification.active == true
    )
    |> select([palette], {palette.id, palette.name})
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  defp test_sheet_options do
    TestSheet
    |> join(:inner, [sheet], palette in Palette,
      on: palette.id == sheet.palette_id
    )
    |> join(:inner, [sheet, _palette], pair in TestSheetPair,
      on: pair.test_sheet_id == sheet.id
    )
    |> join(:inner, [_sheet, _palette, pair], classification in PrintedPairClassification,
      on:
        classification.test_sheet_pair_id == pair.id and
          classification.active == true
    )
    |> select([sheet, palette], {sheet.id, sheet.lookup_code, palette.name})
    |> distinct(true)
    |> Repo.all()
    |> Enum.map(fn {id, lookup_code, palette_name} ->
      {"#{lookup_code} · #{palette_name}", id}
    end)
    |> Enum.sort()
  end

  defp profile_name(nil, paper_type), do: paper_type || ""
  defp profile_name(make_model, nil), do: make_model || ""
  defp profile_name(make_model, paper_type), do: "#{make_model} on #{paper_type}"

  defp format_delta_e(nil), do: "N/A"
  defp format_delta_e(delta_e), do: :erlang.float_to_binary(delta_e, decimals: 3)

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: to_string(value)

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_sort(sort) when sort in @sorts, do: sort
  defp normalize_sort(_sort), do: @default_sort
end
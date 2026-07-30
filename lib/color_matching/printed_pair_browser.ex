defmodule ColorMatching.PrintedPairBrowser do
  @moduledoc """
  Browser-oriented listing, filtering, and sorting for printed pair
  classifications.
  """

  import Ecto.Query

  alias ColorMatching.ColorSpace
  alias ColorMatching.Persistence.{PrintedPairClassification, PrinterProfile}
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

  @spec list_entries(keyword() | map()) :: [entry()]
  def list_entries(filters \\ %{}) do
    filters = normalize_filters(filters)

    PrintedPairClassification
    |> where([classification], classification.active == true)
    |> Repo.all()
    |> Repo.preload([:reproduction_profile, test_sheet_pair: [test_sheet: :palette]])
    |> Enum.map(&to_entry/1)
    |> Enum.filter(&matches_filters?(&1, filters))
    |> sort_entries(filters.sort)
  end

  @spec filter_options() :: map()
  def filter_options do
    entries = list_entries()

    %{
      illuminants:
        Enum.map(PrintedPairClassification.illuminants(), fn illuminant ->
          {illuminant_label(illuminant), illuminant}
        end),
      classifications:
        Enum.map(PrintedPairClassification.classifications(), fn classification ->
          {classification_label(classification), classification}
        end),
      profiles:
        entries
        |> Enum.map(&{&1.profile_name, &1.profile_id})
        |> Enum.uniq()
        |> Enum.sort(),
      palettes:
        entries
        |> Enum.map(&{&1.palette_name, &1.palette_id})
        |> Enum.uniq()
        |> Enum.sort(),
      test_sheets:
        entries
        |> Enum.map(&{"#{&1.test_sheet_lookup_code} · #{&1.palette_name}", &1.test_sheet_id})
        |> Enum.uniq()
        |> Enum.sort()
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
        normalize_integer(
          Map.get(filters, "profile_id") || Map.get(filters, :profile_id) ||
            Map.get(filters, "reproduction_profile_id") ||
            Map.get(filters, :reproduction_profile_id)
        ),
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
      profile_name: profile_name(profile),
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

  defp matches_filters?(entry, filters) do
    matches_filter?(entry.illuminant, filters.illuminant) and
      matches_filter?(entry.classification, filters.classification) and
      matches_filter?(entry.profile_id, filters.profile_id) and
      matches_filter?(entry.palette_id, filters.palette_id) and
      matches_filter?(entry.test_sheet_id, filters.test_sheet_id)
  end

  defp matches_filter?(_value, nil), do: true
  defp matches_filter?(value, expected), do: value == expected

  defp sort_entries(entries, "illuminant") do
    Enum.sort_by(entries, &{&1.illuminant_label, &1.profile_name, &1.pair_id, recent_key(&1)})
  end

  defp sort_entries(entries, "profile") do
    Enum.sort_by(entries, &{&1.profile_name, &1.illuminant_label, &1.pair_id, recent_key(&1)})
  end

  defp sort_entries(entries, "pair_id") do
    Enum.sort_by(entries, &{&1.pair_id, &1.illuminant_label, &1.profile_name, recent_key(&1)})
  end

  defp sort_entries(entries, "delta_e") do
    Enum.sort_by(entries, &{&1.delta_e || 9_999.0, &1.pair_id, recent_key(&1)})
  end

  defp sort_entries(entries, _sort) do
    Enum.sort_by(entries, &{recent_key(&1), &1.pair_id}, :desc)
  end

  defp recent_key(entry), do: datetime_sort_key(entry.updated_at, entry.id)

  defp profile_name(%PrinterProfile{} = profile) do
    [profile.printer_make_model, profile.paper_type]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" on ")
  end

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

  defp datetime_sort_key(%DateTime{} = datetime, _fallback),
    do: DateTime.to_unix(datetime, :microsecond)

  defp datetime_sort_key(%NaiveDateTime{} = datetime, _fallback) do
    datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)
  end

  defp datetime_sort_key(_datetime, fallback), do: fallback
end

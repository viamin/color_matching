defmodule ColorMatching.Persistence.CaptureJudgmentUpload do
  @moduledoc """
  Validates and appends pair judgment observations for a capture.
  """

  import Ecto.Changeset, only: [add_error: 3]
  import Ecto.Query, only: [from: 2]

  alias ColorMatching.Persistence.{
    Capture,
    PairFinding,
    PairFindingObservation,
    TestSheet,
    TestSheetPair
  }

  alias ColorMatching.Repo

  @type invalid_row :: %{
          index: non_neg_integer(),
          identifier: term(),
          errors: %{optional(atom()) => [String.t()]}
        }

  @type invalid_request :: %{optional(atom()) => [String.t()]}

  @type pair_context :: %{
          test_sheet_id: integer(),
          test_sheet_pair_id: integer(),
          printer_profile_id: integer(),
          pair_id: String.t(),
          color_a_hex: String.t(),
          color_b_hex: String.t()
        }

  @spec upload(Capture.t(), map()) ::
          {:ok, [PairFindingObservation.t()]}
          | {:error, {:invalid_request, invalid_request()}}
          | {:error, {:invalid_rows, [invalid_row()]}}
  def upload(%Capture{id: capture_id, test_sheet_id: test_sheet_id}, attrs)
      when is_integer(capture_id) and is_integer(test_sheet_id) and is_map(attrs) do
    with {:ok, judgments} <- fetch_judgments(attrs),
         pair_context_by_id <- pair_context_by_id(test_sheet_id),
         prepared_judgments <- prepare_judgments(judgments, capture_id, pair_context_by_id),
         [] <- collect_invalid_rows(prepared_judgments),
         {:ok, observations} <- persist(prepared_judgments) do
      {:ok, observations}
    else
      {:error, _reason} = error -> error
      invalid_rows when is_list(invalid_rows) -> {:error, {:invalid_rows, invalid_rows}}
    end
  end

  @spec fetch_judgments(map()) :: {:ok, [map()]} | {:error, {:invalid_request, invalid_request()}}
  defp fetch_judgments(attrs) when is_map(attrs) do
    judgments = Map.get(attrs, "judgments", Map.get(attrs, :judgments))

    cond do
      is_nil(judgments) ->
        {:error, {:invalid_request, %{judgments: ["is required"]}}}

      not is_list(judgments) ->
        {:error, {:invalid_request, %{judgments: ["must be a list"]}}}

      judgments == [] ->
        {:error, {:invalid_request, %{judgments: ["must contain at least one judgment"]}}}

      not Enum.all?(judgments, &is_map/1) ->
        {:error, {:invalid_request, %{judgments: ["must contain only judgment objects"]}}}

      true ->
        {:ok, judgments}
    end
  end

  @spec pair_context_by_id(integer()) :: %{optional(String.t()) => pair_context()}
  defp pair_context_by_id(test_sheet_id) do
    from(pair in TestSheetPair,
      join: sheet in TestSheet,
      on: sheet.id == pair.test_sheet_id,
      where: pair.test_sheet_id == ^test_sheet_id,
      select: %{
        test_sheet_id: pair.test_sheet_id,
        test_sheet_pair_id: pair.id,
        printer_profile_id: sheet.printer_profile_id,
        pair_id: pair.pair_id,
        color_a_hex: pair.color_a_hex,
        color_b_hex: pair.color_b_hex
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.pair_id, &1})
  end

  @spec prepare_judgments([map()], integer(), %{optional(String.t()) => pair_context()}) :: [map()]
  defp prepare_judgments(judgments, capture_id, pair_context_by_id) do
    Enum.with_index(judgments)
    |> Enum.map(fn {judgment_attrs, index} ->
      attrs = normalize_judgment_attrs(judgment_attrs, capture_id, pair_context_by_id)

      changeset =
        %PairFindingObservation{}
        |> PairFindingObservation.changeset(Map.put(attrs, :pair_finding_id, -1))
        |> validate_pair_id(attrs[:pair_id], pair_context_by_id)

      %{index: index, identifier: attrs[:pair_id], attrs: attrs, changeset: changeset}
    end)
  end

  @spec normalize_judgment_attrs(map(), integer(), %{optional(String.t()) => pair_context()}) :: map()
  defp normalize_judgment_attrs(attrs, capture_id, pair_context_by_id) do
    pair_id = fetch_value(attrs, :pair_id)
    pair_context = Map.get(pair_context_by_id, pair_id, %{})

    %{
      capture_id: capture_id,
      test_sheet_id: pair_context[:test_sheet_id],
      test_sheet_pair_id: pair_context[:test_sheet_pair_id],
      printer_profile_id: pair_context[:printer_profile_id],
      pair_id: pair_id,
      color_a_hex: pair_context[:color_a_hex],
      color_b_hex: pair_context[:color_b_hex],
      judgment: fetch_value(attrs, :judgment),
      observed_at: DateTime.utc_now(:microsecond)
    }
  end

  @spec validate_pair_id(
          Ecto.Changeset.t(),
          term(),
          %{optional(String.t()) => pair_context()}
        ) :: Ecto.Changeset.t()
  defp validate_pair_id(changeset, pair_id, pair_context_by_id) do
    if is_binary(pair_id) and Map.has_key?(pair_context_by_id, pair_id) do
      changeset
    else
      add_error(changeset, :pair_id, "is not present on the capture sheet")
    end
  end

  @spec collect_invalid_rows([map()]) :: [invalid_row()]
  defp collect_invalid_rows(prepared_judgments) do
    Enum.flat_map(prepared_judgments, fn prepared_judgment ->
      if prepared_judgment.changeset.valid? do
        []
      else
        [
          %{
            index: prepared_judgment.index,
            identifier: prepared_judgment.identifier,
            errors:
              changeset_errors(prepared_judgment.changeset, [
                :pair_finding_id,
                :capture_id,
                :test_sheet_id,
                :test_sheet_pair_id,
                :printer_profile_id,
                :color_a_hex,
                :color_b_hex,
                :observed_at
              ])
          }
        ]
      end
    end)
  end

  @spec persist([map()]) :: {:ok, [PairFindingObservation.t()]}
  defp persist(prepared_judgments) do
    Repo.transaction(fn ->
      Enum.map(prepared_judgments, &persist_judgment/1)
    end)
  end

  @spec persist_judgment(map()) :: PairFindingObservation.t()
  defp persist_judgment(prepared_judgment) do
    attrs = prepared_judgment.attrs
    pair_finding = find_or_create_pair_finding(attrs)

    {:ok, observation} =
      attrs
      |> Map.put(:pair_finding_id, pair_finding.id)
      |> then(&PairFindingObservation.changeset(%PairFindingObservation{}, &1))
      |> Repo.insert()

    pair_finding
    |> PairFinding.changeset(%{
      current_judgment: observation.judgment,
      current_capture_id: observation.capture_id,
      current_observed_at: observation.observed_at
    })
    |> Repo.update!()

    observation
  end

  @spec find_or_create_pair_finding(map()) :: PairFinding.t()
  defp find_or_create_pair_finding(attrs) do
    case Repo.get_by(PairFinding, test_sheet_pair_id: attrs[:test_sheet_pair_id]) do
      %PairFinding{} = pair_finding ->
        pair_finding

      nil ->
        {:ok, pair_finding} =
          %PairFinding{}
          |> PairFinding.changeset(%{
            test_sheet_id: attrs[:test_sheet_id],
            test_sheet_pair_id: attrs[:test_sheet_pair_id],
            printer_profile_id: attrs[:printer_profile_id],
            pair_id: attrs[:pair_id],
            color_a_hex: attrs[:color_a_hex],
            color_b_hex: attrs[:color_b_hex],
            current_judgment: attrs[:judgment],
            current_capture_id: attrs[:capture_id],
            current_observed_at: attrs[:observed_at]
          })
          |> Repo.insert()

        pair_finding
    end
  end

  @spec fetch_value(map(), atom()) :: term()
  defp fetch_value(attrs, key) when is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  @spec changeset_errors(Ecto.Changeset.t(), [atom()]) :: map()
  defp changeset_errors(changeset, ignored_fields) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Map.drop(ignored_fields)
  end
end

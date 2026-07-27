defmodule ColorMatching.DataCase do
  @moduledoc """
  Test helpers for tests that interact with the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ColorMatching.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ColorMatching.DataCase
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  @spec errors_on(Ecto.Changeset.t()) :: map()
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ColorMatching.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(ColorMatching.Repo, {:shared, self()})
    end

    :ok
  end
end

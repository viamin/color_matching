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

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ColorMatching.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(ColorMatching.Repo, {:shared, self()})
    end

    :ok
  end
end

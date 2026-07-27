ExUnit.start()

{:ok, _, _} =
  Ecto.Migrator.with_repo(ColorMatching.Repo, fn repo ->
    Ecto.Migrator.run(repo, Application.app_dir(:color_matching, "priv/repo/migrations"), :up,
      all: true
    )
  end)

Ecto.Adapters.SQL.Sandbox.mode(ColorMatching.Repo, :manual)

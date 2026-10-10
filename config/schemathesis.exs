import_config "test.exs"

config :color_matching, ColorMatching.Repo,
  database: Path.expand("../color_matching_schemathesis.db", __DIR__),
  pool: Ecto.Adapters.SQL,
  pool_size: 10

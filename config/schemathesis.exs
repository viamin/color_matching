import_config "test.exs"

config :color_matching, ColorMatching.Repo,
  database: Path.expand("../color_matching_schemathesis.db", __DIR__),
  pool: DBConnection.ConnectionPool,
  pool_size: 10

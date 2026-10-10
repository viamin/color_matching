import_config "test.exs"

# Schemathesis exercises the API through a running Phoenix server rather than
# through an ExUnit process. It therefore cannot use the test sandbox, which
# requires every database connection to be checked out by a test process.
config :color_matching, ColorMatching.Repo,
  database: Path.expand("../color_matching_schemathesis.db", __DIR__),
  pool: DBConnection.ConnectionPool,
  pool_size: 10

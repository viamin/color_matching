import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :color_matching, ColorMatchingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fCLNm4SncZcWwKeD1LIP3cbexQe7fx3/QmfjcpLIpxVH4h0WVmmGBc3UEQpPLzyc",
  server: false

# In test we don't send emails
config :color_matching, ColorMatching.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Test coverage configuration
config :excoveralls,
  coverage_options: [
    minimum_coverage: 80,
    skip_files: [
      "test/support/",
      "priv/",
      "lib/color_matching_web/controllers/page_controller.ex",
      "lib/color_matching_web/components/layouts.ex"
    ]
  ]

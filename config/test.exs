import Config
config :the_maestro, Oban, testing: :manual

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :the_maestro, TheMaestro.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: System.get_env("MIX_TEST_PARTITION", "the_maestro_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :the_maestro, TheMaestroWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "po3ahnNmd3zvxzgN5T0h9NlcB0pVQGcsxXnC6Izlpg5wXtsFiAiMsmXi+ksAJv2X",
  server: false,
  sql_sandbox: true

# In test we don't send emails
config :the_maestro, TheMaestro.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Finch pools for HTTP clients - Test (minimal configuration)
config :the_maestro, :finch_pools,
  anthropic: [
    pool_config: [size: 2, count: 1],
    base_url: "https://api.anthropic.com"
  ],
  openai: [
    pool_config: [size: 2, count: 1],
    base_url: "https://api.openai.com"
  ],
  gemini: [
    pool_config: [size: 2, count: 1],
    base_url: "https://generativelanguage.googleapis.com"
  ]

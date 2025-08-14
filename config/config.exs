# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :the_maestro,
  ecto_repos: [TheMaestro.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Authentication configuration - set to false to disable authentication requirement
  require_authentication: true

# Configures the endpoint
config :the_maestro, TheMaestroWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TheMaestroWeb.ErrorHTML, json: TheMaestroWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TheMaestro.PubSub,
  live_view: [signing_salt: "Swrv7mtX"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :the_maestro, TheMaestro.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  the_maestro: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  the_maestro: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for OAuth authentication
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email openid"
       ]}
  ]

# Configure Ueberauth Google strategy with hardcoded credentials (like gemini-cli)
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com",
  client_secret: "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"

# Configure Gemini provider with consistent project ID for all OAuth users
config :the_maestro, :gemini, project_id: "even-setup-7wxx5"

# Configure LLM Provider Selection
# Available providers: :gemini, :openai, :anthropic
# Default provider for new conversations
config :the_maestro, :llm_provider, default: :gemini

# Provider-specific configurations
config :the_maestro, :providers,
  gemini: %{
    module: TheMaestro.Providers.Gemini,
    models: ["gemini-2.5-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
  },
  openai: %{
    module: TheMaestro.Providers.OpenAI,
    models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
    oauth_client_id: {:system, "OPENAI_OAUTH_CLIENT_ID"},
    oauth_client_secret: {:system, "OPENAI_OAUTH_CLIENT_SECRET"},
    api_key: {:system, "OPENAI_API_KEY"}
  },
  anthropic: %{
    module: TheMaestro.Providers.Anthropic,
    models: ["claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"],
    oauth_client_id: {:system, "ANTHROPIC_OAUTH_CLIENT_ID"},
    oauth_client_secret: {:system, "ANTHROPIC_OAUTH_CLIENT_SECRET"},
    api_key: {:system, "ANTHROPIC_API_KEY"}
  },
  google: %{
    # Reuse existing Gemini configuration
    module: TheMaestro.Providers.Gemini,
    models: ["gemini-2.5-flash", "gemini-1.5-pro", "gemini-1.5-flash"],
    oauth_client_id: "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com",
    oauth_client_secret: "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",
    api_key: {:system, "GEMINI_API_KEY"}
  }

# Multi-provider authentication configuration
config :the_maestro, :multi_provider_auth,
  # Encryption key for credential storage (change in production!)
  credential_encryption_key: {:system, "CREDENTIAL_ENCRYPTION_KEY", :crypto.hash(:sha256, "the_maestro_default_key_change_in_production")},
  # Default redirect URIs for OAuth flows
  default_redirect_uris: %{
    anthropic: "http://localhost:4000/auth/anthropic/callback",
    openai: "http://localhost:4000/auth/openai/callback", 
    google: "http://localhost:4000/auth/google/callback"
  },
  # Session timeout (in seconds)
  session_timeout: 3600 * 24,  # 24 hours
  # Credential refresh threshold (refresh when < X seconds remaining)
  refresh_threshold: 300  # 5 minutes

# Configure Shell Tool
config :the_maestro, :shell_tool,
  # Enable/disable the shell tool
  enabled: true,
  # Enable/disable sandboxing (SECURITY: enabled by default)
  sandbox_enabled: true,
  # Docker image for sandbox
  docker_image: "ubuntu:22.04",
  # Command execution timeout
  timeout_seconds: 30,
  # Maximum output size (1MB)
  max_output_size: 1024 * 1024,
  # Optional allowlist of commands (empty = allow all)
  allowed_commands: [],
  # Blocked dangerous commands
  blocked_commands: [
    "rm -rf",
    "dd if=",
    "mkfs",
    "fdisk",
    "parted",
    "shutdown",
    "reboot",
    "halt",
    "init 0",
    "init 6",
    "kill -9 -1"
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

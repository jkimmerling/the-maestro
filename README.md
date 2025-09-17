# The Maestro

The Maestro is an Elixir/Phoenix 1.8 application that orchestrates multi-provider LLM sessions with real-time streaming, OAuth credential management, and tooling support for agents. It ships with both a Phoenix LiveView UI and headless utilities so you can drive Anthropic, OpenAI, and Gemini conversations from browsers, CLIs, and automated workflows.

## Table of Contents

1. [Project Goals](#project-goals)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Development Workflow](#development-workflow)
5. [Provider Credentials](#provider-credentials)
6. [Scripts & Utilities](#scripts--utilities)
7. [Testing & Quality Gates](#testing--quality-gates)
8. [Deployment](#deployment)
9. [Troubleshooting](#troubleshooting)
10. [Additional References](#additional-references)

## Project Goals

- Real-time orchestration of concurrent LLM sessions with Phoenix LiveView front-ends.
- Consistent OAuth and API-key handling for Anthropic, OpenAI, and Gemini providers.
- Centralized business logic in contexts under `lib/the_maestro`, backed by Postgres (Ecto) and Oban job processing.
- Extensible tooling layer so agents can safely call out to shell commands, files, and external APIs.

## Prerequisites

Install the toolchain versions below before running any mix tasks:

- Elixir `~> 1.15` (OTP 26 compatible)
- Erlang/OTP 26 or newer
- PostgreSQL 14+ running locally with a `postgres/postgres` superuser (override via `config/dev.exs`)
- Optional: `direnv` or your preferred env manager for exporting API credentials
- macOS/Linux: ensure `inotify-tools`/`fswatch`-equivalent file watchers are available for asset rebuilds

> **Tip:** Tailwind and esbuild binaries are downloaded automatically by `mix assets.setup`; no global Node.js installation is required.

## Quick Start

1. Clone the repository and switch to the `dev` branch (the default branch).
2. Install Elixir dependencies, database, and assets:

   ```bash
   mix setup
   ```

   The alias runs `deps.get`, creates/migrates the Postgres database, seeds baseline data, installs tailwind/esbuild, and builds initial assets.

3. Start the Phoenix endpoint with live reload:

   ```bash
   mix phx.server
   # or for an IEx shell: iex -S mix phx.server
   ```

   The app serves the LiveView UI at http://localhost:4000.

4. Stop the server with `Ctrl+C` twice when you are done; do **not** background it with artificial timeouts.

### Database Access

- Development DB: `ecto://postgres:postgres@localhost/the_maestro_dev`
- Test DB: `ecto://postgres:postgres@localhost/the_maestro_test`
- Recreate from scratch: `mix ecto.reset`

### Asset Pipeline

- Rebuild once: `mix assets.build`
- Continuous rebuild: handled automatically by dev watchers configured in `config/dev.exs`

## Development Workflow

- Use contexts in `lib/the_maestro` for all business logic; web layers only orchestrate and render.
- Run Oban jobs locally by keeping the Phoenix server running; jobs use the same Postgres database.
- Enable verbose HTTP logging by exporting `HTTP_DEBUG=1` when diagnosing provider calls.
- Review architecture and PRD notes under `docs/` for deeper design background and LiveView conventions.

### Environment Configuration

Create `.envrc` or export variables in your shell profile before launching the server. Common options include:

- `PORT` (defaults to `4000`)
- `PHX_SERVER=1` (only required for `mix release` artifacts)
- `HTTP_DEBUG`, `HTTP_DEBUG_LEVEL`, `STREAM_LOG_UNKNOWN_EVENTS` for deeper request/response logging

## Provider Credentials

Populate the credentials you need for local development or E2E tests. All secrets are stored via `cloak_ecto` in the database, anchored by `SECRET_KEY_BASE`.

| Provider | Minimum Setup | Optional OAuth Settings |
| --- | --- | --- |
| Anthropic | `ANTHROPIC_API_KEY` | `ANTHROPIC_CLIENT_ID`, `ANTHROPIC_REDIRECT_URI` overrides, PKCE helpers in `TheMaestro.Auth` |
| OpenAI | `OPENAI_API_KEY`; optionally `OPENAI_ORG_ID` | `OPENAI_OAUTH_CLIENT_ID`, `OPENAI_REDIRECT_URI`, `OPENAI_PROJECT`, `OPENAI_SESSION_NAME`, `OPENAI_OAUTH_STRICT` |
| Gemini | `GOOGLE_API_KEY` or `GEMINI_API_KEY` | `GEMINI_OAUTH_CLIENT_ID`, `GEMINI_OAUTH_CLIENT_SECRET`, `GEMINI_OAUTH_REDIRECT_URI`, `GEMINI_SESSION_NAME`, `GEMINI_USER_PROJECT` |

### Managing Sessions & OAuth

- Launch IEx helpers:
  ```elixir
  iex -S mix
  {:ok, {auth_url, pkce}} = TheMaestro.Auth.generate_gemini_oauth_url()
  {:ok, _} = TheMaestro.Auth.finish_gemini_oauth("AUTH_CODE", pkce, "personal_gemini_oauth")
  ```
- Use CLI scripts for headless flows from the `scripts/` directory, for example:
  ```bash
  mix run scripts/gemini_oauth_cli_helper.exs start personal_gemini_oauth
  mix run scripts/gemini_oauth_cli_helper.exs finish personal_gemini_oauth AUTH_CODE
  mix run scripts/e2e_dual_prompt_stream_test.exs openai personal_openai_oauth
  ```
- Import existing Codex-auth or token data with helpers like `mix run scripts/import_codex_auth_to_session.exs`.

Refer to `docs/examples/*-provider-examples.md` for provider-specific walkthroughs, payload formats, and troubleshooting steps.

## Scripts & Utilities

Key automation entry points live under `scripts/`:

- `production_readiness_suite.exs` – smoke tests for agents, streaming, and OAuth
- `test_*_streaming_e2e.exs` – end-to-end streaming coverage per provider
- `run_*_oauth_agent_loop.exs` – continuously refresh OAuth tokens in development
- `dev_purge_auths_sessions_agents.exs` – reset local database records in a pinch

Invoke scripts with `mix run scripts/<name>.exs [args]`. Use `RUN_REAL_API_TEST=1` when you intend to hit live provider endpoints during automated tests.

## Testing & Quality Gates

Integration coverage is mandatory.

- Run targeted tests: `mix test test/path/to/file_test.exs`
- Full suite: `mix test`
- Pre-flight checks enforced by CI/hooks: `mix precommit`
  - Runs compilation with warnings-as-errors, unlocks unused deps, formats, and executes the full test suite.

LiveView integration tests rely on `Phoenix.LiveViewTest` and `LazyHTML`; ensure selectors align with DOM IDs defined in templates. Add new tests for every feature or fix—unit tests alone are insufficient.

## Deployment

1. Collect production secrets:
   - `DATABASE_URL`
   - `SECRET_KEY_BASE`
   - Provider API keys and OAuth client credentials (see table above)
   - Optional: `DNS_CLUSTER_QUERY`, `PHX_HOST`, `PORT`

2. Build a release:

   ```bash
   MIX_ENV=prod mix release
   ```

3. Run the release on your target host:

   ```bash
   PHX_SERVER=true DATABASE_URL=ecto://... SECRET_KEY_BASE=... bin/the_maestro start
   ```

4. For zero-downtime deploys, manage migrations manually:

   ```bash
   bin/the_maestro eval "TheMaestro.Release.migrate"
   ```

5. Configure HTTPS and clustering as needed (see `config/runtime.exs` comments for `https` and IPv6 examples).

## Troubleshooting

- **Watcher doesn’t rebuild assets** – ensure `mix assets.setup` installed toolchains and you have filesystem watchers available (Linux: `inotify-tools`, macOS: built-in FSEvents).
- **Provider requests fail** – export the relevant API key/OAuth environment variables and check `HTTP_DEBUG=1` logs.
- **Oban jobs stuck** – confirm Postgres is running and migrations are up-to-date; clear jobs with `Oban.drain_queue/1` inside IEx for local debugging.
- **Sessions missing after reset** – run `mix run scripts/dev_purge_auths_sessions_agents.exs` cautiously to wipe dev data before re-importing credentials.

## Additional References

- Architecture overview: `docs/architecture.md`
- Product requirements, epics, and standards: `docs/prd/`
- API usage examples per provider: `docs/examples/`
- Debugging guides: `docs/http-debugging.md`

For Phoenix framework fundamentals and releases, consult HexDocs:

- Phoenix Guides – https://hexdocs.pm/phoenix/overview.html
- Phoenix Deployment – https://hexdocs.pm/phoenix/deployment.html
- Mix Tasks Reference – https://hexdocs.pm/mix/Mix.Tasks.html


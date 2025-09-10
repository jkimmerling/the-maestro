Title: Phoenix Contexts + Ecto Overhaul — Generator-First, Context-Only Access
Date: 2025-09-09
Owner: TBD (Dev Lead)
Status: Draft for review — iteration 2 (answers applied)

Summary
- Goal: Migrate EVERY table and all DB‑touching logic to proper Phoenix‑generated contexts and schemas, standardize ALL tables to `binary_id`, and perform a full baseline refresh of DB migrations. Eliminate direct `Repo` usage outside contexts, normalize directory structure, and align to Phoenix v1.8 generator patterns.
- Why: Current data layer mixes schemas, queries, and business logic across modules and directories. This breaks Phoenix best practices, complicates maintenance, and increases risk. A clean baseline eliminates drift and enforces consistent IDs, naming, and boundaries.

Out of Scope (for this doc)
- No code changes in this PR; this is a planning/story document only.
- No UI redesign beyond what’s required to shift table access through contexts.

Acceptance Criteria
- Each table has a Phoenix‑generated context and schema in the canonical locations.
- All tables use `binary_id` (including `saved_authentications`).
- No direct `Repo.*` calls outside of context modules (exceptions: seeds and data migrations).
- All domain modules call context APIs (create/update/delete/get/list) rather than accessing schemas or `Repo` directly.
- Generators are used for (re)creating schemas and migrations as the new baseline (full refresh approach).
- No seeds required; system boots clean with empty tables.
- `mix precommit` passes without bypassing hooks. Zero tolerance for `--no-verify` or force push.
- SuppliedContext UI supports server‑side search, pagination, and bulk delete of items.
 - Direct `Repo` usage is allowed only for Oban housekeeping inside TokenRefreshWorker (leave Oban alone); all other Repo calls must be within contexts.

Glossary
- Context: API boundary for a business domain (e.g., `TheMaestro.Conversations`).
- Schema: Ecto schema for a table (e.g., `TheMaestro.Conversations.Session`).
- Repo: Persistence adapter that must only be used inside contexts (and migrations/seeds).

Current State (quick inventory)
- Tables in use: `saved_authentications`, `base_system_prompts`, `personas`, `sessions`, `chat_history` (plus historical `agents`). Oban managed by its own migrations.
- Mismatch: `saved_authentications` uses integer PK; others largely use `binary_id`.
- Repo usage appears in LiveView (`session_chat_live`), workers (`token_refresh_worker`), and the `SavedAuthentication` schema module itself.
- `TheMaestro.Prompts` and `TheMaestro.Personas` exist as separate contexts; these will be unified per decision below.

Target Architecture (generator‑style)
- Contexts and schemas per Phoenix defaults, one schema per file under its context folder.
- Standardize ALL PKs/FKs to `binary_id`.
- Context map:
  - Auth
    - Schema: `Auth.SavedAuthentication` (binary_id)
    - Context: `TheMaestro.Auth` — single API for saved auths; move all DB ops from schema into context.
  - Conversations
    - Schemas: `Conversations.Session`, `Conversations.ChatEntry` (both binary_id)
    - Context: `TheMaestro.Conversations` — only API for sessions/chats; extract `ChatEntry` schema into its own file.
  - SuppliedContext (Unified)
    - Purpose: replace separate Prompts/Personas contexts with a single context and table.
    - Schema: `SuppliedContext.SuppliedContextItem` with fields:
      - `id :binary_id`
      - `type :enum` (values: `:persona`, `:system_prompt`)
      - `name :string` (unique within type)
      - `text :text` (prompt/persona body)
      - `version :integer` (default 1)
      - `tags :map`
      - `metadata :map`
    - Context: `TheMaestro.SuppliedContext` — single API for listing/selecting items by `type`.

Generator Commands (new baseline)
Note: Because we are doing a full refresh, these commands generate both contexts and migrations with `--binary-id`.

- Auth — SavedAuthentication (binary_id)
  - `mix phx.gen.context Auth SavedAuthentication saved_authentications provider:string auth_type:string credentials:map expires_at:utc_datetime --binary-id`

- Conversations — Session (binary_id)
  - `mix phx.gen.context Conversations Session sessions name:string last_used_at:utc_datetime latest_chat_entry_id:binary_id auth_id:references:saved_authentications model_id:string persona:map memory:map tools:map mcps:map working_dir:string --binary-id`

- Conversations — ChatEntry (binary_id)
  - `mix phx.gen.context Conversations ChatEntry chat_history turn_index:integer actor:string provider:string request_headers:map response_headers:map combined_chat:map edit_version:integer session_id:references:sessions thread_id:binary_id parent_thread_id:binary_id fork_from_entry_id:binary_id thread_label:string --binary-id`

- SuppliedContext — SuppliedContextItem (unified for personas + system prompts)
  - `mix phx.gen.context SuppliedContext SuppliedContextItem supplied_context_items type:enum:persona:system_prompt name:string text:text version:integer tags:map metadata:map --binary-id`
  - Note: `type` will be an `Ecto.Enum` in the schema; DB column remains `:string`.

Directory/Layout Normalization
- Move all schemas to `lib/the_maestro/<context>/<schema>.ex`.
- Ensure contexts are under `lib/the_maestro/<context>.ex` and expose only context functions to callers.
- Remove schema modules that also house querying/business logic; place all DB ops in contexts.
- Ensure test modules follow the same directory structure and naming.

Baseline Refresh Strategy (Hard Cutover — Domain‑Only Drop; DO NOT TOUCH OBAN)
- We will produce a clean set of generator‑authored migrations as the new canonical baseline and perform a hard cutover for domain tables only. Oban tables remain intact.
- Guardrails:
  - Perform this first in dev/test. For staging/prod, schedule a maintenance window; destructive change is expected. No exporter/importer; no backward compatibility.
  - Archive old domain migrations under `priv/repo/_archive/` (Oban migrations left untouched) before removing them from `priv/repo/migrations/`.
  - Ensure application config sets generator defaults:
    - `config :the_maestro, :generators, migration: true, binary_id: true, timestamp_type: :utc_datetime`
- Domain‑Only Drop & Rebuild steps (once PRs are ready):
  1) Pause app background workers (pause Oban queues) but DO NOT drop Oban tables.
  2) Add a one‑time migration to drop only domain tables if they exist: `saved_authentications`, `sessions`, `chat_history`, legacy `personas`, legacy `base_system_prompts`, legacy `agents`.
  3) Generate contexts/schemas/migrations with commands above (including `supplied_context_items`).
  4) Run `mix ecto.migrate` (do not run `mix ecto.drop`/`mix ecto.create`).
  5) No seeding required.
  6) Run `mix test`, `mix credo --strict`, `mix precommit`.

Research summary (Archon alt due to local absence)
- Contexts encapsulate data access and validation; web layers (controllers/live) call context APIs, not `Repo` directly. Phoenix guides emphasize contexts as the core boundary for interacting with Ecto and external systems. [See References]
- Generators support `--binary-id` to produce UUID primary keys and reference types. Defaults can be set under `config :your_app, :generators` (migration: true, binary_id: false by default, timestamp type). Verified locally via `mix help` and cross‑checked with Phoenix docs. [See References]
- `Ecto.Enum` is appropriate when storing atom states as strings/integers at the DB level (schema uses `Ecto.Enum`, migration uses `:string` or `:integer`). Good fit for `SuppliedContextItem.type` with values `:persona | :system_prompt`. [See References]
- LiveView/UI patterns: use context APIs and the standard components (`<.form>`, `<.input>`, `Layouts.app`), matching our project standards and Phoenix v1.8 guidance.

References (official docs)
- Phoenix Contexts guide (v1.8): https://hexdocs.pm/phoenix/1.8.0/contexts.html
- mix phx.gen.context (latest): https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.Context.html
- mix phx.gen.schema (1.7 series): https://hexdocs.pm/phoenix/1.7.0-rc.3/Mix.Tasks.Phx.Gen.Schema.html
- Ecto.Enum (v3.13): https://hexdocs.pm/ecto/Ecto.Enum.html

Eliminate Direct Repo Usage (inventory‑driven)
- Replace all direct `Repo` calls outside contexts with context functions.
  - `lib/the_maestro_web/live/session_chat_live.ex` — use `Conversations.get_session!/2` or explicit preload helpers in context.
  - `lib/the_maestro/workers/token_refresh_worker.ex` — introduce `Auth` context functions for find/rotate/cleanup; ensure worker depends only on `Auth` API.
  - `lib/the_maestro/auth/persistence/saved_authentication.ex` — strip `Repo` calls; move into `TheMaestro.Auth` context.
  - `lib/the_maestro/core/conversations/conversations.ex` — extract `ChatEntry` schema to its own file; keep all DB ops inside this context.
- Add missing context functions as needed (list/get/create/update/delete variants + specialized queries with preloads/filters).

Refactor Plan — Phases & Checklists

- Phase 0 — Research & Setup
  - [x] Archon RAG (before coding):
        archon:perform_rag_query(query="Phoenix contexts and Ecto best practices", match_count=4)
        archon:perform_rag_query(query="Elixir Ecto context boundaries and Repo usage", match_count=4)
        archon:search_code_examples(query="phx.gen.context --binary-id usage examples", match_count=3)
        Note (2025-09-10): Archon MCP not installed locally; performed equivalent research via official Phoenix/Ecto docs. See "Research summary" below.
  - [x] Verify generator switches locally: `mix help phx.gen.context`, `mix help phx.gen.schema` (verified 2025-09-10)
  - [x] PK strategy: standardize to `binary_id` for ALL tables (confirmed)

- Phase 1 — Generate Contexts & Schemas (new baseline)
  - [x] Run generators listed above with `--binary-id` to create contexts, schemas, and migrations
        Progress (2025-09-10):
        - Generated SuppliedContext + SuppliedContextItem (context + schema + migration).
        - Generated Auth.SavedAuthentication (schema + migration); added Auth context functions.
        - Generated Conversations.ChatEntry (schema + migration) and extracted to its own file.
        - Added Sessions baseline migration. Will reconcile with existing schema during cutover.
  - [ ] Move/merge any existing schema logic into generated schema files
  - [x] Extract `ChatEntry` schema from `core/conversations/conversations.ex` into `lib/the_maestro/conversations/chat_entry.ex`
  - [ ] Ensure changesets live with schemas and business logic lives in contexts only

- Phase 2a — Legacy Code Refactor (File-by-file checklist)
  - Core (lib/the_maestro)
    - [ ] `lib/the_maestro/auth/persistence/saved_authentication.ex`
      - Action: split and relocate; keep only schema + changeset
      - Move schema to `lib/the_maestro/auth/saved_authentication.ex` (module `TheMaestro.SavedAuthentication`) generated with `--binary-id`.
      - Replace field types to match new baseline (e.g., `id: binary_id`, `provider: :string`, `auth_type: Ecto.Enum`, `credentials: :map`, `expires_at: :utc_datetime`).
      - Remove ALL Repo/Ecto.Query functions from this module:
        - get_by_provider_and_name/3, list_by_provider/1, list_all/0, get!/1, update/2,
          create_named_session/4, upsert_named_session/4, delete_named_session/3,
          clone_named_session/4, get_by_provider/2, get_named_session/3.
      - Re-home those functions in `TheMaestro.Auth` context with new names and signatures:
        - `Auth.list_saved_authentications/0`, `Auth.list_saved_authentications_by_provider/1`,
          `Auth.get_saved_authentication!/1`, `Auth.get_saved_authentication_by/1`,
          `Auth.create_saved_authentication/1`, `Auth.update_saved_authentication/2`,
          `Auth.delete_saved_authentication/1`, `Auth.upsert_saved_authentication/1` (if needed),
          `Auth.get_named_session/3`, `Auth.delete_named_session/3`.
      - Update callers accordingly (see items below).

    - [ ] `lib/the_maestro/core/conversations/conversations.ex`
      - Action: split schema and relocate context to generator layout; keep context-only Repo usage
      - [x] Extract `TheMaestro.Conversations.ChatEntry` schema into `lib/the_maestro/conversations/chat_entry.ex` (generated).
      - Create/ensure `lib/the_maestro/conversations.ex` contains only context functions (CRUD + queries) for `Session` and `ChatEntry`.
      - Update functions expecting integer auth IDs (e.g., `latest_session_for_auth_id/1`) to accept binary_id (uuid) if retained; consider renaming to `latest_session_for_auth/1` with map argument.
      - After migration, delete `lib/the_maestro/core/conversations/conversations.ex`.

    - [x] `lib/the_maestro/conversations/session.ex`
      - Action: align schema with generator output and baseline fields (`auth_id` as binary_id ref, `model_id`, `persona` map, `memory` map, `tools` map, `mcps` map, `latest_chat_entry_id`, `working_dir`).
      - Ensure changeset matches new validations (no provider field; enforce presence as required by new flows).

    - [ ] `lib/the_maestro/core/prompts/prompts.ex`
      - Action: remove file; replace with `TheMaestro.SuppliedContext` calls filtered by `type: :system_prompt`.
      - Update all callers (see web list) to use:
        - `SuppliedContext.list_items(:system_prompt)`
        - `SuppliedContext.get_item!(id)`
        - `SuppliedContext.create_item(%{type: :system_prompt, name: ..., text: ..., version: ..., tags: ..., metadata: ...})`
        - `SuppliedContext.update_item(item, attrs)`
        - `SuppliedContext.delete_item(item)`

    - [ ] `lib/the_maestro/prompts/base_system_prompt.ex`
      - Action: remove schema; replaced by `SuppliedContext.SuppliedContextItem` with `type: :system_prompt`.

    - [ ] `lib/the_maestro/core/agents/personas.ex`
      - Action: remove file; replace with `TheMaestro.SuppliedContext` calls filtered by `type: :persona`.
      - Update callers to use the `SuppliedContext` API equivalents listed above (with `type: :persona`).

    - [ ] `lib/the_maestro/personas/persona.ex`
      - Action: remove schema; replaced by `SuppliedContext.SuppliedContextItem` with `type: :persona`.

    - [ ] `lib/the_maestro/workers/token_refresh_worker.ex`
      - Action: remove direct Repo/Ecto.Query usage against domain tables; call `TheMaestro.Auth` context
      - `do_refresh/1`: replace Repo lookups with `Auth.get_saved_authentication!/1` (binary_id). Remove `parse_int/1` path.
      - `fallback_http_refresh/3`: replace Repo lookup with `Auth.get_saved_authentication!/1` (binary_id).
      - `update_stored_token/2`: replace `Repo.update(changeset)` with `Auth.update_saved_authentication(saved_auth, %{credentials: ..., expires_at: ...})`.
      - `cancel_for_auth/1`: leave Oban cleanup logic intact (interacts with Oban tables); keep as-is per “do not touch Oban tables”.
      - Update aliases: remove `alias TheMaestro.Repo`; add `alias TheMaestro.Auth`.

    - [ ] `lib/the_maestro/infrastructure/repo.ex`
      - Action: keep as-is (Ecto.Repo definition).

  - Web (lib/the_maestro_web)
    - [ ] `lib/the_maestro_web/live/session_chat_live.ex`
      - Remove direct `TheMaestro.Repo.preload([:saved_authentication])` in `mount/3`; `Conversations.get_session_with_auth!/1` already preloads.
      - Replace all `TheMaestro.Personas.*` usage with `TheMaestro.SuppliedContext` calls:
        - create persona → `SuppliedContext.create_item(%{type: :persona, name: ..., text: ...})`
        - list personas → `SuppliedContext.list_items(:persona)`
        - get persona → `SuppliedContext.get_item!(id)`
      - Ensure any references to persona structs adapt to `SuppliedContextItem` fields (`text` instead of `prompt_text`, use `metadata` for extras).
      - Replace SavedAuthentication calls with `TheMaestro.Auth` context and drop integer casting:
        - Lines ~777, ~794: `TheMaestro.SavedAuthentication.get!(session.auth_id)` → `Auth.get_saved_authentication!(session.auth_id)`
        - Line ~815: `TheMaestro.SavedAuthentication.list_by_provider(provider)` → `Auth.list_saved_authentications_by_provider(provider)`
        - Line ~856: `TheMaestro.SavedAuthentication.get!(to_int(a))` → `Auth.get_saved_authentication!(a)` (binary_id string)

    - [x] `lib/the_maestro_web/live/dashboard_live.ex`
      - Replace SavedAuthentication calls from schema module with `TheMaestro.Auth` context:
        - `SavedAuthentication.list_all()` → `Auth.list_saved_authentications()`
        - `SavedAuthentication.list_by_provider(provider)` → `Auth.list_saved_authentications_by_provider(provider)`
        - `SavedAuthentication.get!(id)` → `Auth.get_saved_authentication!(id)`
      - Replace prompt/persona option builders to use `SuppliedContext`:
        - `build_prompt_options/0` → `SuppliedContext.list_items(:system_prompt) |> Enum.map(&{&1.name, &1.id})`
        - `build_persona_options/0` → `SuppliedContext.list_items(:persona) |> Enum.map(&{&1.name, &1.id})`
      - Keep model listing via `Provider.list_models/3` unchanged.

    - [x] `lib/the_maestro_web/live/auth_edit_live.ex`
      - Replace `TheMaestro.SavedAuthentication.get!/1` and `SavedAuthentication.update/2` with `TheMaestro.Auth.get_saved_authentication!/1` and `Auth.update_saved_authentication/2`.
      - Remove integer parsing (`String.to_integer/1`); IDs are binary_id strings.

    - [x] `lib/the_maestro_web/live/auth_show_live.ex`
      - Replace `TheMaestro.SavedAuthentication.get!/1` usages with `TheMaestro.Auth.get_saved_authentication!/1`.
      - Remove integer parsing of IDs.

    - [x] `lib/the_maestro_web/live/session_edit_live.ex`
      - Update `auth_options/0` to use `TheMaestro.Auth.list_saved_authentications/0` and map ids as strings (binary_id).

    - [x] `lib/the_maestro_web/controllers/the_maestro_web/session_controller.ex`
      - Update private `auth_options/0` to use `TheMaestro.Auth.list_saved_authentications/0` and binary_id strings.

    - [ ] `lib/the_maestro_web/live/base_system_prompt_live/index.ex`
      - Action: retire (UI superseded by unified SuppliedContext). Remove routes; or rewrite to use `SuppliedContext` filtered by `type: :system_prompt`.

    - [ ] `lib/the_maestro_web/live/base_system_prompt_live/form.ex`
      - Action: retire or rewrite to create/update `SuppliedContextItem` with `type: :system_prompt`.

    - [ ] `lib/the_maestro_web/live/base_system_prompt_live/show.ex`
      - Action: retire or rewrite to show `SuppliedContextItem` with `type: :system_prompt`.

    - [ ] `lib/the_maestro_web/live/persona_live/index.ex`
      - Action: retire or rewrite to use `SuppliedContext` filtered by `type: :persona`.

    - [ ] `lib/the_maestro_web/live/persona_live/form.ex`
      - Action: retire or rewrite to create/update `SuppliedContextItem` with `type: :persona`.

    - [ ] `lib/the_maestro_web/live/persona_live/show.ex`
      - Action: retire or rewrite to show `SuppliedContextItem` with `type: :persona`.

    - [ ] `lib/the_maestro_web/router.ex`
      - Remove routes for `/base_system_prompts*` and `/personas*` if retiring those UIs.
      - If keeping UIs, update routes/modules to point to new SuppliedContext screens.

- Phase 2b — SuppliedContext LiveView CRUD UI
  - [ ] Generate LiveView screens (no duplicate context/schema)
        Command:
        - `mix phx.gen.live SuppliedContext SuppliedContextItem supplied_context_items type:enum:persona:system_prompt name:string text:text version:integer tags:map metadata:map --no-context --no-schema`
        Notes:
        - We already generated the context/schema; `--no-context --no-schema` prevents duplication.
        - Keep binary_id usage in forms by binding to existing schema.
  - [ ] Add routes in `lib/the_maestro_web/router.ex` (browser scope)
        - `live "/supplied_context", SuppliedContextItemLive.Index, :index`
        - `live "/supplied_context/new", SuppliedContextItemLive.Form, :new`
        - `live "/supplied_context/:id", SuppliedContextItemLive.Show, :show`
        - `live "/supplied_context/:id/edit", SuppliedContextItemLive.Form, :edit`
  - [ ] Implement LiveView modules (generator stubs) under `lib/the_maestro_web/live/supplied_context_item_live/`
        - `index.ex` — list + stream items, type filter tabs (persona/system_prompt)
        - `form.ex` — create/edit with fields: `type` (select), `name` (text), `text` (textarea), `version` (number), `tags` (JSON textarea), `metadata` (JSON textarea)
        - `show.ex` — read-only view with edit link
        - Always wrap templates in `<Layouts.app flash={@flash}> ... </Layouts.app>`
        - Use `to_form/2` and `<.form for={@form} ...>` and `<.input ...>` components per project standards
        - Give unique IDs to key elements: `id="supplied-context-form"`, table `id="supplied-context-items"`
  - [ ] Wire the LiveViews to `TheMaestro.SuppliedContext` API
        - list → `SuppliedContext.list_items/1` filtered by `type`
        - get → `SuppliedContext.get_item!/1`
        - create → `SuppliedContext.create_item/1` (ensure `type` present)
        - update → `SuppliedContext.update_item/2`
        - delete (single) → `SuppliedContext.delete_item/1`; bulk → `SuppliedContext.delete_items/1`
  - [ ] Navigation
        - Add a link to the new Index from Dashboard or a global nav (e.g., “Context Library”)
  - [ ] Tests (LiveView)
        - `test/the_maestro_web/live/supplied_context_item_live/index_test.exs` — lists, filter by type, navigate to new/show/edit
        - `test/the_maestro_web/live/supplied_context_item_live/form_test.exs` — validate/save flows, JSON fields
        - `test/the_maestro_web/live/supplied_context_item_live/show_test.exs` — displays and edits
        - Use `Phoenix.LiveViewTest`, element selectors by IDs added above
  - [ ] Remove legacy Prompts/Personas LiveViews and routes (if fully replaced)


- Phase 2 — Migrate Callers to Context APIs
  - [ ] Replace all direct `Repo` usage in LiveViews/Workers with context calls
  - [ ] Add any required context query helpers (preloads, filters)
  - [ ] Delete lingering `alias TheMaestro.Repo` usage outside contexts

- Phase 3 — Baseline Refresh Execution
  - [ ] Archive old domain migrations into `priv/repo/_archive/`
  - [ ] Add one‑time migration to drop domain tables only (not Oban)
  - [ ] Run new generator migrations (no `ecto.drop`)
  - [ ] No seeds required
  - [ ] Ensure `mix ecto.migrate` is clean on dev/staging; coordinate maintenance window for prod

- Phase 4 — Tests & Quality Gates
  - [ ] Update/expand context tests for CRUD and specialized queries
  - [ ] Update worker/live tests to use contexts (no direct Repo)
  - [ ] `mix test` all passing
  - [ ] `mix credo --strict` clean
  - [ ] `mix precommit` clean (never bypass hooks)

- Phase 5 — Cleanup & Docs
  - [ ] Remove obsolete modules/aliases; ensure no duplicate schemas remain
  - [ ] Update architecture docs to reflect new context boundaries
  - [ ] Verify directory structure matches Phoenix defaults

Detailed Tasks with Subtasks

- Context: Auth
  - [ ] Generate `TheMaestro.Auth` + `SavedAuthentication` schema (see commands)
  - [ ] Move functions from `lib/the_maestro/auth/persistence/saved_authentication.ex` into `Auth` context
  - [ ] Reduce schema module to changeset + pure struct concerns
  - [ ] Replace all callers with `Auth.*` functions (workers, live views, services)

- Context: Conversations
  - [x] Ensure `Session` schema lives under `lib/the_maestro/conversations/session.ex`
  - [x] Extract `ChatEntry` schema into `lib/the_maestro/conversations/chat_entry.ex`
  - [ ] Ensure all queries (list/get/create/update/delete, plus thread helpers) live in `TheMaestro.Conversations`
  - [ ] Replace preloads done via `Repo.preload` in LiveViews with `Conversations` API

- Context: SuppliedContext (replaces Prompts + Personas)
  - [x] Generate `TheMaestro.SuppliedContext` + `SuppliedContextItem` schema (see commands)
  - [ ] Replace usage of `Prompts` and `Personas` with `SuppliedContext` API filtered by `type`
  - [ ] Remove/retire old contexts and schemas for Prompts/Personas after cutover

Quality/Policy Gates
- Never bypass git hooks (forbidden: `git commit --no-verify`, `git push --force`, etc.).
- If hooks fail, fix issues (format, test, lint, security) and re‑run.
- Manual testing: run the server long‑lived; do NOT use `10s` timeouts for background processes.

Dev Notes
- Phoenix v1.8 generators:
  - Prefer `phx.gen.context` for context + schema; for this baseline refresh we WILL generate fresh migrations.
  - Use `--binary-id` for uuid PK schemas (sessions/chat_history/personas/base_system_prompts). Keep consistency across schemas and FKs.
- Ecto guidelines (project standards):
  - Only contexts use `Repo.*` (plus migrations/seeds).
  - Do not access changesets or structs via access syntax; use `get_field/2` or direct struct fields.
  - No nested modules in a single file to avoid cyclic deps.
  - Prefer `Task.async_stream(..., timeout: :infinity)` for safe parallel enumeration.
- Testing:
  - Focus on context API behaviors and integration points (workers/live views).
  - For LiveView tests, assert on element presence/selectors, not raw HTML.
 - CI (MVP/POC): no CI guard required; manual review will check for direct Repo usage outside contexts.

Files Touched/Created (planned)
- This document
  - [x] `docs/overhauls/2025-09-09-phoenix-contexts-and-ecto-overhaul-story.md`
- New/updated (to be created by generators and refactors; not included in this PR):
  - `lib/the_maestro/auth.ex`
  - `lib/the_maestro/auth/saved_authentication.ex`
  - `lib/the_maestro/conversations.ex` (ensure context only contains functions)
  - `lib/the_maestro/conversations/session.ex` (schema only)
  - `lib/the_maestro/conversations/chat_entry.ex` (schema only)
  - `lib/the_maestro/supplied_context.ex` and `lib/the_maestro/supplied_context/supplied_context_item.ex` (new unified context+schema)
  - New LiveView UI (generated without context/schema):
    - `lib/the_maestro_web/live/supplied_context_item_live/index.ex`
    - `lib/the_maestro_web/live/supplied_context_item_live/form.ex`
    - `lib/the_maestro_web/live/supplied_context_item_live/show.ex`
    - Router entries in `lib/the_maestro_web/router.ex`
  - New tests (planned):
    - `test/the_maestro_web/live/supplied_context_item_live/index_test.exs`
    - `test/the_maestro_web/live/supplied_context_item_live/form_test.exs`
    - `test/the_maestro_web/live/supplied_context_item_live/show_test.exs`
  - Updated callers:
    - `lib/the_maestro_web/live/session_chat_live.ex`
    - `lib/the_maestro/workers/token_refresh_worker.ex`
    - Any service modules currently aliasing `Repo`

Risks & Mitigations
- Destructive baseline refresh (data loss):
  - Mitigation: stage in dev/test first; require explicit prod approval + maintenance window; acknowledge data reset as part of the cutover (no exporter/importer).
- Hidden direct `Repo` usages may be missed:
  - Mitigation: CI step running `rg -n "\bRepo\.[a-z_]+\(" lib | rg -v "^lib/the_maestro/(.+)/(?:.+)\.ex$"` and failing on non‑context hits.
- Schema moves may break module references:
  - Mitigation: incremental PRs per context; alias maps updated; run `mix xref graph` to find dangling refs.

Rollout Plan
- Small PRs per context to reduce blast radius:
  1) Auth context + worker/live fixes
  2) Conversations schemas split + preload APIs
  3) SuppliedContext integration (replace Prompts/Personas) and retire old contexts
  4) Final sweep to remove stray `Repo` usage
- After each PR:
  - Run `mix test`, `mix credo --strict`, `mix precommit`.
  - Perform manual flows without server timeout limits.

Implementation PR Plan & Sequencing
- PR 1: Auth baseline
  - Add `TheMaestro.Auth` + `SavedAuthentication` schema/context (binary_id).
  - Migrate web callers (dashboard, auth_* liveviews, controllers) to `Auth`.
  - Update TokenRefreshWorker to use `Auth` for domain tables; keep Oban Repo calls.
  - Domain-only drop migration (saved_authentications) and regen new migration.

- PR 2: Conversations split
  - Generate `Conversations.Session` and `Conversations.ChatEntry` schemas and migrate context to `lib/the_maestro/conversations.ex`.
  - Extract ChatEntry schema out of `core/conversations/conversations.ex` and remove legacy file.
  - Align `session_chat_live` preload and helpers to new context functions.
  - Domain-only drop and regen for sessions/chat_history if needed.

- PR 3: SuppliedContext baseline
  - Generate `SuppliedContext.SuppliedContextItem` + `TheMaestro.SuppliedContext`.
  - Remove legacy Prompts/Personas contexts and schemas.
  - Domain-only drop and regen for `supplied_context_items`.
  - Update web callers (dashboard, session_chat_live) to SuppliedContext.

- PR 4: SuppliedContext LiveView UI (CRUD + search + pagination + bulk delete)
  - Generate LiveViews with `--no-context --no-schema`, add routes and tests.
  - Implement server-side search/pagination; implement bulk delete.
  - Add “Context Library” link in dashboard or nav.

- PR 5: Final cleanup
  - Remove retired routes and LiveViews (Prompts/Personas).
  - Repository-wide pass to ensure no stray `Repo` usage outside contexts (excluding Oban).
  - Update docs and ADRs; confirm hooks passing.

Resolved Decisions (locked)
1) SuppliedContext context/table finalized:
   - Context `TheMaestro.SuppliedContext`, table `supplied_context_items`, schema `SuppliedContext.SuppliedContextItem`.
   - `type` uses `Ecto.Enum` with values `:persona` and `:system_prompt`.
   - Extra fields: `version :integer`, `tags :map`, `metadata :map`.
2) Production cutover: hard, surgical drop & rebuild; no backward compatibility and no exporter/importer.
3) CI guard: not required for MVP/POC; rely on code review and repo search.

Next Steps
- Finalize and commit the generator command set (above) as the authoritative baseline plan.
- I will prepare the first implementation PR plan focusing on Auth + Conversations + SuppliedContext baseline generation (no CI guard work for now).

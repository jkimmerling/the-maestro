# Overhaul Story: MCP Protocol Integration Across Codex, Gemini, Claude Code, and OpenAI

This document defines the plan to add Model Context Protocol (MCP) support to our framework while preserving and interleaving existing LLM (OpenAI) API flows. It includes scope, architecture approach, transports, configuration, security, testing, acceptance criteria, risks, and a detailed task checklist. This is a documentation-only deliverable; no code changes are included here.

## Summary

- Add first-class MCP Client and MCP Server capabilities alongside existing non-MCP LLM calls (both roles in this phase).
- Support multiple MCP transports: `STDIO`, `SSE` (HTTP streaming, text/event-stream), and `HTTP` (request/response).
- Integrate with current tools and agent sessions so that:
  - Our framework can call out to strict MCP servers used by Codex, Gemini CLI, and Claude Code.
  - Our own agent sessions can be exposed “as an MCP server” so one agent session can request help from another (code advice, search, test creation, etc.).
- Provide DB-backed configuration for endpoints/transports with secrets loaded from ENV; redact secrets in logs.
- Ensure compatibility with existing OpenAI API usage and routing (non-breaking default behavior).
 - UI: Session Config modal offers a dropdown of installed/configured MCPs; a separate “MCP Connections” page manages installations and advanced settings.

## Decisions & Constraints (Locked-In)

- Deliver both MCP Client and MCP Server now; agents must both expose and consume MCP.
- Runtime is Elixir-only; follow project standards (use `Req` for HTTP, OTP supervision, `Jason` for JSON).
- Store configuration in the database (use existing `sessions.mcps` map); do not add config files.
- Secrets come from ENV only; do not persist raw secrets in DB (store env var names/refs only).
- Use canonical session/thread addressing defined in `docs/overhauls/2025-09-09-session-centric-architecture-overhaul.md`.
- Persist provider-agnostic API logs in DB with per-provider translators on read/export.
- No new CLI UX for now; prefer DB + existing UI/config flows.
 - Canonical API events are embedded within chat_history (under `combined_chat["events"]` or a sibling `events`), enabling cross-provider continuity; switching providers/agents in the same chat can reuse past MCP call info.
 - STDIO launchers are flexible per-target (store `cmd` and `args` in `sessions.mcps`), with sane defaults pointing to launchers under `source/*`.
 - Cross-session permissions default to allow-all for now (single-user dev tool), pinned to sessions; a stricter allow-list arrives later without breaking the shape.
 - Observability is DB-only in this phase; no external metrics/traces sink.

## In-Scope

- MCP Client implementation to talk to external servers used by:
  - Codex: `source/codex`
  - Gemini CLI: `source/gemini-cli`
  - Claude Code interactions: `source/llxprt-code`
- MCP Server façade to expose our agent sessions as MCP-compliant tools/endpoints (session-as-MCP).
- Transport adapters for `STDIO`, `SSE`, and `HTTP` with a single, unified client interface.
- Sessions and routing: create/select sessions; allow an agent session to call another via MCP.
- DB-backed configuration in `sessions.mcps`; secrets from ENV; validations and redaction.
- Logging, tracing, and strict error handling to meet stricter clients’ expectations.
- Provider-agnostic API logging persisted in DB with translators for Codex, Gemini, Claude Code, and OpenAI.

## Out-of-Scope (for this overhaul)

- New model/provider support beyond the listed targets (unless required for MCP compatibility).
- UI/UX redesign outside of minimal controls needed to configure MCP.
- Long-term key management store or vault migration (we’ll integrate with what exists today; see Open Questions).
 - New CLI/subcommands; any CLI will follow after DB+UI flows are stable.

## Goals and Non-Goals

- Goals
  - Unify LLM (non-MCP) and MCP interactions under a single orchestration layer.
  - Make transport choice a runtime concern, not an architectural fork.
  - Allow session-to-session collaboration through MCP without circular deadlocks.
  - Keep default path backwards compatible (existing OpenAI calls keep working by default).
- Non-Goals
  - Changing repository defaults (branch remains `dev`).
  - Bypassing git hooks or relaxing CI gates (forbidden).

## Architecture Overview

- Terminology
  - MCP Client: Our side initiating a connection to an MCP server (Codex/Gemini/Claude Code/Archon/etc.).
  - MCP Server: Our façade that exposes tools/capabilities of our agent sessions to other MCP clients.
  - Transport Adapters: Concrete connectors for STDIO, SSE, HTTP bound behind a single interface.

- High-Level Components
  - `MCP Client Core`
    - Protocol handshake, capabilities, request/response, tool invocation, streaming events.
    - Transport-agnostic API; transport added via adapter injection.
    - Strict mode validation for schema conformance and error propagation expected by Claude Code/Gemini.
  - `Transport Adapters`
    - `STDIO`: spawn child processes; bind stdin/stdout; lifecycle supervision; backpressure.
    - `SSE`: HTTP connection with `text/event-stream` handling; reconnect policy; heartbeats.
    - `HTTP`: JSON over HTTP; retry/backoff; idempotency keys where applicable.
  - `Session Bridge (Server)`
    - Wrap an existing agent session as an MCP Server exposing: tools (search/tests/code-advice), resources, prompts.
    - Session discovery and addressing (name/ID), permissions, and isolation.
  - `LLM Router`
    - Unified orchestration choosing between legacy OpenAI API calls vs. MCP tool routes.
    - Policy-driven selection and fallbacks (e.g., if MCP server unavailable, optional degrade to direct API if safe).
  - `Config + Secrets`
    - DB-first via `sessions.mcps`; secrets injected from ENV; redaction in logs.
  - `Observability`
    - Structured logs, correlation IDs, request/response traces, MCP traffic sampling, metrics.

### Elixir Implementation Notes

- HTTP/SSE via `Req` (project standard). Implement SSE parsing with a lightweight module if needed and drive it with Req streaming responses.
- STDIO via OTP `Port` processes for stdin/stdout; apply bounded buffers/backpressure and graceful shutdown.
- JSON with `Jason`; strict schema validation for MCP payloads in strict mode.
- Supervise each transport under a dedicated supervisor tree with exponential backoff and jitter.

## Data Model & Storage

- Configuration
  - Store per-session MCP configuration in `sessions.mcps` (map). Example shape:
    - `%{"targets" => [ %{ "id" => "codex", "transport" => "stdio", "cmd" => "...", "args" => ["..."], "env_keys" => ["CODEX_API_KEY"] }, ... ]}`
  - Persist only non-sensitive fields in DB. For secrets, persist ENV variable names and resolve actual values at runtime.
- Logging (provider-agnostic)
  - Capture canonical API events alongside chat snapshots (embed under `combined_chat["events"]`; fallback to sibling `events` only if needed). Store request, response, streaming chunks, errors, and usage.
  - Provide translators to map canonical events to provider-specific formats for UI/debug exports without altering stored data.
- Sessions
  - Reuse session/thread addressing from the Session-Centric overhaul (thread_id, lineage) for MCP traceability and cross-session calls.
- MCP Registry
  - Use the existing MCP-ish table/context in the DB as the registry of installed/configured MCP connectors (name TBD). The `sessions.mcps` map references registry entries by id/name and may override specific fields (e.g., transport, cmd/args) per session when needed.

## MCP Context (Phoenix Generators)

Introduce a dedicated `TheMaestro.MCP` context and schemas generated via Phoenix, then refactor existing code to use this context uniformly. There is no existing registry; we will create new tables and migrate any session-level `mcps` data.

- Schemas
  - `MCP.Connector` (table: `mcp_connectors`)
    - name:string (unique), kind:string ("client"|"server"), transport:string ("stdio"|"sse"|"http"), base_url:string (nullable), cmd:text (nullable), args:map (default `%{}`), env_keys: array(string), options:map (default `%{}`), strict:boolean (default true), enabled:boolean (default true)
  - `MCP.SessionBinding` (table: `mcp_session_bindings`)
    - session_id: references(:sessions, type: :binary_id), connector_id: references(:mcp_connectors), label:string, transport_override:string, endpoint_override:string, cmd_override:text, args_override:map, env_keys_override: array(string), options_override:map, priority:integer (default 0)

- Generator commands (to be run during implementation; shown here for planning)
  - `mix phx.gen.context MCP Connector mcp_connectors name:string:unique kind:string transport:string base_url:string cmd:text args:map env_keys:array:string options:map strict:boolean enabled:boolean`
  - `mix phx.gen.context MCP SessionBinding mcp_session_bindings session_id:references:sessions connector_id:references:mcp_connectors label:string transport_override:string endpoint_override:string cmd_override:text args_override:map env_keys_override:array:string options_override:map priority:integer`
  - LiveView management pages (separate MCP Connections page)
    - `mix phx.gen.live MCP Connector connectors mcp_connectors name kind transport base_url cmd args env_keys options strict enabled`
    - `mix phx.gen.live MCP SessionBinding session_bindings mcp_session_bindings session_id connector_id label transport_override endpoint_override cmd_override args_override env_keys_override options_override priority`

- Integration
  - Session Config modal: load connectors via `MCP.list_connectors/0` for a dropdown; apply per-session overrides via `MCP.SessionBinding`.
  - Transitional resolver: `MCP.ConfigResolver` merges connector defaults + binding overrides and resolves secrets from ENV; falls back to `sessions.mcps` until migration completes.

- Indices & constraints (to include in migrations)
  - `mcp_connectors(name)` unique
  - `mcp_session_bindings(session_id, connector_id, label)` unique (optional label uniqueness per session/connector)
  - Foreign keys with `on_delete: :delete_all` from connectors -> session_bindings and sessions -> session_bindings

- Data migration (from legacy `sessions.mcps`)
  - Script reads each Session’s `mcps` map and creates matching `MCP.Connector` rows (de-duped by name) and `MCP.SessionBinding` rows.
  - Preserve transport, cmd/args, env_keys, and options; default `kind` based on usage (client/server) when inferable; otherwise default to `client`.
  - After backfill, set a feature flag to switch resolution to MCP context; keep a fallback to `sessions.mcps` only during rollout.

## Transports: Requirements

- STDIO
  - Spawn strategy; command and args from config; working directory; env injection for API keys.
  - Non-blocking IO; bounded buffers; graceful shutdown; orphan cleanup.
  - Healthcheck on start (handshake success within T seconds) and liveness pings.

- SSE
  - Connect with headers (auth) and query params; handle reconnects with `Last-Event-ID` when supported.
  - Parse events, chunked frames; backpressure; heartbeat timeouts; exponential backoff.

- HTTP
  - JSON request/response; status mapping; structured errors; retries for safe operations only.

## Session-as-MCP

- Expose each agent session as an MCP Server namespace:
  - Tools: `code.advice`, `search.web`, `tests.generate`, `refactor.apply`, etc.
  - Sessions can call other sessions via MCP Client Core, enabling cross-session collaboration.
  - Prevent cycles via hop counters and request IDs; detect and reject re-entrancy loops.
  - Authorization policy: which sessions can call which tools/targets.
  - Addressing: include `session_id` and `thread_id` metadata per request for auditing and traceability.

## Configuration & Secrets

- Surfaces
  - DB (primary):
    - `sessions.mcps` map holds per-session targets, transports, command/args, and ENV key references.
    - MCP Registry (new `mcp_connectors` table via `TheMaestro.MCP` context) holds reusable connector definitions; sessions reference these by id/name.
  - ENV (secrets): resolve credentials from ENV at runtime; persist only ENV var names in DB.
- Redaction and logging guards for anything matching `*_KEY`, `*_TOKEN`, `*_SECRET`, `authorization`.

## Compatibility With Existing OpenAI API Calls

- Keep current OpenAI path as default. MCP-enabled behavior activates only when configured.
- Provide capability routing so a single high-level action can be satisfied by either:
  - Direct LLM call (OpenAI), or
  - MCP tool call to external server (Codex/Gemini/Claude Code) or a local session-as-MCP.
- Report clear provenance in logs: `route=openai|mcp:stdio|mcp:sse|mcp:http`.

## Observability & Logging (DB)

- Persist provider-agnostic API events for every MCP and direct-LLM interaction (request/response/stream).
- Translate events for UI export per provider (Codex/Gemini/Claude/OpenAI) without altering stored canonical data.
- Include correlation IDs, `session_id`, `thread_id`, and transport kind; redact secrets by rule.
- Provide query helpers for per-session and cross-session traces and end-to-end correlation.
 - No external telemetry/metrics sink required in this phase.

## Repository Touchpoints (for implementation planning)

- External interaction code to review:
  - Codex: `source/codex`
  - Gemini CLI: `source/gemini-cli`
  - Claude Code: `source/llxprt-code`
- Orchestration/core that decides between LLM vs MCP (identify current router/agent orchestrator modules).
- Config loading and key management modules; leverage `TheMaestro.Conversations.Session` (`mcps` map), new `TheMaestro.MCP` context, and `TheMaestro.SavedAuthentication`.

## Research (Archon MCP Server) — Required Before Coding

- Strategic patterns
  - `archon:perform_rag_query(query="MCP client/server best practices patterns", match_count=3)`
  - `archon:perform_rag_query(query="MCP transports STDIO SSE HTTP reliability patterns", match_count=3)`
- Implementation examples
  - `archon:search_code_examples(query="MCP STDIO client examples", match_count=3)`
  - `archon:search_code_examples(query="MCP SSE event-stream examples", match_count=3)`
  - `archon:search_code_examples(query="MCP server exposing tools examples", match_count=3)`
- Provider specifics
  - `archon:search_code_examples(query="Codex MCP integration examples", match_count=2)`
  - `archon:search_code_examples(query="Gemini CLI MCP examples", match_count=2)`
  - `archon:search_code_examples(query="Claude Code MCP strict mode examples", match_count=2)`

## Task Checklist

- [x] Create this overhaul story in `docs/overhauls/`.
- [ ] Confirm scope, assumptions, and open questions with stakeholders (updated per clarifications in this doc).
- [ ] Inventory existing code paths for Codex, Gemini CLI, Claude Code under `source/*`.
- [ ] Define MCP Client Core interface (requests, tools, resources, streaming callbacks) in Elixir.
  - [ ] Map error taxonomy (validation, transport, protocol) and strict-mode behavior.
  - [ ] Correlation IDs, tracing hooks, and redaction utilities.
- [ ] Implement Transport Adapters behind one interface (Elixir/OTP).
  - [ ] STDIO adapter: Port-based spawn, supervise, backpressure, handshake, shutdown.
  - [ ] SSE adapter: Req streaming connect, parse events, reconnect strategy, heartbeats.
  - [ ] HTTP adapter: Req request/response, retries, structured errors.
- [ ] Add Session Bridge (MCP Server façade) to expose agent sessions.
  - [ ] Tool registry for session capabilities; permission mapping.
  - [ ] Loop prevention and hop counters.
  - [ ] Health, discovery, and session selection by name/ID.
- [ ] DB-backed configuration
  - [ ] Define canonical schema for `sessions.mcps` map (targets, transports, env key refs, args/options).
  - [ ] CRUD via existing contexts; validations for allowed transports and required fields.
  - [ ] Secrets policy: store env var names only; resolve at runtime from ENV.
  - [ ] Default timeouts, retry policies, and transport selection rules.
 - [ ] MCP Context/Registry (new)
   - [ ] Generate `TheMaestro.MCP` context with `Connector` and `SessionBinding` schemas and migrations.
   - [ ] Build an “MCP Connections” management page (CRUD) to add/configure connectors.
   - [ ] Session Config modal: add dropdown to select installed connectors; support per-session overrides.
- [ ] Orchestration integration: route actions to OpenAI vs MCP.
  - [ ] Compatibility switch; keep OpenAI default path stable.
  - [ ] Provenance metadata in logs and outputs.
- [ ] Observability
  - [ ] Structured logs (JSON), levels, fields; performance metrics.
  - [ ] Request/response sampling; event stream diagnostics.
  - [ ] Provider-agnostic canonical API event logging in DB with translators per provider.
- [ ] E2E validation against providers
  - [ ] Codex MCP flows (from `source/codex`).
  - [ ] Gemini CLI MCP flows (from `source/gemini-cli`).
  - [ ] Claude Code MCP flows (from `source/llxprt-code`).
- [ ] Documentation & examples
  - [ ] Quickstarts per transport.
  - [ ] Session-as-MCP cookbook (agent calls agent).
  - [ ] Troubleshooting guide.
- [ ] CI & hooks: add/extend tests; never bypass pre-commit/CI hooks.

### Generators & Refactor (New)

- [ ] Generate MCP context and schemas
  - [ ] `phx.gen.context` for `MCP.Connector` and `MCP.SessionBinding` (tables `mcp_connectors`, `mcp_session_bindings`).
  - [ ] If an MCP-ish table exists, align schema to it or plan data migration.
- [ ] Generate LiveView CRUD for MCP Connections and (optional) Session Bindings admin.
- [ ] Implement `MCP.ConfigResolver` and update call sites to use it for all MCP interactions.
- [ ] Replace direct `sessions.mcps` reads with MCP context calls, keeping a fallback shim during cutover.
- [ ] Update Session Config modal to use dropdown of connectors; support per-session overrides.
- [ ] Remove/deprecate legacy paths once parity confirmed.

## Acceptance Criteria

- [ ] MCP Client Core supports request/response and streaming with strict schema validation.
- [ ] Three transports available and switchable at runtime: STDIO, SSE, HTTP.
- [ ] Session-as-MCP: one agent session successfully calls another to request code advice and to generate tests.
- [ ] Works with existing OpenAI API flows; default behavior remains unchanged when MCP is not configured.
- [ ] DB-backed configuration under `sessions.mcps` with secrets from ENV; no raw secrets stored.
- [ ] Observability: provider-agnostic API logs persisted in DB with translators for Codex/Gemini/Claude/OpenAI.
 - [ ] Provider/agent switching within the same chat can reuse past MCP call information due to canonical embedded events; continuity verified.
 - [ ] UI: Session Config modal presents dropdown of installed MCP connectors; separate “MCP Connections” page supports add/edit/remove and advanced configuration.
 - [ ] MCP context (`TheMaestro.MCP`) with `Connector` and `SessionBinding` schemas is used by all MCP client/server code paths.
 - [ ] Legacy `sessions.mcps` access is removed or gated behind a compatibility shim; tests cover both paths during migration.
- [ ] Verified E2E against Codex, Gemini CLI, and Claude Code integrations in `source/*`.
- [ ] All new configuration options documented; secrets redacted in logs by default.
- [ ] Observability: correlation IDs, structured logs, and minimal metrics present.
- [ ] All tests and linters pass; no git hook bypass used.

## Dev Notes

- Branching & Hooks
  - Default branch is `dev`, not `main`.
  - Do not bypass git hooks (no `--no-verify`, no force pushes). Fix hook failures.
  - For manual testing, run long-lived background processes without arbitrary 10s timeouts; kill when done.

- Transport Implementation Notes
  - STDIO: implement with OTP `Port`; bounded buffers to avoid deadlocks; graceful shutdown signals.
  - SSE: `Req`-driven streaming + robust parser; reconnect with jittered backoff, heartbeats, idle timeouts.
  - HTTP: use `Req`; respect idempotency and provider rate limits; structured error mapping.

- Config & Secrets
  - DB-backed config (`sessions.mcps`); secrets from ENV only. Redact any field named `key`, `token`, `secret`, `password`, or `authorization`.
  - Consider pluggable secret resolvers later (OS keychain, cloud secrets manager).

- Observability
  - Emit correlation IDs per request; propagate across transports and sessions.
  - Sampling for verbose MCP traffic to keep logs manageable.
  - Persist canonical API events in DB; translate on export per provider.

- Provider Strictness
  - Claude Code and Gemini clients may enforce tighter schemas and error codes; keep strict-mode on by default when those clients are detected.

- Language/Lib Notes
  - Elixir-only. Use `Req` for HTTP/SSE; avoid `:httpoison`/`:tesla`.

## Test Plan (High-Level)

- Unit tests for MCP Client Core request shaping, validation, and error mapping.
- Transport adapter tests (mock servers/processes) for STDIO, SSE, HTTP.
- Integration tests against local MCP mock server and session-as-MCP façade.
- E2E smoke tests with Codex, Gemini CLI, and Claude Code directories.
- Reliability tests: reconnects, backpressure, cancellation, and timeouts.
 - Persistence tests: DB-backed config resolution from `sessions.mcps` and ENV; canonical event logging and translation round-trips.

## Risks & Mitigations

- Transport instability (SSE reconnect storms) — jittered backoff, heartbeats, caps.
- Deadlocks with STDIO — bounded buffers, async IO, supervised lifecycles.
- Session recursion/loops — hop counters, request IDs, and deny self-calls.
- Secret leakage in logs — aggressive redaction and field-based filters.
- Provider divergence in schemas — strict-mode validators and adapter shims per provider.
 - Canonical event schema drift vs. provider translators — mitigate with versioned translators and regression tests.

## Files Touched/Created

- [x] `docs/overhauls/mcp-protocol-integration-overhaul-story.md` (this document)
 - [ ] (Planned) Implementation stories will enumerate code files to be modified; this story is documentation-only.

## Open Questions

None at this time. Assumptions are captured and locked above (Elixir-only, new MCP context/registry via generators, ENV-only secrets, embedded canonical events, UI plan). If any of these change, we will revise the story and tasks.

---

With this version, the next iteration will be to spin out implementation issues per directory (codex, gemini-cli, llxprt-code, orchestration, UI) aligned to the Generators & Refactor checklist.

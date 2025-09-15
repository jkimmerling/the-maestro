# Overhaul Story: MCP Protocol Integration via Hermes MCP

This document supersedes the hand-rolled MCP core plan by adopting the Hermes MCP library as our protocol engine. It preserves our product goals (Session-as-MCP, Team MCP Server, DB-backed config, LiveView UI, and observability) while replacing the lowest‑level protocol/transport code with a maintained, spec-aligned Elixir implementation.

References:
- Hermes MCP (GitHub): https://github.com/cloudwalk/hermes-mcp
- Hermes MCP (HexDocs): https://hexdocs.pm/hermes_mcp/home.html

## Summary

- Adopt Hermes MCP for both MCP Client and MCP Server roles.
- Prefer Streamable HTTP transport for server/client; support STDIO where appropriate; keep plain HTTP for non-streaming calls. SSE is legacy; only add if a client hard‑requires it.
- Implement “Session-as-MCP” and “Team MCP Server” on top of Hermes servers, routing to internal agent sessions with role/priority policies, hop limits, and cancellation.
- Keep existing OpenAI API flows intact; add capability routing to choose direct LLM vs MCP tool.
- Provide DB-backed configuration for MCP connectors and secrets stored in Postgres via the UI (no :ets); add LiveView UI for Servers, Members, Routing, and Diagnostics.
- Persist provider-agnostic MCP events in DB; redact secrets; expose a trace UI and JSON downloads.

## Rationale (Why Hermes)

- Maintained protocol compliance and upgrades (e.g., Streamable HTTP adoption) without re-implementing JSON-RPC framing, capability negotiation, progress/cancel, etc.
- Elixir-native, OTP-friendly design aligns with our stack and reduces risk in transports (Streamable HTTP, STDIO) and state management.
- Lets us focus on product value: UX, DB config, routing, workspace confinement, and provider‑agnostic observability.

## Decisions & Constraints (Locked-In)

- Use Hermes MCP as the protocol engine for both client and server.
- Runtime is Elixir-only; use `Req` for HTTP clients; Phoenix 1.8 for server endpoints.
- Prefer Streamable HTTP; support STDIO; add SSE only if concretely needed.
- Configuration for EVERYTHING is persisted in Postgres via Ecto (no `:ets`).
- Secrets/API keys are entered via the UI and stored in Postgres (encrypted at rest, redacted in logs/UI). Do not rely on ENV for runtime secrets.
- Keep default behavior backwards compatible with existing OpenAI flows.
- Default branch is `dev`. Never bypass git hooks; fix issues and run checks locally.

## In-Scope

- Hermes-based MCP Server(s) that expose our agents’ tools and the Team MCP aggregator.
- Hermes-based MCP Client wrapper that reads DB config and selects transport.
- LiveView UI: Servers index/detail, Members, Routing, Access (API key), Diagnostics.
- Working directory semantics (cwd), path confinement via `PathResolver`.
- Observability: canonical DB events with redaction and downloadable traces.

## Out-of-Scope (for this iteration)

- Broader UI redesign beyond necessary pages.
- Vault/secret manager integrations beyond Postgres storage (future option).
- New model/provider support outside what’s required for MCP interop.

## Architecture Overview

### Components

- Hermes Server (ours): Implements tools/resources/prompts and hosts transports (Streamable HTTP via Phoenix Plug; optional STDIO launchers for local tools).
- Hermes Client (ours): A thin wrapper over `Hermes.Client` that selects transport by connector config, sets headers, manages progress/cancel callbacks, and maps events to our DB.
- Team MCP Server: A Hermes-based server that aggregates internal agent sessions and exposes curated `team.*` tools with routing.
- DB/Config: Ecto schemas for connectors and team servers; secrets persisted in Postgres with redaction.
- Observability: Canonical event storage; translators for provider-specific exports; LiveView diagnostics UI.

### Transports

- Streamable HTTP (Preferred):
  - Server: mount Hermes Streamable HTTP Plug under `/api/mcp/servers/:id/stream`.
  - Client: use `Hermes.Client` with Streamable HTTP transport when `base_url` present.
  - Supports progress, partials, and cancel with proper framing.

- STDIO:
  - Use for local processes/tools where appropriate. Hermes provides STDIO handling; we store `cmd`, `args`, `env_keys`, and working dir in DB and supervise via OTP.

- HTTP (non-stream):
  - For simple request/response flows or initialization calls when streaming isn’t required.

- SSE (Legacy):
  - Only add if a target client strictly needs it. Otherwise keep the code path disabled to reduce complexity.

### Session-as-MCP

- Expose each agent session as a Hermes Server namespace with tools like `code.advice`, `search.web`, `tests.generate`, etc.
- Include `cwd` or `workspace_uri` in tool params; resolve and confine via `PathResolver`.
- Prevent cycles with hop counters and request IDs; deny self-calls; enforce strong cancellation semantics.

### Team MCP Server (Aggregator)

- Curated tool surface:
  - `team.generate_code(spec, path_globs?, test_expectations?, cwd?, options?)`
  - `team.run_tests(paths?, framework?, cwd?, options?)`
  - `team.search_web(query, depth?, cwd?)`
  - `team.plan_task(goal, constraints?, cwd?)`

- Optional power-user dispatch (off by default) with allowlist:
  - `team.dispatch(target_session?, target_role?, tool, params, cwd?, policy_override?)`

- Routing & execution:
  - Role-first then priority; tie-break by recent health/latency.
  - Prefer/Fallback rules per tool from DB (simple map).
  - Server-level concurrency with optional member overrides; FIFO queue when saturated.
  - Cancellation propagates to downstream work; no partial persistence.
  - Hop limit default 3; reject at limit and log provenance.

## Working Directory Semantics & Confinement

- Effective cwd is taken from tool params or server default; path ops go through `PathResolver`.
- Deny access outside workspace; log violations.
- Stream and persist results only after commit points; cancel reverts to last committed state.

## Server Endpoints (Phoenix)

- Streamable HTTP: `POST /api/mcp/servers/:id/stream` (Hermes Plug mounts here; exact verb/path may vary per Plug expectations).
- Optional non-stream RPC: `POST /api/mcp/servers/:id/rpc` for JSON-RPC objects.
- Inbound API key (optional): default header `Authorization: Bearer <token>`; configurable header name (e.g., `x-api-key`). API key value is stored in Postgres and redacted in UI/logs.

## LiveView UI

- Servers Index: Name, Kind, Transport, Enabled, Tool Count, Last Handshake, Health; actions: New/Edit/Enable/Disable/Test/Download Logs.
- Server Detail (Team):
  - Overview: name, enabled, transport, hop_limit, max_concurrency, default working_dir.
  - Members: list/add/remove sessions; role, priority, enabled, health.
  - Tools: show `team.*` catalog; toggle `team.dispatch`; edit allowlist.
  - Routing: Prefer/Fallback per tool.
  - Access: API key header name and stored key value (redacted).
  - Diagnostics: last handshake and error; rolling latencies; JSON trace download.

## Configuration & Secrets

- Ecto schemas (created and maintained via Phoenix generators only):
  - `MCP.Connector`: reusable client connector defs (transport, urls, headers, stdio cmd/args, env vars, options).
  - `MCP.Server`: Team server records (transport, working_dir, hop_limit, concurrency, routing_rules, access config including API key value, status map).
  - `MCP.TeamMember`: server→session membership with role/priority and overrides.

- Secrets policy (project-wide):
  - All API keys/tokens are entered via the UI and stored in Postgres (encrypted at rest) — no ENV indirection for runtime and no `:ets`.
  - Secrets are always redacted in logs and previews; after save, the UI never shows full values (use “Copy once” patterns when needed).
  - Rotation timestamps recorded to support safe cutovers.

## Compatibility With Existing OpenAI API Calls

- Keep current non-MCP calls as the default path.
- Capability router can choose:
  - Direct LLM (OpenAI), or
  - MCP tool call via Hermes Client to external servers or to our own Session/Team server.
- All interactions log provider-agnostic events with a `route=` dimension (e.g., `openai`, `mcp:stdio`, `mcp:stream`, `mcp:http`).

## Observability & Logging (DB)

- Persist canonical events for requests/responses/streams with correlation IDs, `session_id`, `thread_id`, and transport kind.
- Redact tokens and sensitive headers by rule.
- UI trace panel (toggle) and JSON downloads from Diagnostics.
- Translators for provider-specific exports (Codex, Gemini, Claude, OpenAI) without altering canonical data.

## Phased Implementation Plan

### Phase 0: Dependency + Smoke Tests
- Add `:hermes_mcp` to `mix.exs` and compile.
- Create a tiny Hermes server exposing a dummy tool; mount Streamable HTTP Plug.
- Use Hermes client to call it locally; verify progress/cancel and logs.

### Phase 1: Session-as-MCP (POC)
- `TheMaestro.MCP.SessionServer` using `use Hermes.Server`; expose 1–2 session-backed tools.
- Respect `cwd` param; enforce workspace confinement.
- Build “Test Connection” action in Diagnostics (initialize + tools/list + simple tool call).

### Phase 2: Client Wrapper + DB Connectors
- `TheMaestro.MCP.Client` wraps `Hermes.Client` and selects transport from `MCP.Connector` (Streamable HTTP, HTTP, STDIO).
- Map progress/cancel/log events into our DB; add redaction.
- Add LiveView to create/edit connectors (DB-stored secrets; redacted previews).

### Phase 3: Team MCP Server
- Implement `TheMaestro.MCP.TeamServer` (Hermes server) with `team.*` tools.
- Implement routing (role/priority + Prefer/Fallback); concurrency control; hop limits; cancellation.
- Members UI: add existing sessions, set roles/priority, enable/disable, view health.

### Phase 4: Observability + Exporters
- Canonical event queries and trace UI in chat and Diagnostics.
- JSON download; provider-specific translators; sampling for verbose traffic.

### Phase 5: SSE (Only If Needed)
- Add SSE transport paths if we identify a strict client that lacks Streamable HTTP; otherwise skip.

## Test Plan (High-Level)

- Unit tests: client request shaping, error mapping, redaction, and transport selection.
- Server tests: Streamable HTTP init/tools list/tool call; header auth; cwd confinement.
- Integration: Session-as-MCP façade round trips; cancel propagation; queueing under load.
- Team routing: role/priority + Prefer/Fallback; hop-limit enforcement; health-based tie-breaks.
- Observability: DB event persistence; redaction; export translators.

## Risks & Mitigations

- Transport compatibility: Prefer Streamable HTTP; verify target clients. Add SSE only if unavoidable.
- STDIO deadlocks: bounded buffers and supervised ports via Hermes + OTP.
- Looping/recursion: hop counters, request IDs, deny self-calls.
- Secret leakage: strict redaction and field-based filters; never store raw tokens.
- Spec evolution: rely on Hermes releases and changelogs; keep our layer thin.

## Files Touched/Created (Planned)

- `mix.exs` (dependency): add `:hermes_mcp`.
- Server: `lib/the_maestro/mcp/server/session_server.ex`, `lib/the_maestro/mcp/server/team_server.ex`.
- Client: `lib/the_maestro/mcp/client.ex`.
- Config/DB: `lib/the_maestro/mcp/*.ex` (context), migrations for `mcp_connectors`, `mcp_servers`, `mcp_team_members`.
- Endpoint: mount Hermes Streamable HTTP Plug under `/api/mcp/servers/:id/stream`.
- UI: LiveViews for Servers index/detail and Connectors.
- Observability: event persistence adapters; translators; UI trace views.

## Dev Notes

- Branching & Hooks: default branch is `dev`; do not bypass git hooks or force pushes. Fix and re-run checks locally.
- Phoenix v1.8: build server endpoints in Phoenix only; use `Req` for HTTP/streaming per project standards.
- Elixir guidelines: follow list access, form handling, and HEEx rules from our project guide.

## Open Questions

- Do any current target clients require SSE instead of Streamable HTTP? If yes, which ones, and can we gate that path behind a feature flag?
- Should we add a lightweight health probe endpoint for Team servers that surfaces tool count and last handshake timestamp for the UI table?
- Do we need WebSocket client transport for any external MCP servers in the near term, or is Streamable HTTP + HTTP sufficient?

---

With Hermes as our protocol foundation, the remaining work is app-specific: DB-driven configuration, LiveView UX, the Team routing layer, and observability. This plan reduces risk, accelerates delivery, and keeps us aligned with the evolving MCP spec.

## UI/UX Plan (Clean, Spacious, Hermes‑First)

This UI plan replaces cramped/griddy forms with spaced, guided flows. It focuses on making it trivial to add STDIO commands/args and to create our own MCP servers, while keeping advanced JSON fields accessible but unobtrusive.

### 1) MCP Hub (Landing)

- Three wide cards with generous spacing and readable copy:
  - Connectors — outbound MCP clients to external servers (count, last tested).
  - Session Bindings — attach connectors to sessions with overrides.
  - Servers — our Team MCP façade (Streamable HTTP/STDIO/HTTP) and any custom servers.
- Primary actions per card: “Manage Connectors”, “Manage Bindings”, “Manage Servers”.
- Subtext line can show helpful tips (e.g., “Use the Connectors page to add a preset quickly”).

### 2) Connectors (Outbound Clients) — Cleaner Forms

Goal: make it easy to point to external MCP servers and test quickly.

Form layout (stepper or tabbed sections; each section fits comfortably on screen):

1. Basic
   - Name (required)
   - Description
   - Kind: client | server (default client)
   - Enabled (toggle)

2. Transport
   - Transport: stream (Streamable HTTP, preferred) | stdio | http | sse (legacy)

   Streamable HTTP / HTTP fields
   - Base URL (e.g., https://mcp.example.com)
   - Endpoint Path (default /mcp or /api/mcp)
   - Headers (Key–Value Editor)
     - Add row → key, value; secret values are stored in DB and redacted after save (no ENV indirection)
   - Preview (read-only) of headers with secrets redacted

   STDIO fields (for local client binaries)
   - Executable (Cmd) — file picker + text
   - Arguments Builder (Chips)
     - “Add Argument” → adds a chip; chips are reorderable and editable
     - Helper buttons insert tokens: {cwd}, {session_id}, {thread_id}
   - Env Vars (Key–Value Editor)
     - Enter literal values; they are stored in DB and redacted after save (no ENV indirection)
   - Working Dir (optional; directory picker)
   - Command Preview (read-only) shows exactly what will execute

3. Advanced
   - Options (Key–Value Editor) — structured client options (timeouts, debug)
   - Notes (free text)

Actions
- Save / Cancel (sticky footer)
- Test Connection (Initialize → Tools/List, optional tool call)
- Show JSON (collapsible) of the effective connector config for copy/paste

Empty-States & Validation
- If Transport=stream/http and Base URL empty → inline error
- If Transport=stdio and Cmd empty → inline error
- If Headers or Env Vars contain suspected secrets as literals → allow and warn that values are stored in DB and redacted after save; provide a “Copy once” affordance

### 3) Servers (Team MCP + Custom) — Easy Command/Args and Our Own Servers

Goal: create first‑class Team MCP servers and custom servers with minimal friction. Emphasis on STDIO Cmd/Args editor and clean Streamable HTTP setup.

Form layout (five compact sections):

1. Basic
   - Name (required)
   - Kind: team (default)
   - Enabled (toggle)
   - Description

2. Transport
   - Transport: stream (preferred) | stdio | http | sse (legacy)

   Streamable HTTP / HTTP
   - Base URL (for external hosting) or “Host here” toggle
   - If “Host here” checked: instructions display the mounted Hermes Plug path, e.g., /api/mcp/servers/:id/stream
   - Headers (Key–Value Editor). Secret values stored in DB and redacted after save.
   - API Key Protection (optional)
     - Header Name (default authorization)
     - API Key Value (stored in DB; preview shows “Authorization: Bearer ****”)

   STDIO (build our own local server process)
   - Executable (Cmd) — file picker + text
   - Arguments Builder (Chips)
     - Add/reorder chips; helpers to insert tokens: {cwd}, {server_id}, {hop_limit}
   - Env Vars (Key–Value Editor). Values stored in DB and redacted after save.
   - Working Dir (directory picker)
   - Command Preview — exact argv list with redaction

3. Routing & Members (Team Server)
   - Routing Strategy: by_role_priority (default)
   - Prefer/Fallback rules per tool — compact Key→Value editor
   - Members Table
     - Add Existing Session → select session, set role (code/test/search/planner), priority, enable
     - Drag to reorder priorities; health indicator (last latency, failures)

4. Security & Paths
   - Hop Limit (default 3)
   - Enable Path Policy (toggle)
   - Allowed Roots (chips for directories)
   - Denied Paths (chips; supports glob)

5. Diagnostics
   - Test Connection (Initialize + Tools/List + sample call)
   - Trace: rolling latencies, last error; “Download JSON” button

Actions
- Save / Cancel (sticky)
- Test Connection (always visible on edit page)

Empty-States & Validation
- Transport field must be set; show contextual help describing Streamable HTTP vs STDIO
- If “Host here” selected without mounting path available → present clear instruction text (no save block)
- For secret fields, UI confirms storage in DB with redaction; never re-displays full values post‑save

### 4) UX Conventions (Consistent, Not Cramped)

- Generous line-height and 8–12px vertical rhythm between controls
- Two‑column grid only on desktop; single column on narrow screens
- Sticky action bar for Save/Test; never hide primary actions
- Key–Value Editors: append row at bottom; keyboard Enter adds a row; Tab navigates cells
- JSON Advanced toggles collapse to keep the main form tidy
- Tooltips for special tokens like {cwd} explain runtime substitution

### 5) Example Presets (Quick Start)

- “Use Context7 Preset” (stream)
  - Base URL: https://mcp.context7.com
  - Endpoint Path: /mcp
  - Header: X-Api-Key → <paste your key> (stored securely; redacted after save)

- “Local Hermes STDIO Server”
  - Cmd: ./bin/my_hermes_server
  - Args (chips): --port, 0, --log, info
  - Env Vars: HERMES_LOG_LEVEL → info
  - Working Dir: project root

### 6) Acceptance Criteria (UI)

- Connectors: can create/edit/delete; can switch transport; can test and view structured result
- Servers: can create/edit/delete; can configure Streamable HTTP hosting vs external; can configure STDIO Cmd/Args with preview
- Security: Secret values entered in the UI are stored in Postgres (encrypted), never shown in full after save, and always redacted in logs and previews. No ENV or `:ets` usage for runtime config.
- Path Policy: allowed/denied inputs render as easy chips; validation on save
- Diagnostics: Test Connection returns initialize + tools/list payloads; sample tool call works with optional cwd

### 7) Notes on Spec Alignment

- Default to Streamable HTTP for hosted servers; expose SSE only if a known client requires it
- Keep “args” as an ordered list (UI chips) but persist as a map/array based on underlying schema; preview always reflects the runtime argv order
- Support token substitutions ({cwd}, {session_id}, {server_id}) at runtime and display a help popover describing each token

### 8) ASCII Wireframes (Layout Sketches)

The wireframes are indicative of grouping/spacing and primary affordances; exact styling follows our Tailwind theme.

#### A) MCP Hub

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ MCP Hub                                                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────┐   ┌────────────────┐   ┌───────────────┐                 │
│  │ Connectors     │   │ Session Bindings │ │ Servers        │                 │
│  │ Outbound MCP   │   │ Attach to sessions│ │ Team MCP + custom│                │
│  │ clients. Count:3│  │ Count:0           │ │ Count:0         │                │
│  │ [Manage]       │   │ [Manage]          │ │ [Manage]        │                │
│  └───────────────┘   └────────────────┘   └───────────────┘                 │
│                                                                              │
│  Tip: Use Connectors for presets; Diagnostics lives under Servers.           │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### B) Connectors – Create/Edit

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ New Connector                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│  Stepper: [1 Basic]──[2 Transport]──[3 Advanced]                             │
│                                                                              │
│  [Basic]                                                                     │
│  Name: [                ]   Description: [                ]                   │
│  Kind: (client|server)    Enabled: [✓]                                        │
│                                                                              │
│  [Transport]                                                                │
│  Transport: (stream | stdio | http | sse)                                    │
│                                                                              │
│  When stream/http selected:                                                  │
│  Base URL:        [ https://...            ]                                 │
│  Endpoint Path:   [ /mcp ]                                                    │
│  Headers (Key–Value Editor)                                                  │
│  ┌ key ──────────────┬ value (stored, redacted after save) ────────────────┐ │
│  │ X-Api-Key          │ •••••••••••••••••••••••••••••••••••••••••••••      │ │
│  │ Authorization      │ Bearer ••••••••••••••••••••••••••••••••••••••      │ │
│  └────────────────────┴────────────────────────────────────────────────────┘ │
│  [Preview headers: redacted]                                                 │
│                                                                              │
│  When stdio selected:                                                        │
│  Executable (Cmd): [ ./bin/my_client ]   Working Dir: [ ./ ] [Pick…]         │
│  Arguments (chips):  [--flag] [value] [--mode] [fast] [+ Add]                │
│  Env Vars (Key–Value Editor, stored/redacted)                                │
│  ┌ NAME ─────────────┬ VALUE (stored, redacted after save) ────────────────┐ │
│  │ HERMES_LOG_LEVEL   │ info                                               │ │
│  └────────────────────┴────────────────────────────────────────────────────┘ │
│  [Command Preview: ./bin/my_client --flag value --mode fast]                 │
│                                                                              │
│  [Advanced]                                                                  │
│  Options (Key–Value): { rpc_timeout_ms: 12000, debug: true }                 │
│  Notes: [ free text … ]                                                      │
│                                                                              │
│  Sticky actions:    [Test Connection]  [Save]  [Cancel]                      │
│  Test panel (collapsible): shows initialize/tools-list + sample call result  │
└──────────────────────────────────────────────────────────────────────────────┘
```

Key–Value Editor behaviors
- Enter adds a row; Tab moves focus; values are stored in DB and redacted post‑save.
- “Copy once” on freshly entered secrets; later renders show bullets.

#### C) Servers – Create/Edit (Team + Custom)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ New Server (Team)                                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│ Stepper: [1 Basic]──[2 Transport]──[3 Routing & Members]──[4 Security]──[5 Diag] │
│                                                                              │
│ [Basic]                                                                      │
│ Name: [ Team Alpha ]  Kind: (team)  Enabled: [✓]  Description: [ … ]         │
│                                                                              │
│ [Transport]                                                                   │
│ Transport: (stream | stdio | http | sse)                                     │
│                                                                              │
│ If stream/http:                                                               │
│  Base URL: [ https://… ]  [ ] Host here → shows: /api/mcp/servers/:id/stream │
│  Headers (K/V, stored/redacted)                                              │
│  API Key Protection: Header Name [authorization]  Key Value [••••••••]       │
│                                                                              │
│ If stdio:                                                                     │
│  Executable: [ ./bin/team_server ]  Working Dir: [ ./ ] [Pick…]               │
│  Args (chips): [--port] [0] [--log] [info] [+ Add]                            │
│  Env Vars (K/V, stored/redacted)                                             │
│  Command Preview: ./bin/team_server --port 0 --log info                       │
│                                                                              │
│ [Routing & Members]                                                           │
│ Routing Strategy: by_role_priority                                            │
│ Prefer/Fallback (per tool):                                                   │
│  team.generate_code → Prefer: openai  Fallback: anthropic                     │
│  team.run_tests   → Prefer: gemini                                           │
│ Members:                                                                      │
│  ┌ Session ─────────────┬ Role ────┬ Priority ─┬ Enabled ─┬ Health ────────┐ │
│  │ Session A             │ code     │ 1         │   ✓      │ 85ms (green)  │ │
│  │ Session B             │ test     │ 2         │   ✓      │ 132ms (green) │ │
│  └───────────────────────┴──────────┴───────────┴──────────┴───────────────┘ │
│  [Add Existing Session]  (drag to reorder)                                    │
│                                                                              │
│ [Security & Paths]                                                            │
│ Hop Limit: [3]  [✓] Enable Path Policy                                       │
│ Allowed Roots (chips): [./] [+Add]                                           │
│ Denied Paths  (chips): [node_modules] [tmp/**] [+Add]                        │
│                                                                              │
│ [Diagnostics]                                                                 │
│  [Test Connection] → shows initialize + tools/list + sample call (cwd opt.)  │
│  [Download JSON trace]                                                        │
│                                                                              │
│ Sticky actions:    [Test Connection]  [Save]  [Cancel]                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

Chips Editor behaviors
- Each chip is a single argv token; Enter converts input to chip; drag to reorder.
- Helper menu inserts tokens: {cwd}, {server_id}, {hop_limit} with tooltip.

## Sessions as Teams — Guided Setup

This flow makes “sessions as teams” straightforward and discoverable. It’s opinionated, minimizes jargon, and keeps advanced controls one click away.

### A. Create a Team MCP Server

1) Go to MCP Hub → Manage Servers → New.
2) Basic
- Name: e.g., "Team Alpha"
- Kind: team (default), Enabled: on, Description: optional
3) Transport
- Choose one:
  - Streamable HTTP → Host here (recommended) or External Base URL
  - STDIO → run our own local process
- If Host here: the page displays the mounted path, e.g., /api/mcp/servers/:id/stream
- API Key (optional): header name (authorization by default) + key value stored in DB (redacted after save)
4) Security & Paths
- Hop Limit: 3 (default)
- Enable Path Policy (optional)
- Allowed Roots (chips) and Denied Paths (chips) for workspace confinement
5) Save

Tip: You can run “Test Connection” at any time on the server list to verify initialize → tools/list and a sample call.

### B. Add Sessions to the Team

1) Open your new server → Members tab → Add Existing Session.
2) For each session:
- Role: code | test | search | planner (choose one)
- Priority: lower number = higher priority
- Enabled: on
3) Drag to reorder priorities if needed.
4) Save.

### C. Configure Routing Rules

1) Open the Routing tab.
2) For each team.* tool, set Prefer and Fallback targets:
- Example: team.generate_code → prefer: openai, fallback: anthropic
- Example: team.run_tests → prefer: gemini
3) Save.

### D. Test the Team Server

1) Diagnostics tab → Test Connection.
2) Verify:
- initialize returns server info
- tools/list shows `team.*` tools
- sample call succeeds (optionally set cwd)
3) Download JSON trace if you want a record.

### E. Optional: Bind External Connectors to Sessions

1) MCP Hub → Manage Connectors → New.
2) Choose transport:
- Streamable HTTP (preferred) → Base URL + Headers (secret values stored in DB)
- STDIO → Cmd + Args (chips) + Env Vars (values stored in DB) + Working Dir
3) Save, then Test Connection.
4) MCP Hub → Manage Bindings → attach your connector to specific sessions with per-session overrides (headers/options/cwd), then Save.

### F. Day-to-Day Use

- In chats or tools that call MCP, target the Team server. The router sends work to the right session by role/priority and health.
- Use Diagnostics to view recent latency and errors; adjust routing or member priorities as needed.
- For local workflows, run a STDIO server on the project and point a connector at it.

## Project-Wide Process Notes

- Any new schemas/contexts/migrations must be created via Phoenix generators (e.g., `mix phx.gen.schema`, `mix ecto.gen.migration`).
- All runtime configuration (including secrets) is sourced from Postgres via Ecto — no `:ets` or ENV indirection for runtime values.
- Redaction rules cover fields matching `*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD`, and `authorization`.

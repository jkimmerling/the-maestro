# Story | Epic | Overhaul — TUI ↔ LiveView Session Parity
- Owner: dev
- Start: 2025-09-30  Target End: 2025-10-02
- Links: [Issue](), [PR](), [Design Doc]()

## Goals
- TUI and LiveView create/edit sessions using identical payloads and backend logic.
- TUI uses lazy session creation: on first user message, POST create-session, then send the message.
- If settings are incomplete on startup, TUI runs a one-time Setup Wizard and saves all defaults to settings.json.
- Working dir is always the process CWD for TUI; never user-editable in the TUI.
- TUI lists and manages only remote sessions (tool_runtime=remote). LiveView sessions are local and must not appear in TUI list.
- Deleting sessions is supported from the TUI sessions screen.

## Tasks
- [x] Backend parity verification
  - [x] Confirm POST /sessions and PATCH /sessions/:id accept the same keys LiveView sends (see `lib/the_maestro_web/live/session_chat_live.ex`).
  - [x] Ensure `apply=now|defer` works identically to LiveView (restart stream when `now`).
  - [x] Ensure GET /sessions?tool_runtime=remote filters correctly; LiveView-created sessions remain `local`.
  - [x] Ensure DELETE /sessions/:id deletes remote sessions safely.
  - [x] GET /sessions/:id returns derived `provider`, auth meta, and full session config (persona, memory, tools allowlist, MCPs, system prompts).
  - [x] Expose/read prompt library/builder and tool inventory/MCP endpoints with shapes used by LiveView (if not already present).
- [x] TUI: settings defaults and Setup Wizard
  - [x] Extend `~/.the_maestro/settings.json` with `session_defaults` (persona, memory, tools allowlist, `mcp_server_ids`, `system_prompt_ids_by_provider`).
  - [x] Exclude `working_dir` from settings; compute CWD at runtime.
  - [x] Implement Setup Wizard to gather missing defaults (Provider/Auth/Model; defaults for Persona/Memory/Tools/MCP).
  - [x] Save all wizard choices to `settings.json`.
- [x] TUI: lazy session creation flow
  - [x] On first message with no active session, POST /sessions with: `auth_id`, `model_id`, `working_dir=CWD`, `tool_runtime=remote`, plus persona/memory/tools/MCP/system prompts from `session_defaults`.
  - [x] Set `current_session_id` from response; clear `current_thread_id`; then POST turn and attach SSE.
- [x] TUI: sessions list and deletion (remote only)
  - [x] List sessions via GET /sessions?tool_runtime=remote.
  - [x] Add Delete action (DELETE /sessions/:id). If deleting the active session, clear app state and mark reload.
- [ ] TUI: session edit parity
  - [ ] Replace model-only picker with a full Session Config modal mirroring LiveView sections (minus Working Dir UI).
  - [ ] PATCH /sessions/:id with identical payload keys (+ `working_dir=CWD`, `apply=now|defer`).
  - [ ] After successful edit, update `settings.json` `session_defaults` to keep defaults aligned.
- [x] TUI: orchestration/provider source
  - [x] Remove provider guessing; fetch provider from GET /sessions/:id or cache after POST/PATCH.
  - [x] On function_call frames, normalize using session provider; execute IO tools locally; POST `function_call_output` in order.
- [ ] Documentation and parity review
  - [x] Cross-check payloads against LiveView’s `build_session_update_attrs/2` and related helpers.
  - [ ] Update README snippets if needed.

## Dev Notes
- Use LiveView modal as the canonical source for payload shape. Mirror keys exactly:
  - `auth_id`, `model_id`, `working_dir` (TUI sends CWD), `persona`, `memory`, `tools` (allowlist map), `mcps`, `mcp_server_ids`, `system_prompt_ids_by_provider`.
  - PATCH adds `apply` (`now` or `defer`).
- Ensure TUI always sets `tool_runtime=remote` on POST /sessions; listing filters by `tool_runtime=remote`.
- Remove Working Dir from any TUI UI; always compute with `os.getcwd()` and include in POST/PATCH.
- For prompt builder, reuse server shapes used in LiveView: entries with `%{id, enabled, overrides}` per provider.
- Orchestrator must read provider from session (no heuristics); keep tool results POST flow unchanged.
- Reference files:
  - `lib/the_maestro_web/live/session_chat_live.ex`
  - `lib/the_maestro/providers/openai/streaming.ex`
  - `lib/the_maestro/tools/tool_surface.ex`

## Blockers
- 2025-09-30 Confirm/implement endpoints for prompt library/builder and tool inventory/MCP — Status: open — Owner: dev
  - Next step: enumerate current endpoints; add missing ones with LiveView-compatible shapes
  - Link: 

## Deviations From Plan
- 2025-09-30 None yet
  - Reason: 
  - Impact: 
  - Approval: 

## Tests Created and Ran
- Test plan:
  - Success paths:
    - Lazy create on first message uses `CWD` and `tool_runtime=remote`.
    - Edit session PATCH with `apply=defer` updates next turn; `apply=now` restarts stream and TUI reattaches.
    - Remote-only sessions list; delete removes and clears active state when applicable.
    - Function-call roundtrip executes local tools and posts `function_call_output`.
    - Prompt/Tools/MCP selections roundtrip from TUI to server and back.
  - Edge/failure paths:
    - Missing settings triggers Setup Wizard; subsequent launch skips wizard.
    - Streaming provider overloaded/retry remains handled by backend; TUI remains attached.
- Implemented:
  - [ ] Unit
  - [x] Integration (Phoenix.ConnCase, Phoenix.LiveViewTest)
  - [ ] E2E
- Files:
  - Phoenix: `test/the_maestro_web/controllers/sessions_api_parity_test.exs`, `test/the_maestro_web/controllers/api_prompts_mcp_endpoints_test.exs`
  - Python: `clients/maestro_tui_python/tests/test_session_management_integration.py` (updated)
- Commands and results:
  - `mix test test/the_maestro_web/controllers/sessions_api_parity_test.exs` — pass
  - `mix test test/the_maestro_web/controllers/api_prompts_mcp_endpoints_test.exs` — pass
  - `pytest -q clients/maestro_tui_python/tests` — pending (install steps below)
  - `mix precommit` — pending
  - CI link: <URL>

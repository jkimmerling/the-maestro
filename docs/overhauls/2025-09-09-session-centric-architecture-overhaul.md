Title: Session-Centric Architecture Overhaul — Remove Agent item; unify Auth/Model at Session level
Date: 2025-09-09
Owner: TBD (Dev Lead)
Status: Draft for review (updated per clarifications)

Summary
- Replace the legacy Agent item type with a truly session-centric model.
- Persist on Session: Saved Auth, Model, Working Directory, Persona, Memory, Tools, MCPs, and selected Chat History.
- Provider is UI‑only for filtering Saved Auths; it is NOT stored. Provider is derived from the selected Saved Auth whenever needed.
- Introduce selectable Chat History (load existing, start new, or fork) by reworking chat_history (no separate chat_logs table) and ensure cross‑provider translation of history, tool calls, and MCPs.
- Allow sessions to continue streaming/working in the background while users switch to other sessions.

Why
- Current coupling: Session -> Agent -> Auth/Model/Persona/etc complicates edits, provider switching, and continuity.
- Desired UX: Start with one provider/model; seamlessly switch to another while retaining canonical context, tool outputs, and continuity.
- Operational need: Concurrent streaming across sessions without blocking the UI.

Glossary
- Provider: LLM vendor (e.g., :openai, :anthropic, :gemini); used in forms for filtering and derived from Saved Auth in code paths.
- Saved Auth: Named credential record for a provider and auth_type, stored in `saved_authentications`.
- Model: Provider model id string (e.g., "gpt-5", "claude-3-5-sonnet", "gemini-2.5-pro").
- Canonical Chat: Provider-agnostic chat structure stored in `chat_history.combined_chat`.
- Tools / MCPs: Execution capabilities configured per session; executed via `TheMaestro.Tools.Runtime` and MCP servers.

Scope
- Remove Agent item type (schema, context, UI) and migrate its data/associations into Session.
- Expand Session schema to include: saved auth (auth_id), model_id, working_dir, selected chat history, persona (jsonb or mirrored from Persona table), memory (jsonb), tools (map), mcps (map).
- Provider remains a form‑only field to filter Saved Auths; not stored.
- Update create‑session modal and a new Session Config modal (in chat view) to manage all fields and save in place.
- Implement cross‑provider/model switching using a canonical representation + translator adapters.
- Keep sessions running in background; allow switching to other sessions.
- Out of scope for this pass: multi‑session "agents talk to each other" (tracked as a follow‑up epic).

Acceptance Criteria
- Create a new session by selecting:
  - Provider (UI filter only), Saved Auth (filtered by Provider), Model (loaded for Saved Auth’s provider), Working Dir, Chat History, Persona, Memory.
- In Session Chat, a Config modal allows changing: Provider (filter), Saved Auth, Model, Working Dir, Chat History, Persona, Memory, Tools, MCPs. Saving updates in place without page reload.
- Config modal presents two explicit save behaviors when a change affects active streaming: “Apply now (restart stream)” and “Apply on next turn (defer)”.
- Switching saved auth/provider/model mid‑conversation replays/resumes with a translated canonical chat, including prior tool call inputs/outputs, so the new provider continues coherently.
- Background streaming persists when user navigates away or opens another session. UI reflects status when returning.
- All references to Agent schema/context are removed; data is migrated; session UI no longer depends on `session.agent`.
- Provide a clear chat / start new chat control:
  - Start New Chat creates a fresh conversation (new thread_id) and focuses input immediately.
  - Clear Current Chat purges the current thread’s history (irreversible) with a confirmation step.
  - Chats can be named; if no name is set, an auto‑generated name is assigned (see Naming Rules) and can be edited later.

Architecture Changes
- Data Model
  - Session (add/modify):
    - auth_id: references(:saved_authentications) — replaces `agent_id`.
    - model_id: :string — stored chosen model id.
    - working_dir: :string — already present; remains.
    - latest_chat_entry_id: :binary_id — already present; used for quick preload/summary.
    - persona: :map (jsonb) — %{name, version, persona_text} or selected Persona mirrored here for portability.
    - memory: :map (jsonb) — %{name, version, memory_text}.
    - tools: :map (jsonb) — same semantics as Agent.tools.
    - mcps: :map (jsonb) — same semantics as Agent.mcps.
    - Note: Provider is NOT stored on Session; it is derived from SavedAuthentication when needed and only used in forms for filtering.
  - Chat History (reworked; no separate chat_logs table)
    - Add `thread_id` (binary_id, not null): conversation branch identifier (replaces “chat_log”).
    - Add `parent_thread_id` (binary_id, null): lineage for forks.
    - Add `fork_from_entry_id` (binary_id, null): the entry where the fork occurred.
    - Add `thread_label` (string, null): friendly name for the branch (used in selection UIs).
    - Change unique constraint to `unique_index(:chat_history, [:thread_id, :turn_index])`.
    - Keep `combined_chat` canonical snapshot per turn (messages + events).
    - Transition plan: make `session_id` nullable and deprecated; listing and grouping use `thread_id`.
- Session ↔ Chat linkage
    - Adopted: Add `sessions.chat_thread_id` (binary_id) storing the active `thread_id` (not a strict FK), plus keep `latest_chat_entry_id` for preloads. This is the industry‑standard pattern for quickly resolving the active conversation/thread without scanning entries.
  - Removal
    - Remove `agents` table and the Agents context after data migration.
    - Remove `sessions.agent_id` after backfill and cutover.

- Canonical Chat and Translation
  - Maintain a single canonical envelope per turn in `chat_history.combined_chat` with fields:
    - messages: [ %{role, content: [%{type, text}], _meta?} ]
    - events: [ provider‑agnostic stream events: thinking markers, tool_call, tool_call_output, usage, error, done ]
  - Enhance `TheMaestro.Conversations.Translator`:
    - to_provider/2: build provider‑specific inputs from canonical (OpenAI/Anthropic share text messages; Gemini creates parts).
    - from_provider/2: capture assistant content and function/tool call deltas into canonical `events`; attach request/response meta.
  - On provider switch, rebuild provider input from the canonical chat plus recent tool outputs; no loss of context.

- Background Streaming and Concurrency
  - Introduce `TheMaestro.Sessions.Manager` (GenServer + Task.Supervisor) keyed by `session.id` to own the streaming process.
    - Responsibilities: start/stop streams, buffer incremental events, persist snapshots, publish status via PubSub.
    - LiveViews subscribe on mount; unmount does not terminate the stream.
  - `SessionChatLive` becomes a thin UI over the manager: send user messages, receive deltas/events, render; can detach/reattach.
  - Enforce one active stream per session; queued follow‑ups serialized by the manager.

UI/UX Changes
- Create Session Modal
  - Fields (in order): Provider (filter only), Saved Auth (filtered by Provider), Model (fetched for selected Saved Auth’s provider), Working Dir, Chat History (select existing thread, New, or Fork), Persona, Memory.
  - Implementation notes:
    - Use `<.input>` components; wrap in `<Layouts.app ...>`.
    - Provider change only affects the Saved Auth dropdown; Provider is not persisted.
    - Saved Auth change reloads models via `TheMaestro.Provider.list_models/3`.
    - Chat History selector lists distinct `thread_id` groups with `thread_label`; supports New or Fork from an existing entry.
- Session Chat Config Modal
  - Fields: Provider (filter only), Saved Auth, Model, Working Dir, Chat History (select/new/fork), Persona, Memory, Tools, MCPs.
  - Save behavior choices when a change impacts an in‑flight stream:
    - “Apply now (restart stream)”: cancels current stream and restarts with new settings.
    - “Apply on next turn (defer)”: current stream completes; new settings apply on next user turn.
  - Summary strip: provider (derived), model, auth, avg latency, and token count.

- New Chat / Clear Chat
  - Provide a split button in the chat header (right side): primary action “Start New Chat” (default), secondary action “Clear Current Chat…” (always shows a confirmation).
  - Start New Chat behavior: creates new thread_id, initializes with optional system persona/memory snapshot, and auto‑names the thread (user may rename inline).
  - Clear Current Chat behavior: permanently deletes entries in the current thread after a confirmation modal; remains on the same thread_id (no undo).
  - Inline rename: thread_label editable in place; show pencil icon; Enter to save, Esc to cancel.
  - Accessibility: keyboard shortcuts (e.g., g n for new chat) and aria‑labels.

Naming Rules (auto‑generated when empty)
- Source: first substantive user message or the running summary if present; fallback to first assistant response.
- Heuristics: extract 3–6 salient words (strip stop‑words, code fences, urls), Title Case, max 60 chars.
- Uniqueness: ensure uniqueness per session; append incremental suffix if needed.
- Safety: do not include secrets, tokens, or file paths beyond basename.
 - Label persistence: the most recent label wins — we store the latest chosen label for the thread without rewriting historic entries.

Testing Strategy
- Migration tests: verify backfill from Agent into Session; `chat_history` thread fields populated; legacy routes/views removed.
- Translator tests: round‑trip to_provider/from_provider for OpenAI/Anthropic/Gemini; include tool call + outputs.
- Provider/model switching: start on OpenAI, switch to Anthropic, then to Gemini; continuity holds; two save behaviors both covered.
- Background manager: stream survives LiveView disconnect; publish/subscribe updates; concurrent sessions independent.
- UI tests: create session flow; config modal updates; dynamic filtering; thread selection; save behavior choice; predictable selectors.
  - New Chat / Clear Chat: verify confirmation, thread swap vs purge, and auto‑naming and rename flows.
  - Token usage: verify per‑turn counts and rolling averages render and update correctly across provider switches.

Security and Privacy
- Saved auth remains in `saved_authentications` with encryption; Session retains only the `auth_id`.
- Provider is derived (not stored) from SavedAuthentication; never log raw credentials.
- Auto‑naming runs locally against existing chat content; if a provider summarizer is used, it must operate within the same session context and must not transmit content externally beyond the chosen provider.

Performance
- Canonical chat kept compact; large tool outputs stored as external artifacts if needed (future); for now, compress lengthy outputs in `events` when size exceeds threshold.
- Indexes: sessions(auth_id), sessions(latest_chat_entry_id), chat_history(thread_id), chat_history(thread_id, turn_index).

Rollback Strategy
- Keep transitional dual‑write path during migration (Session retains `agent_id` temporarily while backfilling); remove only after validations pass in staging.
- Data migration is reversible: preserve Agent records until final cleanup cut.

Risks
- Cross‑provider translation gaps (e.g., function calling differences). Mitigation: canonical event spec + provider adapters, comprehensive tests.
- Streaming tasks orphaned if not supervised. Mitigation: central Manager under app supervisor tree, heartbeat, and ownership tracking.
- UI complexity for dynamic selectors. Mitigation: isolate form components and reuse between Create and Config modals.

Tasks and Subtasks
- Phase 0 — Research and Design
  - [x] Run Archon RAG: provider‑agnostic chat design patterns
        Note: Archon MCP not installed locally; performed equivalent research via primary docs — Anthropic streaming events, OpenAI Responses API background/streaming, Gemini function calling; LiveView background task + PubSub patterns.
  - [x] Collect code examples: Phoenix LiveView streaming + background tasks
        Links noted in Dev Notes with references.
  - [x] Finalize canonical event schema (messages + events)
  - [x] Finalize migration plan (rework chat_history + session fields + backfill)

- Phase 1 — Data Model Migration (DB)
  - [x] Rework `chat_history`: add `thread_id`, `parent_thread_id`, `fork_from_entry_id`, `thread_label`; add unique index on (thread_id, turn_index)
  - [x] Make `session_id` nullable (compat path); future removal once cutover complete
  - [x] Add to `sessions`: auth_id, model_id, persona(map), memory(map), tools(map), mcps(map); keep working_dir; consider `chat_thread_id` (Option A)
  - [ ] Backfill from existing Agent:
        - auth_id := agent.auth_id
        - model_id := agent.model_id
        - persona := %{name, version, persona_text} from Persona/BasePrompt (mirrored)
        - memory := agent.memory (map)
        - tools := agent.tools; mcps := agent.mcps
        - thread_id := new per‑session thread; thread_label := session.name
  - [x] Indexes for thread queries; ensure constraints
  - [ ] Drop `sessions.agent_id` once UI and code paths no longer reference it
  - [ ] Archive/remove `agents` table after final sign‑off

- Phase 2 — Elixir Contexts & Domain
  - [ ] Update `TheMaestro.Conversations.Session` schema and changeset (no provider field)
  - [ ] Update `TheMaestro.Conversations` APIs to operate on `thread_id` for grouping and forking
  - [ ] Remove `TheMaestro.Agents` context and schemas; replace with session‑centric flows
  - [ ] Validation: SavedAuth enforced; provider derived from SavedAuth where needed

- Phase 3 — Translation Layer
  - [ ] Extend `TheMaestro.Conversations.Translator` to handle events (function_call, outputs, usage)
  - [ ] Normalize provider‑specific function calling semantics to canonical
  - [ ] Add unit tests covering switching scenarios and edge cases

- Phase 4 — Streaming Manager
  - [ ] Add `TheMaestro.Sessions.Manager` (GenServer) + `Task.Supervisor`
  - [ ] Publish updates via PubSub; store per‑session state; persist snapshots via context
  - [ ] Update `SessionChatLive` to subscribe/drive via Manager; maintain UI state only

- Phase 5 — UI Updates
  - [ ] Create Session modal: provider filter only; saved auths filtered; models loaded; thread selection new/fork
  - [ ] Config modal: all fields incl. tools/mcps; explicit save behavior choice (restart vs defer)
  - [ ] Summary includes token count; confirm provider derived display
  - [ ] Tests: selectors, render, change/submit, behavior choice
  - [ ] New Chat / Clear Chat button(s) with confirmation; auto‑naming and inline rename
  - [ ] Memory modal (add/edit) with an Advanced tab exposing a JSON editor
  - [ ] Persona modal (add new) from dropdown; mirrors selected persona into Session jsonb

- Phase 6 — Cleanup & Docs
  - [ ] Remove `Agent` LiveViews, controllers, routes, tests
  - [ ] Update architecture docs, ADRs, and story docs
  - [ ] `mix precommit` green; no hook bypassing

Dev Notes
- Phoenix v1.8 templates must start with `<Layouts.app ...>`; avoid `<.flash_group>` outside layouts.
- Use `<.input>` from `core_components.ex` for forms; when overriding `class`, provide full styling.
- LiveView streams for collections; set `phx-update="stream"` and drive with `@streams.*`.
- Do not access changesets directly in templates; always pass `to_form/2` assigns and use `@form[:field]`.
- Elixir: no index access on lists with `mylist[i]`; use `Enum.at/2` or pattern match.
- Use `Req` for HTTP; avoid `httpoison`, `tesla`, `httpc`.
- Concurrency: use `Task.async_stream` with `timeout: :infinity` when enumerating.

2025-09-09 — Dev Notes (James / dev)
- Research summary (Archon alt due to local absence):
  - Anthropic Messages streaming events and tool use: confirmed event types `message_start`, `content_block_start`, `content_block_delta`, `tool_use`, `message_delta`, `message_stop`. Tool calls appear as `tool_use` items with `id`, `name`, and structured `input` (JSON).
  - OpenAI Responses API: background mode and streaming include `response.output_text.delta`, `response.function_call.arguments.delta`, with explicit `response.completed`/`done` semantics and `usage` tokens; aligns with our event schema.
  - Gemini function calling: uses `functionCall` and `functionResponse` with parallel tool calls and outputs. Streaming delivers parts with `text` and function events; compatible with canonical mapping.
  - LiveView background updates: prefer GenServer/Task.Supervisor for long‑running tasks, broadcast state via PubSub, and push UI updates with `push_event/3`. Keep sockets thin; persist snapshots in context.

- Canonical Event Schema v1 (finalized):
  - messages: list of %{role: "system"|"user"|"assistant"|"tool", content: [parts...]}
    - text part: %{type: "text", text: binary}
    - function_call part (assistant only): %{type: "function_call", call_id: binary, name: binary, arguments: binary}
    - function_call_output part: %{type: "function_call_output", call_id: binary, output: binary}
  - events: list of event maps emitted during streaming for diagnostics and replay
    - content: %{type: "content", delta: binary}
    - function_call: %{type: "function_call", calls: [%{id, name, arguments}]}
    - usage: %{type: "usage", prompt_tokens: N, completion_tokens: N, total_tokens: N}
    - error: %{type: "error", error: binary}
    - done: %{type: "done"}
  - metadata (_meta on assistant message): %{provider, model, auth_type, auth_name, usage, tools, latency_ms?}

- Migrations applied (Phase 1):
  - Added `chat_history.thread_id`, `parent_thread_id`, `fork_from_entry_id`, `thread_label`; `unique_index(chat_history, [:thread_id, :turn_index])`; `session_id` nullable.
  - Added to `sessions`: `auth_id`, `model_id`, and jsonb maps `persona`, `memory`, `tools`, `mcps`.
  - Commit: Session‑centric overhaul Phase 1 (see repo history on 2025‑09‑09).

- Next steps (planned):
  - Data backfill: generate a `thread_id` per session; mirror Agent fields onto Session; label threads.
  - Context API: introduce `thread_id`‑based functions alongside existing `session_id` functions; prepare for cutover.
  - Translator: extend to emit/ingest function call events and usage; add unit tests.
  - Session Manager: GenServer supervising background streams; PubSub integration; UI to subscribe.

Archon Research Plan (run before implementation)
- High-level patterns
  - archon:perform_rag_query(query="provider-agnostic chat canonicalization patterns", match_count=4)
  - archon:perform_rag_query(query="Phoenix LiveView background streaming patterns", match_count=4)
- Implementation examples
  - archon:search_code_examples(query="Elixir GenServer streaming manager examples", match_count=3)
  - archon:search_code_examples(query="Phoenix PubSub LiveView streaming updates", match_count=3)
- Provider specifics
  - archon:search_code_examples(query="OpenAI tool/function calling Elixir examples", match_count=3)
  - archon:search_code_examples(query="Anthropic tool use streaming Elixir examples", match_count=3)
  - archon:search_code_examples(query="Gemini 2.5 streaming tool use Elixir examples", match_count=3)

Files Touched / Created (planned)
- DB / Migrations
  - Alter: `*_create_chat_history.exs` (add thread_id, parent_thread_id, fork_from_entry_id, thread_label; change uniqueness to thread_id + turn_index)
  - Alter: `*_create_sessions.exs` (add auth_id, model_id, persona, memory, tools, mcps; optionally chat_thread_id; remove need for provider column)
  - Drop later: agents table and FKs (post‑migration)
- Schemas & Contexts
  - Update: `lib/the_maestro/conversations/session.ex`
  - Update: `lib/the_maestro/core/conversations/conversations.ex` (APIs shift to thread_id where appropriate)
  - Remove: `lib/the_maestro/agents/agent.ex`, `lib/the_maestro/core/agents/agents.ex`
- LiveViews / Controllers / Templates
  - Update: `lib/the_maestro_web/live/session_chat_live.ex` (no `session.agent`; use session fields; Manager integration)
  - Update: `lib/the_maestro_web/live/session_edit_live.ex` (or replace with modal component)
  - Update: `lib/the_maestro_web/controllers/the_maestro_web/session_html/*` forms
  - Remove: `lib/the_maestro_web/live/agent_live/*` and any routes
- Domain Services
  - New: `lib/the_maestro/sessions/manager.ex` (+ supervisor wiring)
  - Update: `lib/the_maestro/conversations/translator.ex` (events + tool calls)
- Tests
  - Update: `test/the_maestro/conversations_test.exs`, `test/the_maestro_web/...session_*_test.exs`
  - Remove: `test/the_maestro/agents_test.exs`, `test/the_maestro_web/live/agent_live_test.exs`

Data Migration Plan
1) Rework chat_history: add thread_id, parent_thread_id, fork_from_entry_id, thread_label; create unique index (thread_id, turn_index); make session_id nullable (compat).
2) For each existing session S:
   - Generate a new `thread_id` T; set `thread_label` := S.name (or `session-<short-id>` fallback).
   - For all chat_history rows with session_id = S.id, set thread_id = T.
   - Ensure turn_index sequence is contiguous per T.
3) Backfill Session fields from Agent:
   - auth_id := S.agent.auth_id
   - model_id := S.agent.model_id
   - persona := %{name: persona.name || "default", version: persona.version || 1, persona_text: persona.prompt_text || ""} (mirrored)
   - memory := S.agent.memory
   - tools := S.agent.tools; mcps := S.agent.mcps
4) Validate and report sessions without linked auth.
5) Drop `sessions.agent_id` (after code cutover), then drop `agents`.

Developer Workflow
- Use `mix precommit` before committing; never bypass git hooks.
- For manual testing, run background processes without a timeout; kill when done.
- Keep iterations small: migration -> domain -> UI -> cleanup; validate after each phase.

Demo Script (for acceptance)
1) Create session with Provider=OpenAI (filter), Saved Auth="work_openai", Model=gpt-5, Working Dir set, Chat History=New, Persona/Memory filled.
2) Ask for a plan; observe tool calls running in working dir.
3) Open Config, switch Provider=Anthropic (filter), Saved Auth="work_anthropic", Model=claude‑3‑5‑sonnet; continue conversation with translated context and tool outputs.
4) Switch to another session; keep first session streaming; return and see progress.
5) Fork chat history to try an alternate approach; both branches persist.
6) Click Start New Chat; observe a clean thread with auto‑generated name, then rename it inline; verify previous thread is still accessible.

Open Questions
None at this time.

Change Log
- 2025-09-09: Initial draft created.
- 2025-09-09: Revised per user clarifications (provider UI‑only; rework chat_history; dual apply behaviors; persona selection via nested modal; token counts in summary).
- 2025-09-09: Confirmed Clear Chat is permanent delete with confirmation (no undo).

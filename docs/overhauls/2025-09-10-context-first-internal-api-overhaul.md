Title: Context‑First Internal API Overhaul — UI‑Independent Chat Orchestration (Idiomatic Phoenix)

Status: Proposal (2025‑09‑10)

Owner: Platform/Infra

Related:
- 2025‑09‑09 Session‑Centric Architecture Overhaul
- 2025‑09‑09 Phoenix Contexts + Ecto Overhaul
- Struct‑First Domain Overhaul

---

Purpose

- Centralize ALL business logic behind a single, internal Phoenix context API so every user interface (LiveView, AgentLoop, future REST/CLI) calls the same functions.
- Decouple UI lifecycles from long‑running chat turns so sessions continue streaming, tool follow‑ups run, and persistence completes even when users navigate away.
- Align strictly with idiomatic Phoenix: contexts own business logic and side effects; web/agent layers render state and send commands.

Non‑Goals

- No visual redesign. Minimal LiveView template changes beyond wiring to the new API.
- No changes to auth storage or provider creds formats.

Why Now

- We observed two correctness issues tied to UI‑owned logic:
  - Returning to a chat shows blank history due to missing `thread_id` on persisted entries and lack of param‑change re‑hydration.
  - Leaving a chat mid‑turn cancels finalization because the LiveView owns follow‑ups/persistence.
- Centralizing logic fixes both and sets a foundation for a REST API without duplicating behavior.

Guiding Principles (Idiomatic Phoenix)

- Contexts expose a stable domain API; UIs are thin adapters.
- Only contexts talk to Repo and orchestrators; UIs never call providers or Repo directly.
- Long‑running work is owned by supervised background processes.
- Events are published over PubSub; subscribers (UIs) render.
- All interfaces share the same context functions for feature parity.

High‑Level Architecture

- Context Facade: `TheMaestro.Chat`
  - Single entrypoint for chat/session operations, combining `Conversations` (persistence), `Sessions.Orchestrator` (streaming/tooling), and provider/model resolution.
- Persistence Context: `TheMaestro.Conversations`
  - Owns schemas and DB IO for sessions, chat entries, threads.
- Orchestrator: `TheMaestro.Sessions.Orchestrator` (evolves from `TheMaestro.Sessions.Manager`)
  - Starts provider streams, accumulates chunks/usage/tools, runs tool follow‑ups, applies retries, persists assistant turns, and emits lifecycle events.
- Eventing: Phoenix PubSub
  - Topics: `"session:" <> session_id`.
- UIs (LiveView, AgentLoop, future REST)
  - Only call `TheMaestro.Chat.*` and subscribe to `Chat.subscribe/1`.

Internal API Surface (initial)

```elixir
defmodule TheMaestro.Chat do
  @type session_id :: Ecto.UUID.t()
  @type thread_id :: Ecto.UUID.t()
  @type stream_id :: Ecto.UUID.t()

  # Session lifecycle / config
  def get_session(id), do: ...
  def update_session_config(id, attrs), do: ...
  def list_models(auth_id), do: ...

  # Threads
  def ensure_thread(session_id), do: ... # {:ok, thread_id}
  def new_thread(session_id, label \\ nil), do: ... # {:ok, thread_id}
  def rename_thread(thread_id, label), do: ...
  def clear_thread(thread_id), do: ...
  def latest_snapshot(session_id), do: ...
  def latest_snapshot_for_thread(thread_id), do: ...

  # Streaming turns
  def start_turn(session_id, thread_id, user_text, opts \\ []), do: ... # {:ok, stream_id}
  def cancel_turn(session_id), do: :ok

  # PubSub
  def subscribe(session_id), do: ...
  def unsubscribe(session_id), do: ...
end
```

Responsibilities & Data Flow

- LiveView (and other UIs)
  - On user input → `Chat.start_turn/3`.
  - On “Cancel” → `Chat.cancel_turn/1`.
  - Thread ops → `Chat.new_thread/2`, `Chat.rename_thread/2`, `Chat.clear_thread/1`.
  - Render messages from `Chat.latest_snapshot*/1` and subscribe to PubSub via `Chat.subscribe/1`.

- `TheMaestro.Chat`
  - Validates inputs; ensures a thread exists; persists the user turn immediately with `thread_id`.
  - Resolves provider/model/auth; starts orchestrator stream; returns `stream_id`.
  - Delegates to `Conversations` for persistence, and to `Orchestrator` for long‑running work.

- `TheMaestro.Sessions.Orchestrator`
  - Runs provider stream; emits `:thinking`, `:content`, `:function_call`, `:usage`, `:error`, `:done`.
  - Handles retries (e.g., Anthropic overload), runs tool follow‑ups, then persists assistant turn and updates session `latest_chat_entry_id` and `last_used_at`.
  - Publishes events regardless of UI presence; continues if LiveView disconnects.

- `TheMaestro.Conversations`
  - Persists all entries with `thread_id`.
  - Provides `latest_thread_id/1`, `latest_snapshot*/1`, `new_thread/1`, `delete_thread_entries/1`, etc.

Bug Fixes Integrated into This Overhaul

- Always set `thread_id` on EVERY persisted chat entry (user and assistant).
- LiveView implements `handle_params/3` to re‑hydrate on `:id` change and re‑subscribe to the correct session topic.
- Finalization (assistant persistence and tool follow‑ups) moves from LiveView to Orchestrator so leaving the page doesn’t cancel work.

Migration Plan (Phased)

Phase 1 — Introduce Facade and Thread Discipline
- Add `TheMaestro.Chat` facade that wraps current `Conversations` + `Sessions.Manager` without behavioral change.
- Update LiveView to call `Chat.subscribe/1` and `Chat.start_turn/…` (stop calling `Sessions.Manager` directly).
- Ensure user/assistant turns persist with `thread_id`; if not present, `Chat.ensure_thread/1` first.
- Add `handle_params/3` to LiveView for param‑change rehydration and PubSub resubscription.

Phase 2 — Move Finalization into Orchestrator
- Extract `finalize_no_tools/1`, tool follow‑up logic, and usage attachment from LiveView into the Orchestrator.
- Orchestrator persists the assistant turn via `Conversations.create_chat_entry/1` and updates session metadata.
- LiveView becomes a pure subscriber; remove persistence from LV.

Phase 3 — REST/Agent Parity
- Implement REST endpoints that delegate to `TheMaestro.Chat` (no new logic).
- Update AgentLoop to call `Chat.*` only.
- Add parity tests to ensure REST/LiveView/Agent produce the same persisted outcomes for identical inputs.

Phase 4 — Observability & Hardening
- Telemetry events for turn lifecycle (started, tokens, done/canceled, persisted).
- Dashboard session cards show “active turn” indicator via `Chat.subscribe/1`.
- Bounded retries and explicit cancel semantics remain in Orchestrator.

Acceptance Criteria

- UI‑independent completion: starting a turn, navigating away, and returning shows the assistant turn persisted and visible; tool follow‑ups executed.
- Single source of truth: No provider or Repo calls from LiveView, AgentLoop, or controllers; all go through `TheMaestro.Chat`.
- Thread integrity: All chat entries have `thread_id`; switching threads changes only scoped history.
- Navigation correctness: `handle_params/3` reloads state when `:id` changes; PubSub topic is switched.
- Test coverage: LiveView tests assert behavior via `Chat.*`; REST tests assert identical results given the same inputs.

Coding Standards (Enforcement)

- Web layer (controllers/LiveViews/components) must not:
  - Call `TheMaestro.Provider.*` directly.
  - Use `TheMaestro.Streaming.*` or `Task.Supervisor` directly.
  - Touch `Repo` directly.
- Add a Credo rule/checklist in PRs to flag the above in `lib/the_maestro_web/**` and adapters.
- Context functions return simple tuples; web layers never unwrap secrets or alter domain models.

Module Placement & Naming

- `lib/the_maestro/chat.ex` — internal API facade
- `lib/the_maestro/sessions/orchestrator.ex` — background orchestrator (rename/evolve from `Sessions.Manager`)
- `lib/the_maestro/conversations/**` — schemas + persistence
- `lib/the_maestro_web/**` — UI only

Data Contracts (selected)

- PubSub topic: `"session:" <> session_id`
- Stream messages: `%{type: :content | :function_call | :usage | :error | :done, metadata: map()}`
- Persisted message metadata stays in `combined_chat.messages[*]._meta` with `{provider, model, auth_type, auth_name, usage, tools, latency_ms}`.

Backward Compatibility

- Retain `Sessions.Manager` name temporarily; implement new behavior under `Sessions.Orchestrator` and delegate from Manager to Orchestrator during migration. Cut over once LV no longer uses the old entrypoints.

Risks & Mitigations

- Risk: Double‑persistence during migration.
  - Mitigation: Feature flag that toggles LV‑side finalization off only after Orchestrator persistence is verified in staging.
- Risk: Event ordering differences across providers.
  - Mitigation: Keep unified stream parser and normalize in Orchestrator prior to persistence.

Testing Strategy

- LiveView: navigate away mid‑turn; later assert assistant turn exists (`latest_snapshot_for_thread/1`).
- Orchestrator: property tests for chunk accumulation and tool follow‑up chaining.
- REST: turn parity vs LiveView with same inputs.
- Context: `thread_id` present on all entries and `latest_thread_id/1` behavior.

Operational Notes

- Supervisors: Orchestrator runs under its own `Task.Supervisor` per current design; can evolve to a dynamic supervisor per session if needed.
- Telemetry: emit metrics for latency, token counts, retry counts.

Implementation Checklist

- [ ] Create `TheMaestro.Chat` facade with functions above; thin delegation initially.
- [ ] Add `handle_params/3` to `SessionChatLive` and resubscription on `:id` change.
- [ ] Ensure `thread_id` is set on all persisted entries (user + assistant).
- [ ] Extract finalization + tool follow‑ups from LV into Orchestrator and wire persistence there.
- [ ] Update LiveView to call only `Chat.*` and remove direct `Sessions.Manager` invocations.
- [ ] Add REST endpoints that call `Chat.*` (parity only; no new logic).
- [ ] Add tests for mid‑turn navigation, parity across UIs, and thread integrity.
- [ ] Add Credo checks or repo‑wide grep CI for forbidden patterns in `lib/the_maestro_web/**`.

References

- Phoenix Contexts guide — contexts own business logic and data access.
- Internal repo docs: Session‑Centric Overhaul, Contexts + Ecto Overhaul, Struct‑First Domain Overhaul.

Notes for Implementation PRs

- Follow the repository’s pre‑commit checks; never bypass git hooks.
- Use `Req` for HTTP requests within providers or orchestration.
- Before coding, run Archon RAG queries for patterns and examples; annotate findings in PR descriptions.


# Struct-First Domain Overhaul (Streaming + Request Meta + Versioned JSON)

Status: In progress — Stage 1 complete (Option B – Standard)
Owner: Platform / Runtime
Date: 2025‑09‑10

## Summary

We will introduce a small set of domain structs (and one embedded schema) that become the source of truth for our internal data contracts while keeping provider adapters (OAuth and streaming HTTP) 100% map‑based at the wire edge. This yields safer refactors, fewer shape bugs, and clearer cross‑module boundaries without risking compatibility with OpenAI / Anthropic / Gemini.

Scope is intentionally surgical: streaming events, request metadata, and the persisted combined_chat shape. No DB schema changes are required; combined_chat remains JSONB (optionally validated via embedded_schema or a custom Ecto.Type).

## Non‑Goals / What NOT To Change

- Do NOT change provider OAuth request builders or headers.
  - Keep literal maps with string keys for bodies and explicit header lists in adapter modules.
  - No struct→JSON auto‑encoding in outbound OAuth requests.
- Do NOT rename or “helpfully” transform provider field names at the HTTP edge.
- Do NOT touch Oban migrations or tables.
- Do NOT re‑introduce `Repo` usage outside contexts (except Oban job management where already allowed).
- Do NOT require DB migrations for this effort. combined_chat remains JSONB.

## Why This Helps

- One‑time normalization: provider/auth/model/time semantics are enforced once when constructing the struct(s), not repeatedly downstream.
- Safer cross‑module contracts: pattern matching on structs catches drift earlier than permissive maps.
- Fewer regressions in streaming/UI: we eliminate ad‑hoc message/event shapes.

## Target Design (Option B – Standard)

New domain types (files under `lib/the_maestro/domain/`):

- `ProviderMeta` (struct)
  - Fields: `provider :: :openai | :anthropic | :gemini`, `auth_type :: :oauth | :api_key`, `auth_name :: String.t()`, `model_id :: String.t()`, `session_uuid :: String.t() | nil`
  - `new!(opts)` smart constructor: normalizes provider (string→atom; allowlist), validates auth_type, default `session_uuid`.

- `RequestMeta` (struct)
  - Fields: `provider_meta :: ProviderMeta.t()`, `usage :: Usage.t() | nil`
  - `new!/1` from raw assigns/params. Adds future room for tracing/request IDs.

- `Usage` (struct)
  - Fields: `prompt_tokens :: non_neg_integer`, `completion_tokens :: non_neg_integer`, `total_tokens :: non_neg_integer`
  - `new/1` computes `total_tokens` when omitted.

- `ToolCall` (struct)
  - Fields: `id :: String.t()`, `name :: String.t()`, `arguments :: String.t()` (raw JSON string)
  - Built from provider‑specific events.

- `StreamEvent` (struct)
  - Fields: `type :: :content | :function_call | :usage | :done | :error`, `content :: String.t() | nil`, `tool_calls :: [ToolCall.t()]`, `usage :: Usage.t() | nil`, `raw :: map()`
  - Purpose: canonical streaming event shape consumed by Managers/LV.

Persisted JSON (combined_chat):

- `CombinedChat` (embedded_schema or plain struct placed at `lib/the_maestro/domain/combined_chat.ex`)
  - Fields: `version :: String.t()` (e.g., "v1"), `messages :: [map()]`, optional `events :: [map()]`
  - If embedded_schema: add `changeset/2` to validate keys; pair with an `Ecto.Type` only if you want automatic cast/load in ChatEntry. Otherwise, keep as plain struct with `to_map/1` and `from_map/1` helpers used at the boundary.

## Implementation Plan

Progress Checklist (2025-09-10):
- [x] 1) Add the domain structs — modules exist with `@enforce_keys`, `new/1` and `new!/1`; added `StreamEvent.content/1`, `usage/1`, `tool_calls/1` helpers
- [ ] 2) Normalize streaming events in one place — return `%StreamEvent{}` from `TheMaestro.Streaming.parse_stream/3`
- [ ] 3) Managers/UI consume `%StreamEvent{}` — update `Sessions.Manager` and LiveView
- [ ] 4) Persist `CombinedChat` via helper — ensure `to_map/1`/`from_map/1` usage at boundary
- [ ] 5) Compatibility helpers — thin adapter for any legacy consumers
- [ ] 6) Tests and contracts — unit + golden request fixtures
- [ ] 7) Rollout and flagging — optional `:struct_events` flag, logging

### 1) Add the domain structs

- Create modules listed above with `@enforce_keys` for required fields and `new!/1` constructors that:
  - Normalize provider string→atom using `TheMaestro.Provider.list_providers/0` as the allowlist.
  - Validate `auth_type in [:oauth, :api_key]`.
  - Default/compute derived fields (e.g., `Usage.total_tokens`).
  - For `StreamEvent`, provide helpers: `content/1`, `usage/1`, `tool_calls/1`.

Status: Completed 2025‑09‑10. Structs created and constructors implemented; `StreamEvent` helpers added.

Already scaffolded/implemented in this branch:
- `lib/the_maestro/domain/provider_meta.ex`
- `lib/the_maestro/domain/request_meta.ex`
- `lib/the_maestro/domain/usage.ex`
- `lib/the_maestro/domain/tool_call.ex`
- `lib/the_maestro/domain/stream_event.ex`
- `lib/the_maestro/domain/combined_chat.ex`

### 2) Normalize streaming events in one place

- Update `TheMaestro.Streaming` (and `OpenAIHandler`) so `parse_stream/3` returns `%StreamEvent{}` instances wrapping the raw provider events (`raw` field).
- Keep provider adapters unchanged; conversion happens after HTTP.
- Provide a thin compatibility function if any consumer still expects provider maps during the transition.

Recommended changes (when you wire it):
- `lib/the_maestro/streaming/*.ex`: have `parse_stream/3` return `%TheMaestro.Domain.StreamEvent{}`. Keep `raw: map` for diagnostics.
- `lib/the_maestro/streaming/openai_handler.ex` (or equivalent): centralize event→struct mapping.

### 3) Sessions.Manager publishes structs

- In `TheMaestro.Sessions.Manager`, after calling `Streaming.parse_stream/3`, publish `%StreamEvent{}` tuples on the PubSub channel (`{:ai_stream, stream_id, %StreamEvent{...}}`).
- Remove per‑message ad‑hoc map handling in favor of matching on `%StreamEvent{}`.

Where to change:
- `lib/the_maestro/sessions/manager.ex`: publish `{:ai_stream, stream_id, %StreamEvent{}}` and adjust consumers accordingly.

### 4) SessionChatLive consumes structs

- Replace scattered map lookups with pattern matches on `%StreamEvent{}`:
  - Append content via `event.content`.
  - Accumulate `event.tool_calls` and `event.usage`.
  - React to `event.type == :done` to finalize.
- Build `RequestMeta` (from `ProviderMeta` + selected model) once, store in assigns.

Where to change:
- `lib/the_maestro_web/live/session_chat_live.ex`: replace direct map access with `%StreamEvent{}` fields, build `%RequestMeta{}` where we currently build `req_meta` maps before persistence.

### 5) CombinedChat value object

- Introduce `CombinedChat` with `version: "v1"` and `messages: []`.
- Choose one of:
  - A) `embedded_schema` + `changeset/2` used explicitly when persisting/loading ChatEntry.
  - B) Plain struct with `from_map/1`/`to_map/1`; call these in `Conversations` when saving/reading `combined_chat`.
- Do not change the DB schema; still store as JSONB.

Where to change:
- `lib/the_maestro/conversations.ex`: call `CombinedChat.to_map/1` on write and `CombinedChat.from_map/1` on read around `ChatEntry.combined_chat`.
- `lib/the_maestro/conversations/chat_entry.ex`: optionally add an `Ecto.Type` later if you want automatic casting.

Optional feature flag (safe rollout):
- Add `config :the_maestro, :struct_events, true` (default true in dev/test). Gate `StreamEvent` publishing to allow a quick revert if needed.

### 6) Tests and contracts

- Add unit tests for constructors: `ProviderMeta.new!/1`, `RequestMeta.new!/1`, `StreamEvent` mapping, `Usage.new/1`.
- Update streaming tests to assert `%StreamEvent{}` fields rather than free‑form maps.
- Add “golden” contract tests for provider OAuth request payloads and headers (OpenAI/Gemini/Anthropic):
  - Build requests via adapters and assert exact JSON string (encoded) and header set match fixtures.
  - This guarantees struct changes never bleed into HTTP shapes.

### 7) Rollout and flagging

- Optional: feature flag `config :the_maestro, :struct_events, true` gating `%StreamEvent{}` publishing. Default ON in dev/test; allow disabling quickly in prod.
- Logging: emit a single line per turn summarizing provider/model/usage from `RequestMeta`.

## File/Module Inventory (est.)

New files (6–8):
- `lib/the_maestro/domain/provider_meta.ex`
- `lib/the_maestro/domain/request_meta.ex`
- `lib/the_maestro/domain/usage.ex`
- `lib/the_maestro/domain/tool_call.ex`
- `lib/the_maestro/domain/stream_event.ex`
- `lib/the_maestro/domain/combined_chat.ex` (struct or embedded_schema)
- (Optional) `lib/the_maestro/ecto_types/combined_chat.ex` for Ecto.Type wrapper

Updated files (≈10–15):
- `lib/the_maestro/streaming/*.ex` (central parse normalization)
- `lib/the_maestro/sessions/manager.ex` (publish `%StreamEvent{}`)
- `lib/the_maestro_web/live/session_chat_live.ex` (consume structs)
- `lib/the_maestro/conversations.ex` (save/load `CombinedChat` via helper)
- `lib/the_maestro/conversations/chat_entry.ex` (optional cast of `combined_chat`)
- Tests under `test/the_maestro/` and `test/the_maestro_web/` updated to assert structs

Effort estimate: 3–5 dev days (one senior engineer) + 1 day if enabling feature flag and golden fixtures.

## Invariants & Normalization Rules

- Provider normalization: string provider names must be converted to atoms from the allowlist (`list_providers/0`); unknowns default to `:openai`.
- Request meta must include `auth_type` and `auth_name` or fail construction.
- Usage fields default to 0; `total = prompt + completion` when omitted.
- CombinedChat must always carry `version`, even if `messages` is empty.

## Risks & Mitigations

- Risk: structs accidentally serialized into outbound OAuth calls.
  - Mitigation: keep adapters map‑only; add golden request tests.
- Risk: test churn from shape changes.
  - Mitigation: add small compatibility helpers; migrate spec by spec; flip feature flag if needed.
- Risk: subtle provider differences in function/tool call events.
  - Mitigation: Map provider events to `%ToolCall{}` defensively; retain `raw` in `%StreamEvent{}` for debugging.

## Coding Standards for This Overhaul

- Constructors (`new!/1`) raise on invalid input; add `new/1` variant returning `{:ok, t} | {:error, term}` where useful.
- Do not hide side effects in constructors; structs should be pure normalization/validation.
- Keep `raw :: map()` in `%StreamEvent{}` for tracing/diagnostics.
- No dynamic atom creation; only `String.to_existing_atom/1` after allowlist check.

## Example Skeletons (non‑executable)

`ProviderMeta`

```
defmodule TheMaestro.Domain.ProviderMeta do
  @enforce_keys [:provider, :auth_type, :auth_name]
  defstruct [:provider, :auth_type, :auth_name, :model_id, :session_uuid]

  def new!(opts) do
    # normalize provider, validate auth_type, default session_uuid
  end
end
```

`StreamEvent`

```
defmodule TheMaestro.Domain.StreamEvent do
  @enforce_keys [:type]
  defstruct [:type, :content, :tool_calls, :usage, :raw]
end
```

`CombinedChat` (plain struct)

```
defmodule TheMaestro.Domain.CombinedChat do
  @enforce_keys [:version, :messages]
  defstruct version: "v1", messages: [], events: []

  def from_map(%{"messages" => m} = map), do: %__MODULE__{version: map["version"] || "v1", messages: m, events: map["events"] || []}
  def to_map(%__MODULE__{} = cc), do: %{version: cc.version, messages: cc.messages, events: cc.events}
end
```

## Validation / Quality Gates

- `mix test` – update tests to assert `%StreamEvent{}` and `%RequestMeta{}` where applicable.
- `mix credo --strict` – keep zero warnings policy.
- `mix dialyzer` – add basic specs for constructors and stream conversions.
- OAuth contract tests – per provider, assert exact headers/body strings for request builders.

Suggested test additions:
- `test/the_maestro/domain/provider_meta_test.exs` – validates normalization rules and allowlist fallback.
- `test/the_maestro/domain/stream_event_test.exs` – maps provider messages→`%StreamEvent{}` including tool_calls and usage.
- `test/the_maestro/streaming/contract_openai_oauth_test.exs` (and anth/gemini) – assert headers and exact JSON body against fixtures.
- `test/the_maestro/conversations/combined_chat_value_object_test.exs` – round‑trip `from_map/1`↔`to_map/1`.

## Rollout Checklist

1) Land domain structs and conversion in Streaming; keep a runtime config flag to toggle struct events.
2) Update Sessions.Manager to publish structs; adapt SessionChatLive.
3) Add CombinedChat struct helpers; keep DB JSONB.
4) Update tests; add golden OAuth fixtures.
5) Run full pre‑commit gates; verify UI streaming and model selection paths.
6) Enable in staging; monitor logs (usage summations, tool call counts) vs baseline.

Operational tips:
- Log one summary line per assistant turn from `%RequestMeta{}` – provider/model/auth/total_tokens – for easy regression detection.
- If any consumer outside LiveView subscribes to `"session:" <> id`, add a temporary compatibility layer translating `%StreamEvent{}` to the previous map shape.

## Notes on Backward Compatibility

- PubSub messages: If any external consumer subscribes to `"session:" <> id`, consider providing a compatibility shim (map translation) behind the feature flag while migrating.
- Persisted rows: No migration; old JSON loads into the struct via `from_map/1`.

## Appendix: What This Does NOT Solve

- It doesn’t standardize every provider payload. That’s deliberate—providers differ. We normalize only the parts we actually rely on (events/meta/usage).
- It doesn’t add pagination, search, or analytics; those remain orthogonal enhancements.

## Practical Pointers (what I would do next)

- Wire `%StreamEvent{}` first (lowest risk, highest payoff), behind a config flag. Commit small.
- Migrate `SessionChatLive` to `%RequestMeta{}` next; keep persistence maps until all callers use the struct.
- Introduce `CombinedChat` last; start with manual `from_map/1`/`to_map/1` calls in `Conversations` to avoid any type surprises.
- Add golden request fixtures for OAuth adapters before touching any streaming code; they are your net.
- Keep all struct constructors side‑effect‑free and fast; prefer fail‑fast `new!/1` in the core paths and `new/1` for user input flows.

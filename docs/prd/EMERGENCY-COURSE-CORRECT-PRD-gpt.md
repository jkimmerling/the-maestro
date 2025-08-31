# 🚨 EMERGENCY COURSE CORRECT PRD (GPT Variant)
# Universal Provider Architecture Overhaul — Additive Corrections

Document Type: Emergency Product Requirements Document
Priority: CRITICAL
Status: ACTIVE
Version: 1.1 (GPT corrections)
Date: 2025-08-30

This PRD builds on docs/prd/EMERGENCY-COURSE-CORRECT-PRD.md and focuses on additive/corrective changes required to fully meet the goals of a clean, modular, drop‑in provider system with seamless generic interfaces. It does not replace the original; it clarifies, corrects, and extends it for execution.

---

## Summary of Changes vs Original PRD

- Dual‑mode OpenAI OAuth support mandated (Personal ChatGPT vs Enterprise API key exchange) with automatic account‑type detection and unified E2E coverage.
- Named sessions enabled by schema change (support >1 auth per provider/auth_type via `name`) with migration plan and acceptance.
- Streaming adapter requirement added so all providers feed TheMaestro.Streaming.parse_stream/3 the same way (Finch → SSE enumerable) and testable in E2E.
- HTTP client standardization: use `Req` for OAuth flows and E2E scripts immediately; keep existing Tesla provider clients during migration; plan optional provider migration to `Req` later.
- E2E filename unified to `scripts/test_full_openai_oauth_streaming_e2e.exs` and dual‑mode validations included.
- Context management UI hooks specified (LiveView IDs + streams) and interface acceptance.
- Loop/retry behavior specified (intelligent recovery and termination conditions).
- Gemini “code quality audit” tool defined with interface and acceptance gates.
- Tool “intent” parameters specified (purpose/scope/risk), persisted for audits.

---

## Goals (Unchanged)

- Universal provider interface with dynamic module resolution
- Drop‑in provider model (provider subfolders; oauth/api_key/streaming/models modules)
- Feature parity across providers and auth types (token refresh, named auths, model listing, streaming)

---

## Core Architecture Clarifications

### 1) Generic Interface (no change, clarified usage)

Public entry points (all provider/auth operations must use these):

- `TheMaestro.Provider.create_session(provider, auth_type, opts)` → `{:ok, session_id}`
- `TheMaestro.Provider.list_models(provider, auth_type, session_id)` → `{:ok, [model]}`
- `TheMaestro.Provider.stream_chat(provider, session_id, messages, opts)` → `{:ok, stream}`
- `TheMaestro.Provider.refresh_tokens(provider, session_id)` → `{:ok, tokens}`
- `TheMaestro.Provider.delete_session(provider, auth_type, session_id)` → `:ok`

All provider specifics remain behind provider modules resolved dynamically.

### 2) Dynamic Module Resolution (no change)

`:anthropic + :oauth → TheMaestro.Providers.Anthropic.OAuth`, etc. Ensure `Code.ensure_loaded?` and behavior compliance checks.

### 3) Provider Folder Structure (no change)

```
lib/the_maestro/providers/
├── provider.ex
├── resolver.ex
├── behaviors/
│   ├── oauth_provider.ex
│   ├── api_key_provider.ex
│   ├── streaming_provider.ex
│   └── model_provider.ex
├── anthropic/{oauth,api_key,streaming,models,config}.ex
├── openai/{oauth,api_key,streaming,models,config}.ex
└── gemini/{oauth,api_key,streaming,models,config}.ex
```

---

## Corrective Additions

### A) OpenAI Dual‑Mode OAuth (MANDATORY)

- Detect account mode from ID token (plan type + openai.com email):
  - Personal plans (Free/Plus/Pro/Team or OpenAI employee) → ChatGPT mode: use `access_token` directly with `https://chatgpt.com/backend-api/codex/responses` and headers including `chatgpt-account-id`.
  - Enterprise/Business/Edu/Unknown → API key mode: RFC 8693 token exchange (Stage‑2) at `https://auth.openai.com/oauth/token`, use returned API key with `/v1/responses`.
- The generic interface must hide these differences; providers/openai/oauth.ex implements both paths.
- E2E must validate both modes when applicable.

Acceptance (OpenAI):
- AC‑OA1: Account‑type detection implemented with safe fallbacks.
- AC‑OA2: Both flows supported end‑to‑end via `TheMaestro.Provider`.
- AC‑OA3: Streaming works identically through generic parser in both flows.

### B) Named Sessions — Schema Change (MANDATORY)

- Add `name` (string) to `saved_authentications` and change uniqueness constraint to `[provider, auth_type, name]`.
- Backfill existing rows to `name: "default_#{provider}_#{auth_type}"`.
- Update interface to require `name` on session creation; return the `name` or generated id as `session_id`.

Acceptance (Sessions):
- AC‑NS1: Multiple concurrent OAuth/API key credentials per provider.
- AC‑NS2: All generic calls accept named sessions.
- AC‑NS3: Migration executes without data loss.

### C) Streaming Adapter (MANDATORY)

- Provide a Finch→SSE adapter that yields an enumerable suitable for `TheMaestro.Streaming.parse_stream/3`.
- Option A: Implement `TheMaestro.Streaming.read_stream_chunk/2` for Finch responses.
- Option B: New utility module `TheMaestro.Streaming.FinchAdapter.stream_request/5` used by provider implementations and E2E tests.

Acceptance (Streaming):
- AC‑ST1: All providers use the same parser entry point.
- AC‑ST2: E2E validates chunked SSE parsing and `[DONE]` termination.

### D) HTTP Client Standardization — Req‑Only (MANDATORY)

- Use `Req` for all HTTP across the codebase (OAuth flows, provider API calls, streaming, tests). This replaces Tesla and HTTPoison usage.
- Keep existing Finch pools; `Req` runs on top of Finch by default.
- Provide a small `Req` client factory to apply base_url, headers, JSON, retry, and logging consistently per provider.

Acceptance (HTTP/Req):
- AC‑REQ1: No usage of HTTPoison/Tesla in the application code; all HTTP requests implemented via `Req`.
- AC‑REQ2: Provider modules (OpenAI/Anthropic/Gemini) perform all HTTP operations using `Req`.
- AC‑REQ3: Streaming is implemented using `Req` streaming + shared SSE adapter into `TheMaestro.Streaming.parse_stream/3`.

### E) E2E Test File and Scope

- Canonical file: `scripts/test_full_openai_oauth_streaming_e2e.exs`.
- Must execute full pipeline: OAuth URL → manual auth → token exchange → (OpenAI dual‑mode) → live streaming with standard prompt → generic stream processing → validations.
- Include interruption/retry tests (loop behavior).

Acceptance (E2E):
- AC‑E2E1: Full pipeline passes for real OpenAI integration.
- AC‑E2E2: Validates complete answer to standardized prompt.
- AC‑E2E3: Validates usage stats and error recovery.

### F) Context Management UI Hooks (LiveView)

- Add UI IDs and stream usage to inspect/delete context chunks.
- Parent container: `id="context-chunks" phx-update="stream"`.
- Acceptance must include selectors for LiveView tests.

Acceptance (UI):
- AC‑UI1: Unique DOM IDs present; selectors covered by tests.
- AC‑UI2: List/delete context chunk flows validated.

### G) Retry/Loop Behavior

- Intelligent retry with classification: auth errors (refresh), transient network (exponential backoff), SSE interruption (restart/resume semantics where provider allows).
- Termination conditions and telemetry for failures/success.

Acceptance (Loop):
- AC‑LP1: Defined retry classes and limits.
- AC‑LP2: E2E includes interruption handling scenario.

### H) Gemini Code Quality Audit Tool

- Add provider‑agnostic audit endpoint using Gemini: `TheMaestro.Provider.audit_code(:gemini, session, source, opts)` with structured findings.
- Include standardized prompt and output schema.

Acceptance (Audit):
- AC‑GM1: Audit callable via generic interface and returns structured results.

### I) Tool “Intent” Parameters

- All tool calls accept metadata: `%{purpose: :test_pass | :best_practice | :maintenance, scope: String.t(), risk_level: :low | :medium | :high}` and persist alongside context.

Acceptance (Intent):
- AC‑TI1: Intent captured and persisted; available to audits.

---

## Provider‑Specific Notes

### OpenAI

- OAuth config remains per codex public client.
- Dual endpoints:
  - ChatGPT mode: `https://chatgpt.com/backend-api/codex/responses` with `Authorization: Bearer access_token` and `chatgpt-account-id` header; `OpenAI-Beta: responses=experimental`.
  - Enterprise mode: `https://api.openai.com/v1/responses` with `Authorization: Bearer sk-*` (from Stage‑2 exchange) and env headers for org/project.
- Streaming: both paths must funnel through generic streaming.

### Anthropic

- OAuth manual code paste remains; provider module implements token exchange and streaming using generic parser.

### Gemini

- OAuth: research/implement Google Identity (PKCE) or start with API key path; both auth types must be supported behind `TheMaestro.Provider`.
- Streaming: handler already exists; ensure adapter path routes to parser.
- Model listing: implement via generic interface for both auth types.

---

## Data Model & Migration

Change `saved_authentications` schema:

- Add: `name :string`, required
- Unique index: `(:provider, :auth_type, :name)`
- Backfill migration: set `name` = `"default_#{provider}_#{auth_type}"` for existing rows

Acceptance:
- AC‑DM1: Multiple named sessions per provider/auth_type supported and enforced.

---

## E2E Test Specifications (Updated)

### Standard Prompt

"How would you write a FastAPI application that handles Stripe-based subscriptions? Include error handling and webhook verification."

### OpenAI OAuth + Streaming (Dual‑Mode)

File: `scripts/test_full_openai_oauth_streaming_e2e.exs`

- Generate OAuth URL (PKCE) and print.
- Run callback listener (no timeout) and capture auth code.
- Exchange for tokens via `Req`.
- Detect mode and, if necessary, perform Stage‑2 token exchange via `Req`.
- Send live streaming request; stream via Finch adapter → `TheMaestro.Streaming.parse_stream/3`.
- Validate full response, usage stats, interruption handling.

### Anthropic OAuth + Streaming

- Manual code paste flow; exchange via `Req`.
- Stream via generic parser; validate like OpenAI.

### Gemini OAuth/API Key + Streaming

- Implement OAuth (PKCE) or start with API key.
- Stream via generic parser; validate like OpenAI.

---

## UI/LiveView Requirements (Context Management)

- Parent container for chunks: `id="context-chunks" phx-update="stream"`.
- Child item IDs from `@streams` keys; include a “hidden only:block” empty‑state sibling.
- Tests must use LiveView selectors referencing these IDs.

---

## Roadmap Adjustments

- Phase 0.5: Schema migration for named sessions (AC‑NS1..3).
- Phase 1.0: Req‑only migration: replace Tesla/HTTPoison with `Req` across providers and OAuth (AC‑REQ1..3).
- Phase 1.4: Streaming adapter (AC‑ST1..2) using `Req` streaming.
- Phase 2.2 (OpenAI): Dual‑mode OAuth and E2E (AC‑OA1..3, AC‑E2E1..3).
- Phase 2.3 (Gemini): OAuth/API key parity and streaming (AC parity + E2E).
- Phase 3.x: UI context management, loop behavior, audit tool, intent metadata.

---

## Ambiguities Resolved

- HTTP client: `Req` everywhere (OAuth, providers, streaming, tests). Tesla/HTTPoison deprecated and removed.
- E2E filename unified; prior variants deprecated.
- OpenAI account‑type detection explicitly required and tested.
- Named sessions defined at data and interface level.

---

## Acceptance Criteria Addendum (Global)

- AC‑G1: All provider/auth interactions go through `TheMaestro.Provider`.
- AC‑G2: Streaming for every conversation via generic parser; no provider‑specific parsing at call sites.
- AC‑G3: Model listing available for all providers/auth types.
- AC‑G4: Token refresh available for all OAuth providers; verified via tests.
- AC‑G5: Multiple named sessions per provider/auth type supported and documented.
- AC‑G6: E2E tests implemented for OpenAI (dual), Anthropic (OAuth), Gemini (OAuth/API key).

---

## Risks & Mitigations (Delta)

- OpenAI mode detection edge cases → default to Enterprise token exchange with explicit warning; allow override via option.
- Streaming adapter correctness → comprehensive SSE fixture tests; real E2E coverage.
- Migration safety for `saved_authentications` → transactional migration with backup; idempotent backfill.

---

## Implementation Notes

- Prefer small, behavior‑specific modules; avoid cross‑cutting side effects.
- Keep provider specifics black‑boxed; the app only calls the generic interface.
- Follow Phoenix v1.8 LiveView and HEEx guidelines for UI work.

---

## Migration & Deprecation Plan (Using Existing Files, Then Retiring Them)

This plan explicitly describes how we leverage current files to keep things working while the new modular architecture is introduced, and how we retire the legacy code afterward.

### A) File‑Level Mapping (Current → New)

- `lib/the_maestro/providers/client.ex` (Tesla client)
  → Replace with per‑provider Req clients inside:
  - `lib/the_maestro/providers/{provider}/api_key.ex`
  - `lib/the_maestro/providers/{provider}/oauth.ex`
  - `lib/the_maestro/providers/{provider}/streaming.ex`
  - `lib/the_maestro/providers/{provider}/models.ex`
  - Temporary: keep `client.ex` as a compatibility shim that delegates to `TheMaestro.Provider` (marked @deprecated) until all call sites migrate.

- `lib/the_maestro/auth.ex` (mix of Anthropic/OpenAI OAuth with HTTPoison)
  → Move provider‑specific OAuth into `lib/the_maestro/providers/{provider}/oauth.ex` using Req. Keep `TheMaestro.Auth` only as a thin delegator (temporary) to the provider modules, switch its HTTP to Req, and mark deprecated.

- `lib/the_maestro/streaming.ex` (generic parser with stubbed `read_stream_chunk/2`)
  → Keep the generic parser. Add a new `TheMaestro.Streaming.Adapter` (Req streaming) used by provider streaming modules. Remove the stub once adapter is integrated.

- `lib/the_maestro/streaming/*_handler.ex` (OpenAI/Anthropic/Gemini handlers)
  → Retain. They already implement provider‑specific event handling and will be used by the new provider streaming modules.

- `lib/the_maestro/workers/token_refresh_worker.ex` (Oban)
  → Retain and update to call `TheMaestro.Provider.refresh_tokens/2` for all providers.

- `lib/the_maestro/saved_authentication.ex`
  → Migrate schema to add `name` and unique `provider+auth_type+name` constraint (see Data Model & Migration). Keep module.

- `lib/the_maestro/providers/openai_config.ex`, `anthropic_config.ex`
  → Consolidate into `lib/the_maestro/providers/{provider}/config.ex` (per provider) consumed by Req client factories. Remove legacy config modules after cutover.

- `lib/the_maestro/application.ex` (Finch pools)
  → Retain pools; `Req` uses Finch under the hood. Only update names if needed.

- Scripts (OAuth/E2E)
  → Consolidate under `scripts/test_full_openai_oauth_streaming_e2e.exs` and similar. Remove legacy variants after new scripts pass.

### B) Cutover Steps

1) Introduce the generic interface and resolver
- Add `TheMaestro.Provider` and `TheMaestro.Provider.Resolver` with behaviors for oauth/api_key/streaming/models.
- No behavior change to callers yet.

2) Implement Req client factory + streaming adapter
- Create a small helper to build per‑provider Req clients (base_url, headers, JSON, retry, logging).
- Add `TheMaestro.Streaming.Adapter` to convert Req streaming responses into SSE events consumed by `TheMaestro.Streaming.parse_stream/3`.

3) Migrate OpenAI (first provider)
- Implement `providers/openai/{oauth,api_key,streaming,models}.ex` using Req.
- Support dual‑mode OAuth and verify with the unified OpenAI E2E test.
- Wire background refresh via `TheMaestro.Provider.refresh_tokens/2`.

4) Switch call sites to `TheMaestro.Provider`
- Add a compatibility shim in `TheMaestro.Providers.Client` that forwards to `TheMaestro.Provider` (and warn with @deprecated).
- Update internal modules to call `TheMaestro.Provider` directly.

5) Migrate Anthropic and Gemini
- Implement Anthropic and Gemini modules using Req (OAuth + API key), streaming via the shared adapter, and model listing.
- Add/execute E2E tests for both auth types where applicable.

6) Remove legacy modules
- Once all call sites use `TheMaestro.Provider` and E2E/tests pass:
  - Remove `lib/the_maestro/providers/client.ex` (Tesla)
  - Remove HTTPoison code from `lib/the_maestro/auth.ex` and retire the module if no longer needed
  - Remove `providers/*_config.ex` legacy config modules (replaced by `{provider}/config.ex`)
  - Delete any deprecated scripts and documentation

### C) Deprecation Mechanics

- Annotate legacy entry points with `@deprecated` and log compile‑time warnings.
- Add Credo checks (or a CI grep) forbidding new references to deprecated modules.
- Maintain a short “Compatibility Window” (one sprint) before removal to allow any final consumer updates.

### D) Validation Gates for Deletion

- CI: No references to deprecated modules (grep/Credo rule passes).
- Tests: Unit, integration, and E2E all green using `TheMaestro.Provider`.
- Ops: Feature toggles (if used) removed or stabilized; telemetry shows no usage of legacy endpoints.

### E) Rollback Plan

- Keep the deprecation shims on a branch for quick restore.
- If needed, re‑enable the shim modules and re‑route calls back while investigating regressions.

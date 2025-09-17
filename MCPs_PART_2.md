# MCPs – Part 2: Dynamic, Provider‑Agnostic MCP Tooling (OAuth Only)

This document specifies how to make MCP tools fully dynamic and provider‑agnostic in The Maestro, with first‑class support for mid‑chat add/remove/update and correct per‑provider shaping when using OAuth:

- Gemini personal OAuth (Cloud Code)
- Anthropic OAuth (Claude Code)
- OpenAI OAuth (ChatGPT personal)

API‑key flows share the same canonical patterns but are out of scope here.


## Goals

- Live, session‑scoped MCP tool registry that can change at any time.
- Tools are injected into the provider request “in the first token slot” on every turn (initial and follow‑ups).
- Canonical chat and tool events remain the source of truth; provider payloads are just‑in‑time renderings.
- Seamless provider switching mid‑session; stable canonical ToolCall IDs with per‑provider ID mapping.
- Correct tool lifecycle per provider (Gemini functionCall/functionResponse, Anthropic tool_use/tool_result, OpenAI function_call/function_call_output).


## Architectural Overview

- Canonical state
  - CombinedChat JSONB (messages) + canonical stream events (content, function_call, usage) remain unchanged.
  - No provider‑specific payloads are stored; they are rendered per request.
- Dynamic overlays (computed every request)
  - Tool declarations (built‑ins + MCP) for the current session.
  - Optional transient inserts/deletes of messages for this request only (do not mutate CombinedChat unless explicitly requested).
- MCP registry (session‑scoped)
  - Maps canonical MCP tools to per‑provider exposed tool names and parameter schemas.
  - Example item:
    ```json
    {
      "canonical_name": "context7.search",
      "provider_exposed_name": {
        "gemini": "context7__search",
        "openai": "context7__search",
        "anthropic": "context7.search"
      },
      "connector_id": "...",
      "mcp_tool_name": "search",
      "server": "context7",
      "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
      "last_seen_at": "2025-09-12T13:05:00Z"
    }
    ```
  - Persist a compact snapshot under `session.tools["mcp_registry"]` and/or keep an ETS cache keyed by `session_id` with a monotonic `tools_revision` integer.
- Execution routing
  - Tools.Runtime.exec(name, args_json, base_cwd) consults the MCP registry; if the name maps to an MCP tool, it calls `TheMaestro.MCP.Service.call_tool/4` and returns the text (or error) payload.
- Turn lifecycle
  1) Stream model output → canonical events (`:function_call` etc.).
  2) Execute tools via Runtime.
  3) Send a follow‑up request with tool outputs, shaped per provider.


## Dynamic Changes Mid‑Chat

- Because provider payloads are rendered from canonical state on each call, any change to tools or context takes effect immediately on the next request.
- If tools are modified while a stream is inflight:
  - Default: apply changes in the next turn.
  - Immediate: cancel current stream and restart the same turn with the updated tool overlay and the same canonical history snapshot.
- Maintain a session‑scoped `tools_revision`. Providers read it right before building the request.


## MCP Registry – Build and Use

- Discovery inputs:
  - Session Connector bindings (rows in `session_mcp_bindings`), and/or `session.mcps` JSON (LiveView config form already supports this).
- Build steps:
  1) For each bound connector, call `MCP.Service.test_connector/2` (or `Client.list_tools/2`) to fetch tool declarations.
  2) Normalize parameter schemas (JSON Schema Draft‑07 superset). Drop unknown types or coerce to strings if the provider requires strict types.
  3) Generate provider‑specific names (sanitize):
     - Gemini: `[A-Za-z0-9_.-]`, length ≤ 63; replace invalid with `_`, middle‑ellipsize if too long.
     - OpenAI Responses: function name must be a string identifier; prefer same constraints as Gemini for consistency.
     - Anthropic: `tools[].name` is free‑form; keep canonical name or the sanitized one for parity.
  4) Store mapping and bump `tools_revision`.
- Lookup at execution time: map `provider_exposed_name` → `{connector_id, mcp_tool_name}` to call MCP.


## Provider Adapters (OAuth)

The adapters render the dynamic tool list and the per‑provider message shapes on every request. All three paths are already present in the codebase; here we specify how to extend them with the dynamic MCP registry.

### Gemini OAuth (Cloud Code)

Reference code: `lib/the_maestro/providers/gemini/streaming.ex`

- Endpoint and envelope
  - `POST https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse`
  - Request body top level:
    - `model`: prefer `gemini-2.5-pro` for OAuth (we already coerce to this model when needed).
    - `project`: user’s project (resolved via `CodeAssist.ensure_project/1`).
    - `user_prompt_id`: random UUID per prompt (we already set this).
    - `request`:
      - `contents`: Gemini messages (role + parts).
      - `generationConfig`: `{ "temperature": 0, "topP": 1 }` by default.
      - `systemInstruction`: optional.
      - `tools`: dynamic tools array.
- Dynamic tool declarations (inject each turn)
  - Build `functionDeclarations` from MCP registry + built‑ins.
  - Include both keys (for backend variance):
    ```json
    {
      "tools": [{
        "function_declarations": [...],
        "functionDeclarations": [...]
      }]
    }
    ```
  - Each `FunctionDeclaration`:
    ```json
    {
      "name": "context7__search",
      "description": "Search docs via context7",
      "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
    }
    ```
- Tool call/response lifecycle
  - Model emits: `role: "model"`, `parts: [{ "functionCall": { "name", "id", "args" } }]`.
  - We must respond immediately with: `role: "user"`, `parts: [{ "functionResponse": { "name", "id", "response": { ... } } }]`.
  - Do not insert any unrelated `contents` between the call and response in the same request.
- Mid‑turn changes
  - If tools change mid‑stream and you need them immediately, cancel and restart; otherwise they will appear in the next request.
- Implementation hooks
  - Replace the fixed `function_declarations/0` with `function_declarations_for_session(session_id)` to merge registry entries per turn.
  - Keep using `maybe_put_tools/2` to attach the array.


### Anthropic OAuth (Claude Code)

Reference structure: `/Users/jasonk/Development/the_maestro/source/llxprt-code` (Claude Code/Anthropic OAuth patterns).

Reference code: `lib/the_maestro/providers/anthropic/streaming.ex`

- Endpoint and envelope
  - OAuth: `POST /v1/messages?beta=true` (Claude Code environment); use `ReqClientFactory.create_client(:anthropic, :oauth, ...)`.
  - Body includes:
    - `model`, `messages`, `max_tokens`.
    - `system`: blocks required by Claude Code (our helper: `anthropic_system_blocks()`).
    - `tools`: dynamic MCP + built‑ins.
    - `metadata`: e.g., `user_id` for Claude Code; we already compute it from session.
- Dynamic tool declarations (inject each turn)
  - Build `tools: [%{ name, description?, input_schema }]` from registry + built‑ins, where `input_schema` is JSON Schema.
- Tool call/response lifecycle
  - Assistant emits a `tool_use` block with `id`, `name`, and structured `input` in an assistant message.
  - We execute, then reply in a user message with `tool_result` blocks referencing `tool_use_id`.
  - Multiple tool results can be batched.
- Mid‑turn changes handled the same as Gemini: restart if you must apply immediately.
- Implementation hooks
  - Replace `anthropic_tools/0` with `anthropic_tools_for_session(session_id)` merging MCP entries.
  - Use the transformation helpers already in the provider to remap messages into Claude Code “messages” blocks.


### OpenAI OAuth (ChatGPT personal)

Reference structure: `/Users/jasonk/Development/the_maestro/source/codex` (Codex/ChatGPT personal OAuth patterns).

Reference code: `lib/the_maestro/providers/openai/streaming.ex`

- Endpoint and envelope (personal OAuth)
  - `POST https://chatgpt.com/backend-api/codex/responses`
  - Required headers: `openai-beta: responses=experimental`, `session_id`, `originator`, `chatgpt-account-id`, etc. (we already set these via `ReqClientFactory`).
  - Body fields (subset):
    - `model`, `instructions`, `input` (Responses items), `tools`, `tool_choice`, `parallel_tool_calls`, `stream`.
- Dynamic tool declarations (inject each turn)
  - Build `tools: [%{ "type": "function", "name": ..., "parameters": ...}]` from MCP registry + built‑ins.
  - Enterprise/API‑key path uses `/v1/responses`; the OAuth personal path is the ChatGPT backend. The shape is the same for tools.
- Tool call/response lifecycle (Responses items)
  - Assistant yields `function_call` items with `call_id`, `name`, `arguments`.
  - We respond with `function_call_output` items `{ "call_id": id, "output": json_or_text }`.
  - For ChatGPT OAuth follow‑ups, set `parallel_tool_calls: false` (we already do this) to serialize outputs deterministically.
- Implementation hooks
  - Replace `responses_tools/0` with `responses_tools_for_session(session_id)`.
  - The follow‑up builders in `Sessions.Manager` already produce the right Responses items (see `build_openai_items/4`).


## Dynamic Context Inserts/Deletes (Per Request)

- Add a ContextView builder in the provider layer (concept):
  - Input: canonical `CombinedChat["messages"]`.
  - Transforms (per request only): `insert_before(index, message)`, `insert_after`, `delete_at`, `replace_at`.
  - Output: transformed messages, then render to provider shape via `Conversations.Translator.to_provider/2`.
- Guardrail (Gemini): if the last provider message had a `functionCall`, do not inject any unrelated content before we send the `functionResponse` in the same request.
- Persisted changes: only when explicitly requested; default is transient overlay.


## Session Manager Integration

- Start/Follow‑up calls should pass `session_id` through to provider adapters (already done) so each adapter can load the dynamic registry and build tool declarations.
- Add `tools_revision` to the session context; if it changes while building a request, either rebuild or cancel+restart to avoid stale tool lists.
- `run_tools_and_followup/3` is already provider‑aware:
  - Builds correct follow‑up shapes for Gemini, OpenAI, Anthropic.
  - Execution results are strings (JSON or text) from Tools.Runtime.exec/3.


## Runtime Execution (MCP)

- Tools.Runtime.exec/3 should:
  - Check if `name` resolves in MCP registry for the session.
  - Parse `args_json` (string) → map, validate minimal required fields.
  - Call `MCP.Service.call_tool(connector_id, session_id, mcp_tool_name, args_map)`.
  - Return `{:ok, payload}` or `{:error, reason}`.
- Error payloads are already wrapped by `tool_output_payload/1` in `Sessions.Manager` so providers get structured error outputs.


## Error Patterns and Remedies

- Gemini: `UNEXPECTED_TOOL_CALL` → the tool was not declared. Ensure the dynamic declarations include the MCP tool before the request is sent.
- Interleaving failures (Gemini) → ensure `functionResponse` immediately follows the `functionCall` in the same request.
- Schema strictness → sanitize/relax schemas to strings for unknown types, or omit optional fields with unknown types.


## Testing Matrix (OAuth only)

- Gemini personal OAuth
  - Single MCP tool call → functionResponse follow‑up.
  - Add a new MCP tool mid‑session → appears in the very next request and is callable without UNEXPECTED_TOOL_CALL.
  - Immediate apply: cancel + restart → tool is callable in the restarted turn.
- Anthropic OAuth (Claude Code)
  - tool_use → tool_result mapping; multiple tool_results batched.
  - Mid‑session add/remove reflected next turn; restart path works.
- OpenAI OAuth (ChatGPT personal)
  - function_call → function_call_output mapping.
  - `parallel_tool_calls: false` on follow‑up; headers present; mid‑session add/remove flows.


## File‑Level Plan (where to extend)

- New: `TheMaestro.MCP.Registry` (session‑scoped)
  - `build_for_session(session_id) :: %{tools: [..], tools_revision: int}`
  - `resolve(session_id, provider_exposed_name) :: {:mcp, connector_id, mcp_tool_name} | :unknown`
- Provider adapters
  - Gemini: `lib/the_maestro/providers/gemini/streaming.ex`
    - `function_declarations_for_session(session_id)` → merge built‑ins + MCP; inject via `maybe_put_tools/2`.
  - Anthropic: `lib/the_maestro/providers/anthropic/streaming.ex`
    - `anthropic_tools_for_session(session_id)` → merge built‑ins + MCP.
  - OpenAI: `lib/the_maestro/providers/openai/streaming.ex`
    - `responses_tools_for_session(session_id)` → merge built‑ins + MCP.
- Runtime
  - `lib/the_maestro/tools/runtime.ex` → route MCP tool names to `MCP.Service.call_tool/4` using the registry.
- LiveView (optional UX)
  - Session settings let users toggle MCP connectors; saving bumps `tools_revision`.
  - “Apply now” cancels current stream and restarts to apply tool changes immediately.


## References (local source examples)

- Gemini OAuth request structuring and tool lifecycle: `source/gemini-cli` (Google gemini‑cli) – see dynamic `tools` and functionCall/functionResponse ordering.
- Anthropic OAuth (Claude Code) request shaping and tool arrays: `/Users/jasonk/Development/the_maestro/source/llxprt-code`.
- OpenAI OAuth (ChatGPT personal) Responses API (codex backend) and tools: `/Users/jasonk/Development/the_maestro/source/codex`.


## Non‑Goals (for this phase)

- API‑key flows (OpenAI enterprise `/v1/responses`, Gemini Public GenLang) beyond reusing the same registry mappers.
- Persisting provider payloads. Canonical is the source of truth.


---

This plan keeps the canonical pipeline intact and adds a dynamic, session‑scoped MCP overlay that is re‑rendered on every request, enabling smooth mid‑chat tool changes across Gemini OAuth, Anthropic OAuth (Claude Code), and OpenAI OAuth (ChatGPT personal).


## MCP.Registry Interface (Proposed)

Purpose: single session‑scoped source for MCP tool discovery, provider name mapping, and declaration materialization.

Elixir shape (sketch):

```
defmodule TheMaestro.MCP.Registry do
  @type provider :: :gemini | :openai | :anthropic

  @type tool_decl :: %{
          canonical_name: String.t(),          # "server.tool"
          provider_exposed_name: %{optional(provider) => String.t()},
          connector_id: String.t(),            # Ecto.UUID.t()
          mcp_tool_name: String.t(),           # tool name on the MCP server
          server: String.t(),                  # MCP server alias/name
          parameters: map(),                   # JSON Schema object
          description: String.t() | nil
        }

  @spec build_for_session(String.t()) ::
          {:ok, %{tools: [tool_decl], tools_revision: non_neg_integer}} | {:error, term()}

  @spec resolve(String.t(), String.t()) ::
          {:ok, %{connector_id: String.t(), mcp_tool_name: String.t(), canonical_name: String.t()}} | :error

  # Provider declaration mappers (render every request)
  @spec to_gemini_decls(String.t()) :: [map()]                       # functionDeclarations array
  @spec to_openai_responses_tools(String.t()) :: [map()]              # Responses tools array
  @spec to_anthropic_tools(String.t()) :: [map()]                     # Claude tools array

  # Revisioning for mid‑chat changes
  @spec bump_revision(String.t()) :: :ok
end
```

Notes:
- Persist a compact snapshot in `sessions.tools["mcp_registry"]` and/or cache in ETS. Always compute declarations per request from the latest snapshot/ETS.
- Name sanitization helpers per provider:
  - Gemini/OpenAI: restrict to `[A-Za-z0-9_.-]`, ≤63 chars; middle‑ellipsize long names, e.g., `my-very-long-name...tail`.
  - Anthropic: keep canonical or sanitized for parity.

Example JSON persisted under `session.tools["mcp_registry"]`:

```json
{
  "revision": 7,
  "tools": [
    {
      "canonical_name": "context7.search",
      "provider_exposed_name": {
        "gemini": "context7__search",
        "openai": "context7__search",
        "anthropic": "context7.search"
      },
      "connector_id": "c3bd2a0f-7b7a-4c8e-a6a2-123456789abc",
      "mcp_tool_name": "search",
      "server": "context7",
      "description": "Search Context7 knowledge base",
      "parameters": {
        "type": "object",
        "properties": {"query": {"type": "string"}},
        "required": ["query"]
      }
    }
  ],
  "updated_at": "2025-09-12T13:05:00Z"
}
```


## Developer Progress Checklist (OAuth MVP)

Use this as a punch‑list. Each item references the primary file(s) to touch.

- [ ] Registry: scaffold session‑scoped MCP registry module
  - [ ] Add `lib/the_maestro/mcp/registry.ex` with `build_for_session/1`, `resolve/2`, declaration mappers, `bump_revision/1`.
  - [ ] Load connectors via `MCP.list_session_connectors/1` and fetch tools with `MCP.Service.test_connector/2`.
  - [ ] Sanitize names per provider; persist snapshot under `session.tools["mcp_registry"]` and keep ETS cache + `tools_revision`.

- [ ] Runtime routing to MCP
  - [ ] Update `lib/the_maestro/tools/runtime.ex` to consult Registry in `dispatch/3`.
  - [ ] If `name` matches an MCP tool, parse args JSON → map; call `MCP.Service.call_tool/4`; return `{:ok, payload}`/`{:error, reason}`.

- [ ] Gemini OAuth: dynamic tools injection
  - [ ] In `lib/the_maestro/providers/gemini/streaming.ex`, replace fixed `function_declarations/0` with `function_declarations_for_session(session_id)` backed by Registry.
  - [ ] Keep `maybe_put_tools/2` structure with both `function_declarations` and `functionDeclarations` keys.
  - [ ] Verify `functionResponse` immediately follows `functionCall` in follow‑ups (already handled by `build_gemini_items/4`).

- [ ] Anthropic OAuth (Claude Code): dynamic tools injection
  - [ ] In `lib/the_maestro/providers/anthropic/streaming.ex`, add `anthropic_tools_for_session(session_id)` that merges Registry tools.
  - [ ] Ensure we continue to send `system` blocks and `metadata` as required.

- [ ] OpenAI OAuth (ChatGPT personal): dynamic tools injection
  - [ ] In `lib/the_maestro/providers/openai/streaming.ex`, add `responses_tools_for_session(session_id)` that merges Registry tools.
  - [ ] Keep `parallel_tool_calls: false` for follow‑ups and ensure headers are set.

- [ ] Session settings / revision bump
  - [ ] On LiveView save (`lib/the_maestro_web/live/session_chat_live.ex#save_config`), after syncing connectors, call `MCP.Registry.bump_revision(session_id)`.
  - [ ] “Apply now” path already cancels and restarts the stream—verify it triggers tool re‑build on next call.

- [ ] Optional: transient ContextView transforms (per request)
  - [ ] Add a minimal builder to insert/delete/replace messages for this request only, prior to `Conversations.Translator.to_provider/2`.
  - [ ] Enforce Gemini guardrail (no inserts between `functionCall` and `functionResponse`).

- [ ] Smoke tests (manual)
  - [ ] Bind a Context7 MCP connector; confirm Gemini OAuth can call `context7.search` without UNEXPECTED_TOOL_CALL.
  - [ ] Remove the tool; confirm it disappears next turn; confirm “apply now” restarts and removes immediately.
  - [ ] Repeat for Anthropic OAuth (tool_use/tool_result) and OpenAI OAuth (function_call/function_call_output) flows.

- [ ] Edge cases
  - [ ] Name collision after sanitization → suffix with stable short hash; verify declarations show unique names.
  - [ ] Unknown schema types → coerce to `string` or omit optional fields; verify providers accept the schema.
  - [ ] Large tool lists → sanity‑limit per provider if needed (Gemini supports many; keep under practical limits).

- [ ] Observability
  - [ ] Log tool declaration counts and `tools_revision` per request (debug‑level).
  - [ ] Log MCP call timings and error summaries (already present in `MCP.Client`/`MCP.Service`).


## Definition of Done (OAuth MVP)

- Adding/removing an MCP tool updates the provider tool list for the next request; “apply now” restarts the active turn and applies immediately.
- Gemini/Anthropic/OpenAI OAuth flows can each call at least one MCP tool end‑to‑end with correct follow‑up message shapes.
- No UNEXPECTED_TOOL_CALL on Gemini when tools exist in the registry.
- Tool outputs and errors are visible to the LLM via the correct provider follow‑up item shapes.
- A developer can follow the checklist above and verify each step.

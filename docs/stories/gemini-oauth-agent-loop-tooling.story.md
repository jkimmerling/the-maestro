# Story: Gemini OAuth Agent Loop — Tool Use (Directory Listing)

## Status
Approved

## Story
As a Maintainer of The Maestro agent loop,
I want the Gemini OAuth path to support tool use end-to-end and successfully list the current working directory using our generic tools,
so that multi‑provider tooling is reliable, DRY, and consistent with OpenAI and Anthropic.

## Acceptance Criteria
1) Running `scripts/run_gemini_oauth_agent_loop.exs` prompts Gemini to “list the files in your directory” and produces a correct directory listing of the project root (or configured `tools_cwd`).
2) Tools remain generic in our code (no provider-specific tool shapes leak into `TheMaestro.Tools.*` or the agent loop call sites). Any translation/adaptation is implemented at the Gemini provider layer.
3) The first model turn may emit one or more function calls; the loop executes them and posts a follow‑up in the proper Gemini format (functionResponse parts, role `tool`) until the model returns a final text answer.
4) The final assistant message contains a readable directory listing (e.g., from `ls -la` or `list_directory` abstraction) matching the actual files in the working directory.
5) Logging shows a complete flow (requests + SSE events) in `gemini_api_flow.log`, including tool call(s) and tool response(s).
6) No Git hooks are bypassed at any time; normal commit/push only.
7) Manual test instructions are documented and pass on macOS (zsh) with `GEMINI_OAUTH_SESSION` configured and `gemini-2.5-pro`.
8) Tests and local runs must create any required sessions/agents dynamically and clean them up (delete) on completion; the database and workspace must not retain test-created sessions or agents after tests finish.
9) Developer runs the tests locally, fixes any failures, re-runs, and repeats the cycle until all tests pass and the interactive manual run produces a correct directory listing.

## Tasks / Subtasks
- [ ] Research: Confirm best‑practice tool semantics for Gemini OAuth (Cloud Code endpoint) vs. GenLang API
  - [ ] Search provider documentation for Gemini tool calling and `functionResponse` semantics (OAuth/Cloud Code streams).
  - [ ] Review local docs in `source/gemini-cli/docs/tools/*` (notably `file-system.md`, `shell.md`) for `list_directory` and `run_shell_command` examples and align naming/args.
  - [ ] If documentation is missing or unclear, ask the user to provide authoritative references or example payloads they want us to match.

- [ ] Update agent‑loop test prompt for Gemini
  - [ ] Change `scripts/run_gemini_oauth_agent_loop.exs` to ask: “List the files in your current working directory.”
  - [ ] Ensure the session/model come from env (`GEMINI_OAUTH_SESSION`, `GEMINI_MODEL`) with sane defaults
  - [ ] Print tools discovered/used and final text

- [ ] Provider‑level tool translation (DRY, generic tools)
  - [ ] Define a canonical tool name mapping in Gemini provider to translate our generic calls to Gemini’s tool schema:
    - `shell` → `run_shell_command` (args: `{command: string, directory?: string}`)
    - `list_directory` → `list_directory` (args: `{path: string, ignore?: [string], respect_git_ignore?: boolean}`)
  - [ ] Keep our tool executors (`TheMaestro.Tools.*`) unchanged and provider‑agnostic

- [ ] Implement Gemini follow‑up (tool result handshake)
  - [ ] Add `TheMaestro.Providers.Gemini.Streaming.stream_tool_followup/3` (parallel to OpenAI/Anthropic) that:
    - [ ] Accepts pending function calls, executes via our tools, builds Gemini `functionResponse` parts with matching `id` and `name`
    - [ ] Sends a follow‑up turn with role `tool` and parts `[{ functionResponse: { name, id, response } }]`
    - [ ] Streams the continuation until completion, aggregating text and additional tool calls if present (loop until no calls)
  - [ ] Update `TheMaestro.AgentLoop.run_turn/5` for `:gemini` to use the follow‑up loop (mirrors OpenAI/Anthropic branches)

- [ ] Ensure directory listing actually works in our workspace
  - [ ] Base CWD comes from project root or configured `tools_cwd` (Session → Tools CWD)
  - [ ] Validate we can execute `ls -la` via `shell` OR use `list_directory` abstraction and format output similarly
  - [ ] Respect `.gitignore` as appropriate if using `list_directory`

- [ ] Observability & Debugging
  - [ ] Enable `DEBUG_STREAM_EVENTS=1` to log parsed stream messages
  - [ ] Verify `gemini_api_flow.log` captures OAuth token exchange (redacted), request bodies, and SSE events

- [ ] Tests
  - [ ] Unit: Map provider tool calls to generic tools (translation function)
  - [ ] Unit: Build correct Gemini `functionResponse` payloads
  - [ ] Integration: Simulated stream with one `functionCall` → execute tool → `functionResponse` → final text
  - [ ] Integration: End‑to‑end script run produces a real directory listing
  - [ ] Data hygiene: Tests create ephemeral session(s) and agent record(s) and remove them during teardown; assert no leftovers remain after suite
  - [ ] Developer loop: Run tests, fix issues, re-run; iterate until green

- [ ] Docs & Safety
  - [ ] Note zero‑tolerance Git hook bypass policy in PR description
  - [ ] Add manual test steps and troubleshooting to `docs/` (see below)

## Dev Notes
- Scope: This is a documentation‑first story. Do not modify code as part of this document creation. Implementation will happen in a follow‑up story execution.
- Current code state (references):
  - `scripts/run_gemini_oauth_agent_loop.exs` — currently sends "Say 'hello-world'..." and returns first turn only.
  - `lib/the_maestro/agent_loop.ex` — Gemini branch collects calls but does not perform tool follow‑up; OpenAI/Anthropic branches show expected reference patterns.
  - `lib/the_maestro/streaming/gemini_handler.ex` — Converts Gemini `functionCall` parts into our unified `:function_call` messages; usage parsing present.
  - `lib/the_maestro/providers/gemini/streaming.ex` — Handles OAuth/GenLang endpoints; Cloud Code payload builder present. Needs a `stream_tool_followup/3` analogous to others.
  - `lib/the_maestro/tools/shell.ex` — Generic safe shell executor; use it for directory listing via `ls -la`, or implement a thin `list_directory` generic tool if desired (still provider‑agnostic).
  - `source/gemini-cli/docs/tools/file-system.md` — Documents `list_directory` semantics; good parity target for output formatting.
  - `source/gemini-cli/docs/tools/shell.md` — Documents `run_shell_command` including listing examples (`ls -la`).
- Provider translation principle:
  - Keep our internal tool API stable: tool names + JSON args.
  - Translate to provider‑specific functionCall names/arg shapes only at the boundary (Gemini provider). Reverse the translation for `functionResponse` handling.
- Gemini `functionResponse` details (to verify in research step):
  - Follow‑up message must use role `tool` with `functionResponse` parts carrying `name`, `id`, and `response` payload.
  - Ensure IDs round‑trip exactly from the corresponding `functionCall`.
- Manual testing policy reminder:
  - Do not use arbitrary 10s timeouts for background processes during manual testing. Start long‑running processes without timeouts and kill them when finished.
- Security/Compliance:
  - Respect zero‑tolerance git hook bypassing. If hooks fail, fix the issues and re‑run checks.

## Testing
- Manual
  - [ ] Set env: `export GEMINI_OAUTH_SESSION=personal_oauth_gemini`
  - [ ] Optional: `export GEMINI_MODEL=gemini-2.5-pro`
  - [ ] From repo root, run: `elixir scripts/run_gemini_oauth_agent_loop.exs`
  - [ ] Expectation: Model emits a function call → tool executes → follow‑up posted → final answer includes a readable directory listing for the repo root.
  - [ ] Inspect `gemini_api_flow.log` for request/response and SSE continuity.
- Automated (proposed)
  - [ ] Add a provider‑agnostic tool loop test fixture that simulates a Gemini stream with a single `functionCall` to `run_shell_command` returning `ls` output.
  - [ ] Verify that `stream_tool_followup/3` posts `functionResponse` with the correct `id/name/response` and that the loop finalizes with expected text.
  - [ ] Ensure test setup dynamically creates any SavedAuthentication/Session and Agent records needed for Gemini OAuth; teardown must delete them.
  - [ ] Add assertions that no test-created sessions/agents exist post-run.
  
### Developer Test-Run Loop (Required)
- [ ] Run full test suite locally: `mix test` (or target specific files)
- [ ] If failures: read failures, fix code, and re-run `mix test --failed`
- [ ] Repeat fix → run until all tests pass (green)
- [ ] Before committing, run quality gates: `mix precommit`
- [ ] Confirm no test-created sessions/agents remain in DB or config after tests (teardown verified)

## Files Touched / Created (Planned)
- Created: this story — `docs/stories/gemini-oauth-agent-loop-tooling.story.md`
- To Modify (implementation phase):
  - `scripts/run_gemini_oauth_agent_loop.exs` (prompt + logs)
  - `lib/the_maestro/agent_loop.ex` (Gemini follow‑up path)
  - `lib/the_maestro/providers/gemini/streaming.ex` (`stream_tool_followup/3`)
  - `lib/the_maestro/streaming/gemini_handler.ex` (validate call/args handling; adjust if needed)
  - (Optional) Add a generic `list_directory` tool (provider‑agnostic) if we prefer not to shell out for `ls`
- To Add (tests/docs as needed):
  - `test/the_maestro/providers/gemini_streaming_tool_followup_test.exs`
  - `docs/qa/gemini-tool-loop.md` (manual steps + troubleshooting)

## Change Log
| Date (UTC) | Version | Description | Author |
| --- | --- | --- | --- |
| 2025-09-06 | 0.1 | Initial story draft for Gemini tool loop directory listing | Dev Agent |

## Dev Agent Record
- Agent Model Used: _TBD at execution time_
- Debug Log References: `gemini_api_flow.log`
- Completion Notes: _TBD_
- File List (created/modified): _TBD_

## QA Results
_TBD after implementation_

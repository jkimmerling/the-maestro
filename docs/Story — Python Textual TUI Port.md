# Story | Epic | Overhaul — Python Textual TUI Port
- Owner: dev
- Start: 2025-09-28  Target End: 2025-10-26
- Links: [Issue](), [PR](), [Design Doc]()

## Goals
- Ship a Python Textual TUI with feature parity to the Elixir TUI and LiveView streams.
- Remote session workflow only: list and connect to sessions with `tool_runtime = "remote"`; never operate against local sessions.
- Exact parity for local tool behaviors and provider-specific tools (OpenAI, Anthropic, Gemini), including argument/return format.
- SSE client in TUI that matches server semantics: keep stream open until a `final` frame is emitted; ignore `done` for close; suppress rendering of `final` if content is empty.
- Thread operations parity: create, rename, list; add missing API endpoints.
- Real API keys with server-side CRUD UI and modal reveal; TUI reads host and key from `~/.the_maestro/config.json`.
- Packaging and distribution for macOS/Linux/Windows.
- Integration tests verifying end-to-end flows (remote session list → start turn → tool calls → follow-up → finalize).

## Tasks
- [x] Core scaffolding
  - [x] Create `clients/maestro_tui_python/` structure
  - [x] Python project init (pip), ruff/black/mypy config
- [x] Configuration
  - [x] Implement `~/.the_maestro/config.json` loader (host, api_key)
  - [x] Validate presence; friendly diagnostics if missing
- [x] API client (`maestro_tui/api/`)
  - [x] Auth header: `Authorization: Bearer <api_key>`
  - [x] Providers/auths/models
  - [x] Sessions: create, list remote (new endpoint)
  - [x] Turns: start turn, post tool results
  - [x] Frames: SSE consumer, polling fallback
  - [x] Threads: list/create/rename/clear (new endpoints)
- [x] SSE streaming
  - [x] Parse `event: message` with `data: {"data": frame}` lines
  - [x] Connection backoff + resume; heartbeat/idle handling
  - [x] Close only on `final` frame; handle `done` and `timeout`
  - [x] Do not render `final` if content is empty
- [ ] Local tool parity (`maestro_tui/tools/`)
  - [x] File ops: `write_file`, `edit`, `multi_edit` (apply_patch, notebook_edit — pending)
  - [x] FS utils: `list_directory`, `glob`, `grep`, `path_resolver` (seek_sequence — pending)
  - [x] Execution: `shell`
  - [x] Reads: `read`, `read_many`
  - [ ] Web: `web_search`, `web_fetch`, `google_web_search`
  - [ ] Planning: `todo_write`
  - [ ] Provider-specific normalization layers as needed
- [x] Textual UI
  - [x] Remote session picker (only `tool_runtime=remote`)
  - [x] Provider/Auth/Model wizard
  - [x] Chat screen: transcript, input, status bar, modals (initial)
  - [x] Threads picker when a session has multiple threads
  - [x] Markdown/code‑fence rendering in transcript
  - [x] Keyboard shortcuts and slash commands
- [x] Server work (APIs + UI)
  - [x] Sessions API: list (filter `tool_runtime=remote`)
  - [x] Threads API: list/create/rename/clear
  - [x] Snapshot API: `GET /api/threads/:thread_id/snapshot` (canonical transcript)
  - [ ] API Keys: DB model, CRUD LiveView, modal reveal, revoke/rotate
- [ ] Packaging
  - [ ] PyInstaller target build matrix
  - [ ] Release automation
- [ ] Tests
  - [x] Integration tests (Phoenix.ConnCase) for new APIs
  - [ ] LiveView tests for API Keys UI
  - [ ] Python integration tests for tool parity
  - [x] Python SSE integration smoke (env‑gated)

## Dev Notes

### Background & Motivation
The current Elixir TUI validated the approach; Python + Textual improves contributor reach and UX, and enables packaged binaries. The TUI remains hybrid: local FS tools on the client; everything else via server APIs.

### Architecture Principles
1. Async-first I/O (httpx + asyncio; manual SSE line parsing).
2. Tool compatibility: mirror Elixir tool args/returns exactly (including ExecOutput JSON envelope).
3. Error resilience: retries, bounded backoff, cancellation.
4. State management in Textual with reactive updates.
5. Security: path validation; deny traversal; never run local sessions.

### Core Dependencies
```toml
[dependencies]
textual = ">=0.47.0"
httpx = ">=0.25.0"        # streaming responses; parse SSE lines
rich = ">=13.0.0"
python-dotenv = ">=1.0.0"
aiofiles = ">=23.0.0"
watchdog = ">=3.0.0"
pydantic = ">=2.0.0"
```

## Blockers
- 2025-09-28 Dialyzer pre-commit hook failing on legacy warnings outside TUI — Status: open — Owner: dev
  - Next step: remove default-arg head conflicts; simplify guards; eliminate stale `Ecto.Multi` opaqueness; fix CLI parser no‑return
  - Link: mix dialyzer logs in local run; modules: `core/agents/agent_loop.ex`, `mcp/import.ex`, `streaming/gemini_handler.ex`, `tools/runtime.ex`, `tools/view_image.ex`

- 2025-09-28 SSE reconnect/backoff not yet implemented — Status: open — Owner: dev
  - Next step: add retry/backoff with jitter; idle heartbeat handling

## Deviations From Plan
- 2025-09-28 Removed `GET /api/sessions/{id}` from client design
  - Reason: endpoint does not exist; LiveView uses contexts directly
  - Impact: rely on `POST /api/sessions` and new `GET /api/sessions?tool_runtime=remote`
  - Approval: self-approved; matches current router

- 2025-09-28 Added `GET /api/threads/:thread_id/snapshot` for transcript hydration
  - Reason: TUI needs canonical messages to render clean transcript on session select
  - Impact: small controller + route; Phoenix.ConnCase test added
  - Approval: self-approved; consistent with `FramesController.latest`

- 2025-09-28 Replaced Ecto.Multi transactions in `Conversations` and Prompts Seeder
  - Reason: Dialyzer opaque warnings; simpler Repo.transaction paths
  - Impact: no behavior change; improved static analysis; tests green
  - Approval: self-approved

## Tests Created and Ran
- Test plan:
  - Success paths:
    - Remote session listing only returns `tool_runtime=remote`
    - Start turn → receive `user_text` → `assistant_thinking` → `assistant_text` → `function_call` → `tool_result` → `final`
    - Tool Results posted back (remote IO) and follow-up stream runs
    - Thread create/rename via API
    - API key CRUD LiveView (create + modal reveal + revoke)
  - Edge/failure paths:
    - SSE reconnect with `timeout` heartbeat
    - Empty `final` (no render) and `done` (ignored)
    - Invalid tool args → ExecOutput error envelope
    - Unauthorized API calls (missing/invalid key)
- Implemented:
  - [ ] Unit
  - [x] Integration (Phoenix.ConnCase, Phoenix.LiveViewTest)
  - [x] Python SSE reconnect integration (MockTransport)
  - [x] Python slash/threads integration (env‑gated)
  - [x] Python local tools tests (file ops, fs utils, shell)
  - [ ] E2E
- Files:
  - `test/the_maestro_web/controllers/api_sessions_remote_test.exs`
  - `test/the_maestro_web/controllers/api_threads_api_test.exs`
  - `test/the_maestro_web/controllers/api_frames_snapshot_test.exs`
  - `test/the_maestro_web/live/api_keys_live_test.exs`
  - `clients/maestro_tui_python/tests/test_sse_client.py`
  - `clients/maestro_tui_python/tests/test_tools_parity.py`
- Commands and results:
  - `mix test test/the_maestro_web/controllers/api/*_test.exs` — green (as of 2025-09-28)
  - `mix test test/the_maestro_web/controllers/api_frames_snapshot_test.exs` — green (as of 2025-09-28)
  - `mix test` — green except external/optional suites
  - `mix precommit` — red (Dialyzer stage; tracked in Blockers)
  - CI link: <pending>

---

## Remote Session Discovery & Connection
- Only list sessions with `tool_runtime = "remote"`.
- Proposed endpoint: `GET /api/sessions?tool_runtime=remote` → `{sessions: [{id, name, working_dir}]}`.
- TUI must not connect to `local` sessions because working directory would not align.

## Configuration File
- Path: `~/.the_maestro/config.json`
- Schema: `{ "api_host": "http://127.0.0.1:4000", "api_key": "<key>" }`
- The client composes URLs as `<api_host>/api/...` and sends `Authorization: Bearer <api_key>`.

## API Endpoints Used

Existing
```text
GET  /api/providers
GET  /api/providers/{provider}/saved_auths
GET  /api/providers/{provider}/saved_auths/{id}/models
POST /api/sessions
POST /api/sessions/{session_id}/turns
GET  /api/sessions/{session_id}/turns/{stream_id}/frames    # SSE (server emits until final)
POST /api/sessions/{session_id}/turns/{stream_id}/tools/results
GET  /api/threads/{thread_id}/turns/latest/frames           # Polling fallback
POST /api/threads/{thread_id}/clear
```

Proposed (to implement)
```text
GET   /api/sessions?tool_runtime=remote                     # list remote-only sessions
GET   /api/sessions/{session_id}/threads                    # list threads for a session (id/label/updated_at)
POST  /api/sessions/{session_id}/threads                    # create new thread {label?}
PATCH /api/threads/{thread_id}                               # rename {label}
```

## Frame Types and Stream Semantics
- `user_text` — initial echo of user message
- `assistant_thinking` — reasoning segments (may include partial content in payload)
- `assistant_text` — streaming deltas via `payload.delta`
- `function_call` — tool calls with `payload.calls = [%{id, name, arguments}]` (arguments is a JSON string)
- `tool_result` — tool result previews and timeouts
- `usage` — token usage updates
- `final` — finalization; includes `{content, meta}`; close SSE on first `final`
- `done` — stream completion marker; do not close on this alone
- `timeout` — heartbeat/idle signal

Rendering rule: suppress output for `final` when `content` is empty; still treat it as the close signal.

## Tool/Function Call Contracts
- Function calls (from frames):
  - Frame: `function_call`
  - Payload shape: `{ "calls": [ { "id": "<uuid>", "name": "<tool>", "arguments": "<json-string>" } ] }`
  - The `arguments` field is a JSON string, not a parsed object.
- Tool results (to server):
  - Endpoint: `POST /api/sessions/{session_id}/turns/{stream_id}/tools/results`
  - Body: `{ "call_id": "<uuid>", "name": "<tool>", "output": "<string>" }`
  - `output` should be the ExecOutput envelope when applicable: `{ "output": "...", "metadata": { "exit_code": <int>, "duration_seconds": <float> } }` serialized as a string.
  - Server previews up to ~200 chars and handles follow-up orchestration.

## Local Tool Mapping (Parity)

| Elixir Tool | Python Tool | Purpose | IO Type |
|------------|-------------|---------|---------|
| `ReadFile.run/2` | `read.py` | Read a file slice | Local |
| `ReadMany.run/2` | `read_many.py` | Read multiple files | Local |
| `WriteFile.run/2` | `write_file.py` | Create/overwrite files | Local |
| `Edit.run/2` | `edit.py` | Single string replacement | Local |
| `MultiEdit.run/2` | `multi_edit.py` | Multiple edits | Local |
| `NotebookEdit.run/2` | `notebook_edit.py` | Jupyter editing | Local |
| `ListDirectory.run/2` | `list_directory.py` | List files | Local |
| `Glob.run/2` | `glob.py` | Pattern matching | Local |
| `Grep.run/2` | `grep.py` | Search content | Local |
| `SeekSequence.run/2` | `seek_sequence.py` | Find sequences | Local |
| `Shell.run/2` | `shell.py` | Execute commands | Local |
| `ShellCommand.run/2` | `run_shell_command.py` | Gemini alias | Local |
| `ApplyPatch.run/2` | `apply_patch.py` | Apply diffs | Local |
| `WebSearch.run/2` | `web_search.py` | Search web | Local (network)
| `WebFetch.run/2` | `web_fetch.py` | Fetch URL | Local (network)
| `TodoWrite.run/2` | `todo_write.py` | Append a todo item | Local |

Provider differences: keep provider-specific wrappers (e.g., Gemini `run_shell_command`) separate where argument shapes differ.

## Provider-Specific Tool Parity
- Baseline sources that define the real interfaces to match:
  - OpenAI Codex: `source/codex`
  - Anthropic Claude Code: `source/claude_code.js`
  - Gemini CLI: `source/gemini-cli`

- Acceptance criteria:
  - Tool names, arguments (including JSON string vs object), return envelopes, and error formats match the above sources.
  - TitleCase vs snake_case aliases honored where applicable.
  - Gemini `run_shell_command` behavior and payloads match `source/gemini-cli`.
  - Web tools (`web_search`, `web_fetch`, `google_web_search`) follow provider-specific schemas.

- Tasks:
  - [ ] Extract tool schemas and examples from each source directory.
  - [ ] Write provider-specific adapters/normalizers in the Python TUI.
  - [ ] Add golden test fixtures derived from the sources for argument validation and output formatting.
  - [ ] Verify parity by running end-to-end flows against the server with each provider enabled.

## API Keys (Server UI + Storage)
- Add DB model `api_keys` (hashed token at rest, label, user/owner optional, last_used_at, revoked_at).
- LiveView: index/list, create (modal reveals plaintext once), revoke, rotate.
- Configurable scopes (future); initial scope grants API access to `/api` routes guarded by ApiAuth plug.
- TUI reads the generated key from `~/.the_maestro/config.json`.

## Development Notes

### 2025-01-28
- Initial story creation
- Analyzed Elixir TUI codebase
- Identified all local tools requiring porting
- Mapped API endpoints and frame types
- Confirmed architectural alignment with LiveView

### Architecture Decisions
1. Async everywhere (httpx streaming; manual SSE parsing)
2. Textual over curses
3. httpx over requests
4. Local tool execution for FS access
5. Pydantic models for API payloads

### Known Challenges
1. SSE reliability and backoff
2. Tool compatibility across providers
3. Packaging size

### Security Considerations
1. Path traversal prevention
2. Command injection hardening for `shell`
3. API key never logged; store only hashed on server
4. Obey server-side workspace confinement; no local session execution

## Related Documents
- [Story — Termite TUI Port + Burrito Packaging.md](./Story%20—%20Termite%20TUI%20Port%20+%20Burrito%20Packaging.md)
- Original Elixir TUI: `clients/maestro_tui/`
- API Controllers: `lib/the_maestro_web/controllers/api/`
- LiveView Implementation: `lib/the_maestro_web/live/session_chat_live.ex`

## Progress Tracking

```
Core Infrastructure             [          ] 0%
APIs (sessions/threads/keys)    [          ] 0%
Local Tools Parity              [          ] 0%
UI Components                   [          ] 0%
Streaming                       [          ] 0%
Testing                         [          ] 0%
Packaging                       [          ] 0%

Overall Progress:               [          ] 0%
```

---

SSE handling today: the API emits SSE from the server (`/api/sessions/:session_id/turns/:stream_id/frames`). LiveView does not use SSE; it subscribes to Phoenix PubSub. The new Python TUI must implement SSE parsing client‑side to match server semantics.

- [ ] Keyboard Shortcuts
  - [ ] Ctrl+Shift+L - Toggle log
  - [ ] Ctrl+Shift+P/A/M - Cycle provider/auth/model
  - [ ] Ctrl+Shift+N - New session
  - [ ] Ctrl+Shift+T - Toggle thinking
  - [ ] Ctrl+Shift+[/] - Switch tabs

- [ ] Slash Commands
  - [ ] `/context` - Show usage
  - [ ] `/model` - Model picker
  - [ ] `/help` - Keybindings
  - [ ] `/clear` - Clear thread
  - [ ] `/thinking` - Visibility mode

- [ ] Session Management
  - [ ] Multiple session tabs
  - [ ] Session persistence
  - [ ] Thread operations (new, clear, rename)
  - [ ] History navigation

### Phase 6: Testing & Quality ⏳
**Target**: Week 3-4

- [ ] Unit Tests
  - [ ] Tool testing with fixtures
  - [ ] API client mocking
  - [ ] Frame processing tests

- [ ] Integration Tests
  - [ ] End-to-end flow tests
  - [ ] SSE streaming tests
  - [ ] Tool execution tests

- [ ] UI Tests
  - [ ] Screen navigation
  - [ ] Keyboard input handling
  - [ ] Modal interactions

### Phase 7: Packaging & Distribution ⏳
**Target**: Week 4

- [ ] Build System
  - [ ] PyInstaller configuration
  - [ ] Platform-specific builds (macOS, Linux, Windows)
  - [ ] Asset bundling

- [ ] Distribution
  - [ ] PyPI package setup
  - [ ] Homebrew formula (macOS)
  - [ ] Snap package (Linux)
  - [ ] GitHub releases with binaries

- [ ] Documentation
  - [ ] Installation guide
  - [ ] Configuration documentation
  - [ ] Tool documentation
  - [ ] Developer guide

## Tool Mapping Reference

| Elixir Tool | Python Tool | Purpose | IO Type |
|------------|-------------|---------|---------|
| `WriteFile.run/2` | `write_file.py` | Create/overwrite files | Local |
| `Edit.run/2` | `edit.py` | Single string replacement | Local |
| `MultiEdit.run/2` | `multi_edit.py` | Multiple edits | Local |
| `NotebookEdit.run/2` | `notebook_edit.py` | Jupyter editing | Local |
| `ListDirectory.run/2` | `list_directory.py` | List files | Local |
| `Glob.run/2` | `glob.py` | Pattern matching | Local |
| `Grep.run/2` | `grep.py` | Search content | Local |
| `SeekSequence.run/2` | `seek_sequence.py` | Find sequences | Local |
| `Shell.run/2` | `shell.py` | Execute commands | Local |
| `ApplyPatch.run/2` | `apply_patch.py` | Apply diffs | Local |
| `PathResolver.run/2` | `path_resolver.py` | Path utilities | Local |

## API Endpoints Used

```python
# Authentication & Setup
GET  /api/providers                                    # List providers
GET  /api/providers/{provider}/saved_auths            # List auths
GET  /api/providers/{provider}/saved_auths/{id}/models # List models

# Session Management
POST /api/sessions                                     # Create session
GET  /api/sessions/{id}                               # Get session

# Chat Operations
POST /api/sessions/{session_id}/turns                 # Start turn
GET  /api/sessions/{session_id}/turns/{stream_id}/frames # SSE stream
POST /api/sessions/{session_id}/turns/{stream_id}/tools/results # Tool results

# Thread Management
POST /api/threads/{thread_id}/clear                   # Clear thread
GET  /api/threads/{thread_id}/turns/latest/frames    # Latest frames
```

## Frame Types

```python
@dataclass
class FrameType:
    ASSISTANT_TEXT = "assistant_text"      # Streaming response text
    ASSISTANT_THINKING = "assistant_thinking" # Thinking process
    FUNCTION_CALL = "function_call"        # Tool invocation
    TOOL_RESULT = "tool_result"            # Tool execution result
    USAGE = "usage"                         # Token usage
    FINAL = "final"                         # Turn completion
    DONE = "done"                           # Stream end marker
```

## Development Notes

### 2025-01-28
- Initial story creation
- Analyzed Elixir TUI codebase
- Identified all local tools requiring porting
- Mapped API endpoints and frame types
- Confirmed architectural alignment with LiveView

### Architecture Decisions
1. **Async everywhere**: Using asyncio for all I/O to prevent UI blocking
2. **Textual over Curses**: Textual provides better abstractions and components
3. **httpx over requests**: Native async support and SSE handling
4. **Local tool execution**: Maintains file system access like Claude Code
5. **Pydantic models**: Type safety for API responses and tool arguments

### Known Challenges
1. **SSE reliability**: Need robust reconnection logic
2. **Tool compatibility**: Must match Elixir tool behavior exactly
3. **Performance**: Python startup time vs compiled Elixir
4. **Distribution size**: Python runtime bundling increases executable size

### Testing Strategy
1. **Tool parity tests**: Compare output with Elixir tools
2. **API integration tests**: Mock server responses
3. **UI snapshot tests**: Textual's testing capabilities
4. **End-to-end tests**: Full flow from wizard to chat

### Security Considerations
1. **Path traversal**: Validate all file paths
2. **Command injection**: Sanitize shell commands
3. **API token**: Secure storage, never in logs
4. **File permissions**: Respect OS permissions

## Related Documents
- [Story — Termite TUI Port + Burrito Packaging.md](./Story%20—%20Termite%20TUI%20Port%20+%20Burrito%20Packaging.md)
- Original Elixir TUI: `clients/maestro_tui/`
- API Controllers: `lib/the_maestro_web/controllers/api/`
- LiveView Implementation: `lib/the_maestro_web/live/session_chat_live.ex`

## Questions & Decisions Needed

1. **Package name**: `maestro-tui` or `the-maestro-tui` for PyPI?
2. **Minimum Python version**: 3.10 or 3.11?
3. **Config file support**: Add `.maestrorc` for persistent settings?
4. **Plugin system**: Allow custom tools to be added?
5. **Telemetry**: Add usage analytics (opt-in)?

## Progress Tracking

```
Phase 1: Core Infrastructure     [          ] 0%
Phase 2: Local Tools             [          ] 0%
Phase 3: UI Components           [          ] 0%
Phase 4: Stream Processing       [          ] 0%
Phase 5: Advanced Features       [          ] 0%
Phase 6: Testing                 [          ] 0%
Phase 7: Packaging               [          ] 0%

Overall Progress:                [          ] 0%
```

---

*This story will be updated as implementation progresses. Each phase completion should include commit references and any deviations from the original plan.*
### Implementation Status (2025-09-28)
- Python Textual client scaffolding complete; config loader reads `~/.the_maestro/config.json`.
- API client covers providers/auths/models, sessions (create/list remote), turns, frames (SSE + latest), tool results, threads (list/create/rename).
- Added server endpoint `GET /api/threads/:thread_id/snapshot` to fetch canonical messages for transcript hydration.
- SSE handling merges `assistant_text` deltas into a single assistant message; `done` ignored; stream closes on `final`; empty `final` suppressed.
- UI:
  - Left panel shows remote sessions and a “New Session” wizard (Provider → Auth → Model).
  - Selecting a session loads its latest thread and renders the transcript.
  - Chat composer sends turns and appends collated messages to the transcript.

### Formatting & Rendering Decisions
- Transcript displays compact, role‑tagged lines; no raw frame dumps.
- Canonical snapshot messages may have `content` parts; renderer normalizes to plain text.
- Tool calls/results are summarized: `[tool:name] {args}` and trimmed previews.

### Server Internals
- Introduced `FramesController.snapshot/2` and route for transcript hydration.
- Refactored `Conversations.create_session/1` and `update_session/1` to use `Repo.transaction/1` instead of `Ecto.Multi` for Dialyzer clarity.
- Refactored System Prompts seeder to sequential transactions (no Multi).

### Follow‑ups
- Add retry/backoff + heartbeat handling for SSE reconnects.
- Add threads picker when multiple threads exist per session.
- Markdown rendering (code fences) and basic keybindings.

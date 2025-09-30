# TUI Usage and Deployment Guide

## Overview
The Maestro Python/Textual TUI connects to the server over HTTP/SSE and drives remote sessions (`tool_runtime = "remote"`). Local file and shell tools run on the client; model inference runs on the server.

## Prerequisites
- Server running (Phoenix app)
- Python 3.10+
- An API key created in the server UI

## 1) Start the Server
- Development: `MIX_ENV=dev mix phx.server`
- Test only: `MIX_ENV=test mix phx.server` (for env‑gated tests)

## 2) Create an API Key
- Visit `/api_keys`
- Click “New API Key”, enter a label
- Copy the plaintext token from the modal (it is shown once)

## 3) Configure the TUI
Create `~/.the_maestro/config.json`:

```
{ "api_host": "http://127.0.0.1:4000", "api_key": "<copied-token>" }
```

- `api_host` should resolve from the client machine
- `api_key` is the token created in step 2

## 4) Install and Run (dev)
- macOS/Linux
  - `cd clients/maestro_tui_python`
  - `python -m venv .venv && source .venv/bin/activate`
  - `pip install -e .[dev]`
  - Run: `python -m maestro_tui.app` or `maestro-tui`

- Windows PowerShell
  - `cd clients/maestro_tui_python`
  - `python -m venv .venv; .venv\\Scripts\\Activate.ps1`
  - `pip install -e .[dev]`
  - Run: `python -m maestro_tui.app` or `maestro-tui`

## 5) Packaging (PyInstaller)
Install explicitly; no auto‑installs.

- macOS/Linux
  - `cd clients/maestro_tui_python`
  - `python -m venv .venv && source .venv/bin/activate`
  - `pip install -e .[dev] pyinstaller`
  - `pyinstaller --clean -y pyinstaller.spec`
  - Binary: `dist/maestro-tui/maestro-tui`

- Windows PowerShell
  - `cd clients/maestro_tui_python`
  - `python -m venv .venv; .venv\\Scripts\\Activate.ps1`
  - `pip install -e .[dev] pyinstaller`
  - `pyinstaller --clean -y pyinstaller.spec`
  - Binary: `dist\\maestro-tui\\maestro-tui.exe`

## 6) Using the TUI
- Remote sessions list shows only sessions with `tool_runtime = "remote"`
- New Session wizard: Provider → Auth → Model
- Threads
  - Click “Threads” to pick a thread for the selected session
  - Snapshot hydrates transcript; latest turn streams over SSE
- Composer
  - Type and Enter to send a turn
  - Slash commands: `/help`, `/model`, `/threads`, `/clear`
- Hotkeys
  - Ctrl+Shift+N: New session
  - Ctrl+Shift+T: Threads picker
  - Ctrl+Shift+H: Help

## 7) Optional Integrations
- Tavily web search: set `TAVILY_API_KEY`
- Google CSE search: set `GOOGLE_CSE_ID` and `GOOGLE_API_KEY` (or `GOOGLE_CX`, `GOOGLE_CSE_API_KEY`)

## 8) Tests
- Server integration tests: `mix test`
- Python tests:
  - `cd clients/maestro_tui_python && source .venv/bin/activate`
  - `pytest -q`
  - Env‑gated (server required):
    - `TUI_API_BASE_URL=http://127.0.0.1:4000 TUI_API_TOKEN=<token> pytest -q -k 'sse_client or threads_env_integration or slash_env_integration'`

## 9) Troubleshooting
- 401 Unauthorized: create an API key and update `~/.the_maestro/config.json`
- SSE stuck: ensure server reachable from client; verify `api_host` and network
- Tool calls fail: ensure client has filesystem permissions and shell available
- Windows quoting: prefer `python -m maestro_tui.app` if `maestro-tui` is not on PATH

## 10) Security Notes
- API tokens are shown once; store securely
- Tokens are hashed in DB; revocation and rotation are available in `/api_keys`
- TUI stores config in the user’s home directory; restrict filesystem permissions

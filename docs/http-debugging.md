# HTTP Debugging & Streaming Tracing Guide

This guide explains how to turn on full-fidelity HTTP debug logging for all providers (Gemini, OpenAI, Anthropic), what gets logged, and how to capture the logs to a file for deep analysis.

The debug logger is provider‑agnostic and hooks into the shared streaming adapter, so every request, response, and (optionally) every SSE chunk is visible in one place.

## TL;DR (Quick Start)

```bash
# Enable logging (all providers)
export HTTP_DEBUG=1

# Choose detail level: low | medium | high | everything
# everything = also dumps every SSE chunk line-by-line
export HTTP_DEBUG_LEVEL=everything

# Optional: write all logs to a file (recommended for long sessions)
export HTTP_DEBUG_FILE="/Users/<you>/Development/the_maestro/gemini_api_flow.log"

# Run the app (or any script)
mix phx.server
# Or any of the E2E scripts below
```

With `HTTP_DEBUG_LEVEL=everything`, you will see:
- The full JSON request body for each call
- Sanitized headers (Authorization and similar are redacted)
- HTTP status + response headers
- Every SSE chunk exactly as the API streamed it

## Environment Variables

- `HTTP_DEBUG` (string):
  - `"1"|"true"|"TRUE"` → enable logging
  - unset/anything else → disable logging

- `HTTP_DEBUG_LEVEL` (string):
  - `low` → request method/URL + final status only
  - `medium` → + request/response headers
  - `high` (default) → + full JSON request bodies
  - `everything` → + raw SSE chunks (line-by-line)

- `HTTP_DEBUG_FILE` (string, optional):
  - Absolute path to a log file. When set, everything printed to stdout is also appended to this file.

Notes:
- Authorization and other sensitive headers are redacted.
- Request/response bodies are not truncated at any level.

## What Gets Logged

For every streaming request (all providers):

- Request
  - Method and URL
  - Sanitized headers
  - Full request body (JSON)

- Response
  - Status code and headers
  - For error responses (>= 400): full response body (decoded when possible)

- Streaming (when `HTTP_DEBUG_LEVEL=everything`)
  - Each SSE chunk is printed as it arrives

Example (Gemini OAuth):

```
[HTTP] POST https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse
Headers: {"authorization":"<redacted>","x-goog-api-client":"gl-node/20.19.4", ...}
Body:
{"model":"gemini-2.5-pro","project":"even-setup-7wxx5","request":{...},"user_prompt_id":"..."}
[HTTP] Status: 200
RespHeaders: {"content-type":"text/event-stream", ...}
[SSE CHUNK]: event: message\ndata: {"response":{...}}\n
[SSE CHUNK]: event: message\ndata: {"response":{...}}\n
...
```

## Provider‑Specific Notes

### Gemini (Personal OAuth)
- Endpoint: `cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse`
- Model is coerced to `gemini-2.5-pro` if an incompatible model is selected.
- System messages from your conversation are passed as `request.systemInstruction` (only if present). No hidden prompt injection is performed.

### OpenAI
- ChatGPT personal OAuth and API key streaming are both logged through the same adapter.
- Requests include the full JSON payload to `/v1/responses` or ChatGPT backend, plus streaming SSE chunks when `HTTP_DEBUG_LEVEL=everything`.

### Anthropic
- Claude streaming via the Messages API is logged in exactly the same way.

## E2E Scripts (Dev DB, No Mocks)

These scripts exercise the backend end‑to‑end without the UI and are handy for reproducing/debugging issues.

- Run a single Gemini OAuth turn:
  ```bash
  export HTTP_DEBUG=1 HTTP_DEBUG_LEVEL=everything
  mix run scripts/run_gemini_oauth_agent_loop.exs
  ```

- Create a new Gemini OAuth Agent + Session and stream a turn:
  ```bash
  export HTTP_DEBUG=1 HTTP_DEBUG_LEVEL=everything
  mix run scripts/test_gemini_agent_create_and_stream.exs
  ```

- Similar scripts exist for OpenAI/Anthropic (see `scripts/`).

## UI Debugging Tips

- Set the env vars before starting Phoenix: `mix phx.server`.
- With `HTTP_DEBUG_FILE` set, you can tail the log alongside the browser:
  ```bash
  tail -f /path/to/your.log | sed -n 'l'
  ```
- The UI path and the script path both go through the same streaming adapter, so you will see identical HTTP traces either way.

## Troubleshooting Checklist

- I see empty `"text":""` in `request.contents`: ensure we’re not re-normalizing provider messages. The current code automatically preserves preformatted Gemini `parts`.
- 404 NOT_FOUND for Gemini OAuth: ensure the model is `gemini-2.5-pro`. The code will coerce, but double-check the payload.
- 403 SERVICE_DISABLED for Gemini OAuth: do not send `x-goog-user-project` for personal OAuth; the current code does not. If you manually set it via proxies, remove it.
- No SSE deltas printed: set `HTTP_DEBUG_LEVEL=everything`.

## Security Notes

- Authorization and similar sensitive headers are redacted automatically.
- Request/response bodies may contain user text and internal IDs — treat logs as sensitive.
- Prefer writing to `HTTP_DEBUG_FILE` and rotating logs per session.

## Where the Code Lives

- Central logging logic: `lib/the_maestro/providers/http/streaming_adapter.ex`
- Logger utility: `lib/the_maestro/debug_log.ex`
- Gemini OAuth streaming: `lib/the_maestro/providers/gemini/streaming.ex`
- E2E runners: `scripts/run_gemini_oauth_agent_loop.exs`, `scripts/test_gemini_agent_create_and_stream.exs`

If you want additional per‑provider toggles, open an issue; the adapter makes it straightforward to add provider‑scoped filters.


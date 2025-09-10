# Golden HTTP Fixtures — Generation and Verification

This document explains how to generate and verify “golden” HTTP request fixtures
for the three providers using real API calls. These fixtures serve as a source of
truth for our request builders and help detect accidental drift.

## What This Covers

- Runs real sessions with your existing saved authentications
- Sends two mandatory turns per provider:
  1) `hello` — must answer and finalize
  2) `please list the files in your current directory` — must use tools and list files
- Captures exact outbound HTTP headers and JSON payloads as golden fixtures
- Provides an optional test to verify golden file presence/shape in CI

## Prerequisites

- Valid saved authentications (named sessions) already exist:
  - OpenAI (OAuth or API key): `personal_oauth_openai`
  - Anthropic (OAuth): `personal_oauth_claude`
  - Gemini (OAuth or API key): `personal_oauth_gemini`
- Your repo working directory is the project root (the generator uses it as the
  workspace for file-listing tools).
- Network connectivity (this uses live provider APIs).

Notes
- No tokens are written to fixtures. Debug logging sanitizes auth headers; raw
  tokens are not stored in fixture files.
- The generator enforces success criteria and aborts on failure.

## Generate Golden Fixtures

Run for any subset or all providers:

- OpenAI only:
  ```bash
  mix golden.gen --openai personal_oauth_openai
  ```
- Anthropic only:
  ```bash
  mix golden.gen --anthropic personal_oauth_claude
  ```
- Gemini only:
  ```bash
  mix golden.gen --gemini personal_oauth_gemini
  ```
- All three in one run:
  ```bash
  mix golden.gen \
    --openai personal_oauth_openai \
    --anthropic personal_oauth_claude \
    --gemini personal_oauth_gemini
  ```

What it enforces per provider
- Turn 1 (`hello`):
  - Finalizes (no error events)
  - Produces non-empty content
- Turn 2 (`please list the files in your current directory`):
  - Calls a shell-like tool (`shell`, `Bash`, `run_shell_command`, or `list_directory`)
  - Finalizes (no error events)
  - Output “looks like” a directory listing (heuristics: presence of items like
    `mix.exs`, `lib/`, `deps/`, `.gitignore`, `README.md`, `drwx`, or `total `)

If any condition fails, the task raises and stops.

## Output Artifacts

For each provider `<p> ∈ {openai, anthropic, gemini}`:

- Log: `priv/golden/<p>/capture.log`
- Fixtures (JSON): `priv/golden/<p>/request_fixtures.json`

Fixture format
```json
[
  {
    "headers": {"accept": "text/event-stream", "content-type": "application/json", ...},
    "body": {"model": "...", "input": [...], "tools": [...], ...}
  },
  {
    "headers": { ... },
    "body": { ... }
  }
]
```
There may be more than two entries if the provider performs follow-up requests.

## Verifying Fixtures in CI

- Optional test exists and is disabled by default. Enable it with:
  ```bash
  RUN_GOLDEN=1 mix test --only golden
  ```
- The test checks that fixture files exist (if present) and are parseable with
  expected top-level keys (`headers`, `body`). It does not do live network calls.

Recommended flow
1) Generate fixtures locally using `mix golden.gen` (live network).
2) Commit `priv/golden/**` files.
3) On CI, enable the verify test (e.g., `RUN_GOLDEN=1`) to guard presence/shape.

## Keeping Fixtures Fresh

Regenerate when any of the below occurs:
- You change request builder code (headers, payload shape, tool exposure).
- Providers change required headers or fields.
- You rotate credentials or rebind sessions.

Command to regenerate (example for OpenAI):
```bash
rm -rf priv/golden/openai && \
  mix golden.gen --openai personal_oauth_openai
```
Repeat per provider as needed.

## Troubleshooting

- “No saved_authentication for <provider>/<name>”
  - Ensure the named session exists (`saved_authentications` row). Re-run your
    OAuth flow or set API keys.

- “Turn failed: provider returned error events”
  - Check provider availability, token validity, and network. Re-run once stable.

- “Second turn did not use tools as required” or listing doesn’t look like files
  - Ensure `shell` tool is exposed for the provider (OpenAI responses tools include
    `shell`). Gemini/Anthropic must surface tool calls through the streaming
    manager; verify tool registration and follow-up logic.

- Anthropic refresh errors in logs (client_id missing)
  - Ensure Anthropic OAuth config is present and valid if you’re testing Anthropic.

## Notes on Scope

- The generator enforces mandatory behaviors you requested for confidence:
  - “hello” must answer and finalize
  - “list files” must use tools and return a credible listing
- The verify test is intentionally light (format only). If you want strict, per-
  field comparisons (ignoring dynamic fields like `session_id`), ask to add a
  golden comparator that asserts exact matches against current builders.


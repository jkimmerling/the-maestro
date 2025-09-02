# Provider Architecture

This document summarizes the universal provider architecture implemented in Epic 0.

- Single entrypoint: `TheMaestro.Provider`
  - `create_session(provider, auth_type, opts)` → `{:ok, session_id}`
  - `list_models(provider, auth_type, session_id)` → `{:ok, [Model.t()]}`
  - `stream_chat(provider, session_id, messages, opts)` → `{:ok, stream}`

Provider-specific modules live under `TheMaestro.Providers.*` and implement behaviours
for OAuth/APIKey, Streaming, and Models. HTTP access is standardized on Req + Finch.

Named sessions are persisted via `TheMaestro.SavedAuthentication` and support both OAuth and API key flows.


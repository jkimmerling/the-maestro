# Migration Guide: Legacy Auth → Universal Providers

This guide describes how to migrate from any legacy `Auth.*` entrypoints to the
unified `TheMaestro.Provider` API.

- Replace direct OAuth helpers with:
  - `TheMaestro.Provider.create_session(:<provider>, :oauth, name: ..., auth_code: ..., pkce_params: ...)`
- Replace API calls using bespoke modules with:
  - `TheMaestro.Provider.stream_chat/4` and `TheMaestro.Provider.list_models/3`

No public legacy auth modules remain; internal utility `TheMaestro.Auth` continues
to support provider implementations. If you still reference removed helpers,
port to `TheMaestro.Provider` using the examples in `docs/api/provider-interface.md`.


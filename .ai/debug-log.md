# Dev Debug Log

- 2025-09-02: Completed Story 0.6 Task 1.1 legacy module assessment (no legacy auth dirs present; `TheMaestro.Auth` retained as shared utility). Verified Tesla fully removed in favor of `Req` + `Finch` (Task 1.2). Added unified OpenAI OAuth streaming E2E script at `scripts/test_full_openai_oauth_streaming_e2e.exs`.
- 2025-09-02: Removed legacy OAuth helper scripts; added Gemini OAuth E2E; added provider switching, streaming consistency, and model listing scripts (AC-2).
- 2025-09-02: Added performance benchmarks and reliability scripts (AC-3); added production readiness orchestrator and architecture/API docs + migration utilities (AC-4). Addressed Credo/Dialyzer warnings in ReqClientFactory.

# Chat Timeline API (proposed)

- GET `/api/sessions/:id/turn` — start a turn (existing). Response includes `frames_topic` string for PubSub subscription: `turn:<session_id>:<stream_id>`.
- GET `/api/threads/:thread_id/turns/:turn_index/frames` — returns `[{id, idx, at_ms, role, kind, payload, thought?, collapsed?}]` for a specific turn (to be implemented).
- GET `/api/threads/:thread_id/turns/latest/frames` — latest turn frames (to be implemented).

Notes:
- Feature flag `:chat_full_timeline` gates write/publish of frames.
- Backfill for legacy entries TBD.

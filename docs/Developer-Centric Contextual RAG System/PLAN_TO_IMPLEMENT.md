# Plan to Implement: Developer‑Centric Contextual RAG + Long‑Term Context Storage

Status: Draft v0.2 (2025-09-06) — maestro-focused, awaiting a few specifics

Owner: The Maestro (LLM agent framework under `lib/the_maestro`)

Purpose: Define an iterative plan to design, implement, and integrate the Contextual RAG system and long‑term context storage with Maestro’s existing agentic framework so in‑app LLM agents reliably leverage project knowledge, persistent memory, and contextual retrieval during work.

References
- PRD: docs/Developer-Centric Contextual RAG System/RAG-PRD.md
- Maestro codebase: lib/the_maestro/*, lib/the_maestro_web/*

## 1) Objectives (Maestro‑specific)
- Integrate Contextual RAG and Long‑Term Memory directly into Maestro’s existing agentic framework:
  - Augment LLM turns (OpenAI/Anthropic/Gemini) with hybrid RAG context packs and citations.
  - Provide persistent, developer‑centric memory (decisions, fixes, conventions) implemented as a first‑class MCP‑style tool inside the Elixir app.
  - Store memories in Postgres (FKs to conversations/sessions/agents) and mirror relationships in Neo4j for linking to code artifacts (commits/diffs/files).
  - Use pgvector in the existing Postgres for embeddings and retrieval; GPU‑backed local embeddings via Ollama on home network.
  - Minimize UI friction: keep current LiveView chat flow; add provenance panel and toggles.

## 2) Constraints & Non‑Goals
- Target is Maestro app only (no BMAD integration for now).
- Archon is not part of the system and should be removed/ignored.
- Use Postgres (existing) + pgvector for vectors; Neo4j CE for graph linking.
- No additional security/redaction requirements were specified.
- Success measured by developer outcomes (improved code quality, fewer failing tests).

## 3) Confirmed Inputs
- Agent scope/runtime: Integrate into Maestro’s in‑app agents (`lib/the_maestro/*`); this PRD is for the existing AI‑driven software dev framework already present.
- Data sources: No constraints on sources (repos, wikis, tickets, URLs); authenticated sources allowed.
- Embeddings: Use GPU via Ollama on home network server.
- Vector DB: Postgres with pgvector (reuse existing DB instance).
- Graph DB: Neo4j Community Edition.
- Memory: Build MCP‑style memory inside the Elixir app; persist in Postgres with FKs; mirror/link in Neo4j (to commits/diffs/codebase).
- LLMs: Default to local Ollama when desired; cloud providers supported; no provider constraints.
- Telemetry: Store metrics in Postgres.
- Deployment: Dev—RAG backend runs in Docker, exposed to host; Elixir app on host talks to it. Prod—Elixir app and all services in Docker.
- Success: Improved code quality and fewer failing tests.

## 4) High‑Level Architecture (Maestro)
- Ingestion/Retrieval Service (container):
  - Python (FastAPI) or Elixir (separate OTP app) service responsible for parsing sources, contextual chunking, contextual BM25 text, embeddings via Ollama, hybrid retrieval, and ranking.
  - Persists chunks + embeddings in Postgres (pgvector) and writes graph edges to Neo4j (Document→Chunk, Chunk↔FilePath, Chunk→Commit, etc.).
- Memory Service (inside Elixir app):
  - MCP‑style tool methods: `memory.read`, `memory.write`, `memory.link`, `memory.stats` implemented as Phoenix routes or internal handlers callable by provider tool turns.
  - Stores memories in Postgres with FKs to `sessions`, `agents`, and optionally `chat_history` rows; mirrors key relations in Neo4j for multi‑hop linking to code artifacts.
- Agent Turn Augmentation:
  - Expose new tool functions to LLMs (OpenAI Responses, Anthropic Tools) for `rag.query`, `rag.feedback`, `memory.read`, `memory.write`.
  - Extend `AgentLoop` and LiveView streaming tool execution to handle these tools and perform HTTP calls (Req) to RAG service and DB writes for memory.
- UI/UX (LiveView):
  - Add a collapsible “Context & Citations” panel per assistant turn; display source titles, file paths, commit hashes, and confidence.
  - Add toggle to include/exclude RAG for a given session; show memory hits applied.

Data flow summary
1) User posts message → Provider streams tool calls → On `rag.query`, Elixir calls RAG service; receives Context Pack + citations → LLM completes with grounded answer.
2) On corrections/feedback, LLM calls `memory.write` (and optionally `rag.feedback`); Maestro persists memory in Postgres and links in Neo4j; optionally triggers incremental re‑index.
3) Subsequent turns call `memory.read` with scoped filters (by session/agent/topic) to inject prior decisions/fixes.

## 5) Maestro Integration Points
- Streaming Providers
  - OpenAI Responses: extend `lib/the_maestro/providers/openai/streaming.ex` `responses_tools()` to include new function tools: `rag_query`, `rag_feedback`, `memory_read`, `memory_write` (JSON schemas below).
  - Anthropic Tools: extend `lib/the_maestro/providers/anthropic/streaming.ex` tools list accordingly with `tool_use` schemas; wire `stream_tool_followup` to handle results.
- Tool Execution (Elixir)
  - Extend `TheMaestro.AgentLoop` and `TheMaestroWeb.SessionChatLive.run_pending_tools_and_follow_up/2` to execute the new tools:
    - `rag_query` → HTTP POST to RAG service `/query` with current session context (working_dir, git sha/branch, changed files, latest user text) → returns a compact Context Pack with citations and debug plan. Return payload JSON to model.
    - `rag_feedback` → POST `/feedback` with context_pack_id, verdict, notes.
    - `memory_write` → insert into Postgres (memories table) with scope and payload; mirror to Neo4j edges (e.g., MEMORY→COMMIT, MEMORY→FILE). Return `{memory_id}`.
    - `memory_read` → query by scope/tags/text; return compact items to inject.
- LiveView Chat
  - Render a “Context & Citations” card on assistant messages when a Context Pack was used (include file paths, commit hashes, source types, token count).
  - Session‑level toggle: enable/disable RAG; show memory hits count.

## 6) APIs and Contracts (Maestro view)
- RAG Service (container; HTTP; called via Req)
  - `POST /ingest` → {sources:[{type:"git|fs|url|doc", uri|path, auth?}], opts:{rechunk, reembed, schedule?}} → {job_id, stats}
  - `POST /query` → {session_id, agent_id, query, k?, rerank?, working_dir?, git:{sha?, branch?, changed_files?}} → {context_pack:{id, tokens, chunks:[{id, text, score, source, path, sha, line_range}]}, citations:[{path|url, sha?, score}], debug:{plan, timings}}
  - `POST /feedback` → {context_pack_id, verdict:"useful|partial|wrong", notes} → {ok}
- Memory Tool (inside Elixir; callable as tool functions)
  - `memory.write` → {scope:{session_id, agent_id, repo?, files?[], commit_sha?}, type, payload, tags?[]} → {memory_id}
  - `memory.read` → {scope, filter:{type?, tags?[], text?}, limit?} → {items:[{id, type, payload, created_at}]}
  - `memory.link` → {memory_id, related:{file_path?|commit_sha?|context_pack_id?}, relation} → {ok}
  - `memory.stats` → {scope} → {counts, last_write_at}

Tool JSON schemas (summary)
- `rag_query` (function):
  - params: {query:string, files?:[string], prefer_graph?:bool, k?:int, rerank?:bool}
- `rag_feedback` (function):
  - params: {context_pack_id:string, verdict:string, notes?:string}
- `memory_write` (function):
  - params: {scope:object, type:string, payload:object, tags?:[string]}
- `memory_read` (function):
  - params: {scope:object, filter?:{type?:string,tags?:[string],text?:string}, limit?:int}

## 7) Research (pre‑implementation)
- Validate contextual chunking and BM25+embedding hybrid configs for pgvector (IVFFlat/HNSW) and best K/chunk sizes for code/doc mixtures.
- Neo4j schema patterns for linking memories to commits/diffs/files and chunks.
- Ollama embedding models (e.g., BGE‑M3, nomic‑embed‑text) performance on code snippets; confirm availability on target server.
- Phoenix v1.8 integration patterns (Req, async tasks, backpressure) for calling containerized services.

## 8) Phased Delivery Plan (Maestro)
- Phase 0 — Alignment (this doc)
  - Confirm allowed service split (RAG container + Maestro Elixir memory).
  - Confirm Ollama host/port and Postgres/Neo4j connection details.
- Phase 1 — DB & Schema Foundations
  - Postgres: enable pgvector; create tables: `rag_documents`, `rag_chunks` (with `embedding vector`), `rag_ingest_jobs`, `memories`, `memory_tags`, `memory_links`, `rag_metrics`.
  - Neo4j: establish base labels and indexes: `(:Document)`, `(:Chunk)`, `(:Memory)`, `(:Commit)`, `(:File)`; rels: `CONTAINS`, `REFERENCES`, `CORRECTS`, `INTRODUCED_IN`, `MODIFIES_FILE`, `RELATES_TO`.
- Phase 2 — RAG Service (container)
  - Implement ingestion (fs/git/url/doc) with contextual chunking; embeddings via Ollama; persistence to Postgres + Neo4j.
  - Implement `/query` hybrid retrieval with contextual BM25 + vector search + light re‑rank; return compact context pack; `/feedback` endpoint.
  - Provide Dockerfile and Compose entry; expose port to host.
- Phase 3 — Maestro Memory (Elixir)
  - Implement MCP‑style `memory.*` tool handlers; Ecto schemas/migrations; Neo4j mirroring.
  - Add `TheMaestro.Tools.Memory` executor.
- Phase 4 — Provider Tooling & Turn Wiring
  - Add tool schemas to OpenAI/Anthropic streaming modules; extend tool execution in `SessionChatLive.run_pending_tools_and_follow_up/2` and `AgentLoop`.
  - Add Req clients to call RAG service; error handling, timeouts, retries.
- Phase 5 — UI/UX
  - Display citations/context; RAG toggle; memory hit badges; basic inspection of debug retrieval plan.
- Phase 6 — Hardening & Evaluation
  - Metrics to Postgres (`rag_metrics`): latency per stage, context token size; rolling eval set based on recent failing tests.
  - Caching of frequent context packs; background re‑embed jobs.

## 9) Security & Ops
- Environment‑driven endpoints and credentials (`RAG_BASE_URL`, `OLLAMA_BASE_URL`, `NEO4J_URI`, `NEO4J_AUTH`, `DATABASE_URL`).
- No special redaction policy requested; keep logs minimal; avoid storing secrets in memory payloads.
- Add health checks for RAG service and Neo4j connectivity.

## 10) Metrics & Success Signals
- Primary: fewer failing tests over time in active repos; faster fix throughput per failing test.
- Supporting: median retrieval end‑to‑end ≤ 2.5s locally; context tokens kept under configured cap; memory writes succeed ≥99%.

## 11) Next Actions
- Provide the following details to finalize v0.3 planning:
  - Ollama endpoint (host:port) reachable from the RAG container.
  - Postgres DSN (same DB as Maestro?) and pgvector extension status.
  - Neo4j CE connection (bolt URI+auth) and persistence volume path.
  - Preferred language for RAG service (Python vs. Elixir). If Python, confirm allowance for Unstructured/Playwright for ingestion.
- I will then add concrete migration names, table schemas, tool JSON schemas, and a dated milestone schedule.

# Product Roadmap

## Phase 1: Foundation & Core Agent Engine

**Goal:** Establish the foundational OTP application, core ReAct agent logic, single LLM provider connection, and metaprogramming DSL for tools
**Success Criteria:** Functional backend engine that can hold conversations, connect to LLM, and use basic secure tools with comprehensive test coverage

### Features

- [ ] Integrate Code Quality Tooling - Configure mix format, Credo, and CI pipeline `S`
- [ ] Core Application & Supervision Tree - Basic OTP app with dynamic supervisor for agent processes `M`
- [ ] Agent State Management & ReAct Loop - GenServer-based conversation state with basic ReAct structure `L`
- [ ] LLMProvider Behaviour & Gemini Adapter - Model-agnostic behaviour with concrete Gemini implementation `L`
- [ ] Tooling DSL & Sandboxed File Tool - Metaprogramming DSL with secure file reading tool `L`
- [ ] Epic Demo & Documentation - Runnable demo and comprehensive tutorials `M`

### Dependencies

- Elixir/Phoenix project initialization
- Gemini API access and credentials
- Testing framework setup

## Phase 2: Phoenix LiveView UI & User Authentication

**Goal:** Implement real-time web interface and secure authentication supporting both single-user and multi-user modes
**Success Criteria:** Full web UI with streaming responses, configurable OAuth, and CLI device authentication flow

### Features

- [ ] Phoenix Integration & Basic Layout - Add Phoenix framework with foundational web structure `M`
- [ ] Configurable Web Authentication - Google OAuth with single-user/multi-user mode configuration `L`
- [ ] Main Agent LiveView Interface - Real-time chat interface with agent process integration `L`
- [ ] Streaming & Status Updates - Word-by-word response streaming with tool execution visibility `L`
- [ ] CLI Device Authorization Backend - API endpoints for terminal-based authentication flow `M`
- [ ] Epic Demo & Documentation - Web application demo with authentication scenarios `S`

### Dependencies

- Phase 1 completion (core agent engine)
- Google OAuth application setup
- Phoenix LiveView dependencies

## Phase 3: Advanced Agent Capabilities & Tooling

**Goal:** Expand agent capabilities with multi-provider LLM support, comprehensive sandboxed tools, and session persistence
**Success Criteria:** Production-ready agent with multiple LLM providers, secure tool execution, and full session management

### Features

- [ ] OpenAI & Anthropic LLM Adapters - Multi-provider support with flexible authentication methods `L`
- [ ] Full File System Tool Suite - Complete file operations (read/write/list) with security validation `M`
- [ ] Sandboxed Shell Command Tool - Docker-based secure shell execution with bypass configuration `XL`
- [ ] OpenAPI Integration Tool - Dynamic API client generation and execution from OpenAPI specs `L`
- [ ] Conversation Checkpointing - Save/restore complete session state with full message history `M`
- [ ] Epic Demo & Documentation - Multi-provider showcase with advanced tool usage `M`

### Dependencies

- Phase 2 completion (web interface)
- OpenAI and Anthropic API access
- Docker setup for shell sandboxing
- Database schema for session persistence

## Phase 4: Terminal User Interface (TUI)

**Goal:** Create feature-complete terminal interface as alternative interface to the core agent system
**Success Criteria:** Full CLI experience with authentication, streaming responses, and tool visibility matching web interface capabilities

### Features

- [ ] TUI Framework Integration - Basic terminal interface with ratatouille framework `M`
- [ ] Configurable TUI Authentication - Device flow integration with anonymous mode support `M`
- [ ] Agent Interaction Loop - Terminal-based conversation with streaming response handling `L`
- [ ] Tool Status Display - Real-time tool execution feedback in terminal interface `M`
- [ ] Epic Demo & Documentation - Complete CLI usage guide and demonstration `S`

### Dependencies

- Phase 3 completion (advanced capabilities)
- Terminal UI library integration
- CLI authentication flow from Phase 2

## Phase 5: Production Hardening & Enterprise Features

**Goal:** Production-ready deployment, monitoring, enterprise authentication, and advanced security features
**Success Criteria:** Self-hostable system with enterprise SSO, comprehensive monitoring, and advanced security controls

### Features

- [ ] Docker Compose Production Setup - Complete containerized deployment with environment management `M`
- [ ] Enterprise Authentication - Google Cloud service accounts and Vertex AI integration `L`
- [ ] Advanced Security Controls - Enhanced sandboxing, audit logging, and permission management `L`
- [ ] System Monitoring & Health Checks - Application metrics, health endpoints, and observability `M`
- [ ] Multi-Modal Content Processing - Enhanced PDF, image, and document processing capabilities `L`
- [ ] Performance Optimization - Caching, connection pooling, and resource optimization `M`

### Dependencies

- Phase 4 completion (TUI)
- Production infrastructure requirements
- Enterprise authentication setup
- Monitoring and observability tools
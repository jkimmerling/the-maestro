# Technical Stack

## Core Application Framework
- **Application Framework:** Phoenix ~> 1.8
- **Backend Language:** Elixir ~> 1.17
- **Runtime:** Erlang/OTP 26

## Database & Data
- **Database System:** PostgreSQL 16
- **ORM/Database Client:** Ecto ~> 3.11

## Frontend & UI
- **Frontend Framework:** Phoenix LiveView ~> 0.20
- **JavaScript Strategy:** Minimal JS with LiveView
- **CSS Framework:** Tailwind CSS ~> 3.4
- **UI Component Library:** Phoenix LiveView Components
- **Import Strategy:** esbuild (built-in with Phoenix)

## Authentication & Security
- **Web Authentication:** Ueberauth (Google) ~> 0.10
- **Cloud Authentication:** Goth ~> 1.3 (for Google Cloud/Vertex AI and LLM provider OAuth)
- **Authorization:** Built-in Phoenix session management

## LLM Integrations
- **Gemini Client:** gemini_ex ~> 0.2
- **OpenAI Client:** openai_ex ~> 0.9
- **Anthropic Client:** anthropix ~> 0.6

## Terminal Interface
- **TUI Framework:** ratatouille ~> 0.3

## Development & Testing
- **Testing Framework:** ExUnit (built-in)
- **Property Testing:** StreamData ~> 0.6
- **Code Quality:** Credo ~> 1.7
- **Code Formatting:** mix format (built-in)
- **Browser Testing:** Wallaby (for E2E tests)
- **Mocking:** Mox (for unit tests)

## Infrastructure & Deployment
- **Containerization:** Docker
- **Orchestration:** Docker Compose
- **Deployment Solution:** Self-hosted via Docker Compose
- **Application Hosting:** User-provisioned local machine/server
- **Database Hosting:** PostgreSQL container in Docker Compose
- **Asset Hosting:** Phoenix static assets served by application

## External Services
- **Search Integration:** Google Search API
- **File System:** Local file system with sandboxing
- **Shell Execution:** Local shell with Docker sandboxing
- **API Integration:** Dynamic OpenAPI client generation

## Development Tools
- **Version Control:** Git
- **Code Repository:** Local/Private repository
- **CI/CD:** GitHub Actions (for code quality checks)
- **Environment Management:** Docker Compose
- **Secrets Management:** Environment variables with Docker secrets

## Fonts & Icons
- **Fonts Provider:** System fonts with web font fallbacks
- **Icon Library:** Heroicons (integrated with Phoenix LiveView)

## Architecture Patterns
- **Application Pattern:** Phoenix Context pattern
- **State Management:** OTP GenServer processes
- **Extensibility:** Elixir behaviours for LLM providers and tools
- **DSL:** Metaprogramming for tool definition
- **Error Handling:** Tagged tuples with structured error types
- **Supervision:** OTP supervision trees for fault tolerance
# The Maestro

An Elixir-based AI agent replication system targeting developers who need robust, fault-tolerant AI agents with model-agnostic architecture. The Maestro provides superior reliability through OTP supervision, comprehensive tool sandboxing, and production-ready multi-user capabilities with flexible authentication strategies.

## Features

- **Fault-Tolerant Architecture**: Built on Elixir/OTP for inherent fault tolerance and supervision
- **Model-Agnostic Design**: Supports multiple LLM providers (Gemini, OpenAI, Anthropic) through behaviour-based adapters
- **Real-Time Web Interface**: Phoenix LiveView-based UI with streaming responses and tool execution status
- **Flexible Authentication**: Configurable single-user or multi-user modes with Google OAuth support
- **Comprehensive Tooling**: Sandboxed file system, shell command execution, and OpenAPI integration
- **Session Management**: Save and restore conversation checkpoints
- **Terminal Interface**: Rich CLI/TUI for command-line workflows
- **Production Ready**: Comprehensive testing, code quality enforcement, and CI/CD integration

## Quick Start

### Prerequisites

- Elixir 1.17+ and Erlang/OTP 26+
- PostgreSQL 16+
- Node.js (for asset compilation)

### Setup

1. **Clone and setup the project**
   ```bash
   git clone <repository-url>
   cd the_maestro
   mix setup
   ```

2. **Configure environment variables** (optional for single-user mode)
   ```bash
   cp .env.example .env
   # Edit .env with your API keys and configuration
   ```

3. **Start the development server**
   ```bash
   mix phx.server
   ```

4. **Visit the application**
   Navigate to [`localhost:4000`](http://localhost:4000) in your browser.

## Development

### Code Quality

This project enforces code quality through automated tools:

- **Formatting**: `mix format` (configured via `.formatter.exs`)
- **Linting**: `mix credo --strict` (configured via `.credo.exs`)
- **Testing**: `mix test`

Run all quality checks:
```bash
mix format --check-formatted
mix credo --strict
mix test
```

### Project Structure

```
lib/
├── the_maestro/           # Core business logic contexts
├── the_maestro_web/       # Phoenix web interface
config/                    # Application configuration
test/                      # Test files
demos/                     # Runnable demonstrations
tutorials/                 # Educational content
```

### Running Demos

Each epic includes a runnable demonstration:
```bash
# Run Epic 1 demo
cd demos/epic1/
mix run demo.exs
```

## Architecture

The Maestro is built using several key architectural patterns:

- **Phoenix Contexts**: Domain logic organization
- **OTP GenServer Processes**: Per-user session state management
- **Behaviours**: Model-agnostic LLM provider and tool interfaces
- **Supervision Trees**: Automatic fault recovery
- **LiveView**: Real-time web interface

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the quality checks: `mix format && mix credo --strict && mix test`
5. Submit a pull request

## License

[Your chosen license]

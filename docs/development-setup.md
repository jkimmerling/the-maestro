# Development Setup

## Prerequisites

- Elixir 1.17+
- Erlang/OTP 26+
- Docker (for PostgreSQL)

## Database Setup

The application requires PostgreSQL for development and testing. We use Docker to run PostgreSQL locally:

### Start PostgreSQL Container

```bash
docker run --name the_maestro_postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=the_maestro_test \
  -p 5432:5432 \
  -d postgres:16
```

### Create Database

```bash
mix ecto.create
```

### Stop PostgreSQL Container

```bash
docker stop the_maestro_postgres
```

### Start Existing Container

```bash
docker start the_maestro_postgres
```

### Remove Container (if needed)

```bash
docker rm -f the_maestro_postgres
```

## Running Tests

```bash
# Run all tests
mix test

# Run specific test files
mix test test/the_maestro/agents*

# Run with coverage
mix test --cover
```

## Code Quality

```bash
# Format code
mix format

# Run static analysis
mix credo

# Check formatting
mix format --check-formatted

# Run strict credo checks
mix credo --strict
```

## Development Workflow

1. Start PostgreSQL container (see above)
2. Create/migrate database: `mix ecto.create && mix ecto.migrate`
3. Install dependencies: `mix deps.get`
4. Run tests: `mix test`
5. Start application: `mix phx.server`

## Project Structure

```
lib/
├── the_maestro/
│   ├── agents/                 # Agent context
│   │   ├── agent.ex           # Agent GenServer
│   │   └── dynamic_supervisor.ex  # Agent supervisor
│   ├── agents.ex              # Agents context API
│   └── application.ex         # OTP Application
└── the_maestro_web/           # Phoenix web layer

test/
└── the_maestro/
    ├── agents/
    │   ├── agent_test.exs
    │   └── dynamic_supervisor_test.exs
    └── agents_test.exs
```
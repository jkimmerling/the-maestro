# Elixir Gemini CLI Replication Fullstack Architecture Document

## Introduction

This document outlines the complete fullstack architecture for the Elixir Gemini CLI Replication project, including backend systems, frontend implementation, and their integration. It serves as the single source of truth for AI-driven development, ensuring consistency across the entire technology stack.

This unified approach combines what would traditionally be separate backend and frontend architecture documents, streamlining the development process for modern fullstack applications where these concerns are increasingly intertwined.

### Starter Template or Existing Project

N/A - Greenfield project. The project is being built from scratch, though it will be initialized with a standard `mix new` structure as a baseline. No external starter templates will be used.

### Change Log

|   |   |   |   |
|---|---|---|---|
|**Date**|**Version**|**Description**|**Author**|
|August 11, 2025|1.0|Initial Architecture Draft|Winston (Architect)|

## High Level Architecture

### Technical Summary

This architecture describes a robust, real-time, full-stack application built on a modern Elixir/Phoenix stack. The system is designed as a standard monolithic repository for optimal tooling support and developer experience. The core of the application is a decoupled OTP-based agentic engine responsible for state management and executing the ReAct reasoning loop. This engine communicates with a rich, real-time frontend built with Phoenix LiveView. The architecture is explicitly designed to be model-agnostic and extensible through the use of Elixir behaviours, supporting multiple LLM providers and a flexible, secure tooling system.

### **(updated)** Platform and Infrastructure Choice

Based on the PRD's requirements for a self-hostable and portable solution, the platform will be built on **Docker Compose**.

- **Platform:** Self-hosted via Docker Compose.
    
- **Rationale**: This approach provides a consistent, reproducible environment for both local development and production deployment. It allows all necessary services (the Phoenix application, a PostgreSQL database, etc.) to be defined and managed in a single `docker-compose.yml` file, ensuring parity between environments and simplifying setup for new developers. This aligns perfectly with the goal of creating a locally-hosted application.
    
- **Key Services:** The Phoenix Application (as a Docker service), PostgreSQL (as a Docker service), and any other required backing services.
    
- **Deployment Host and Regions:** User-provisioned local machine or server.
    

### Repository Structure

The project will use a **Monorepo** structure managed as a standard "poncho" application.

- **Structure:** Monorepo
    
- **Rationale**: As defined in the PRD, this approach provides the best tooling support in the Elixir ecosystem. It simplifies dependency management and allows for easy code sharing between the core application and the Phoenix web interface, which will live inside the same repository.
    

### High Level Architecture Diagram

```
graph TD
    subgraph User's Local Machine / Server
        subgraph Docker Compose Environment
            B[Phoenix LiveView App];
            G[PostgreSQL Service];
        end

        A[User via Browser] --> B;
        B -- WebSocket --> C{Agent Supervisor};
        C -- starts/supervises --> D[Agent GenServer];
        D -- reads/writes --> G;
    end


    subgraph Core Application Logic (within Phoenix App)
      C -- manages --> D
    end


    subgraph External Systems
        D -- calls --> E[LLMProvider Behaviour];
        D -- calls --> F[Tool Behaviour];

        E --> H[Gemini API];
        E --> I[OpenAI API];
        E --> J[Anthropic API];

        F --> K[Local File System];
        F --> L[Local Shell];
        F --> M[External OpenAPI Services];
    end

    style B fill:#90EE90
    style D fill:#ADD8E6
```

### Architectural Patterns

- **Phoenix Context Pattern:** The core application logic will be organized into contexts (e.g., `Accounts`, `Agents`, `Tooling`) to create clear domain boundaries and a well-defined internal API.
    
    - _Rationale:_ This is the standard for building maintainable Phoenix applications, ensuring the core logic is decoupled from the web layer.
        
- **OTP GenServer per Session:** Each user conversation will be managed by its own isolated, supervised `GenServer` process.
    
    - _Rationale:_ This leverages OTP's core strength for fault-tolerant, concurrent state management, ensuring that an error in one user's session cannot affect others.
        
- **Behaviour-based Adapters (Strategy Pattern):** The system will use Elixir `behaviours` to define contracts for external services like LLM providers and internal capabilities like Tools.
    
    - _Rationale:_ This makes the system highly extensible and model-agnostic, fulfilling a key non-functional requirement.
        
- **Metaprogramming for DSLs:** A Domain-Specific Language (DSL) will be created using Elixir macros to provide a clean, declarative way to define new tools.
    
    - _Rationale:_ This reduces boilerplate and improves the developer experience when extending the agent's capabilities.
        

## Tech Stack

### Technology Stack Table

|   |   |   |   |   |
|---|---|---|---|---|
|**Category**|**Technology**|**Version**|**Purpose**|**Rationale**|
|**Backend Language**|Elixir|~> 1.17|Core application language|Leverages OTP for concurrency and fault tolerance, ideal for agentic systems.|
|**Web Framework**|Phoenix|~> 1.8|Web server and application structure|Provides a robust, productive foundation for Elixir web applications.|
|**Real-time UI**|Phoenix LiveView|~> 0.20|Primary web user interface|Optimal for stateful, real-time applications; minimizes client-side JS.|
|**Database**|PostgreSQL|16|Primary data persistence|A powerful, reliable, and well-supported relational database.|
|**DB Client / ORM**|Ecto|~> 3.11|Database interaction and queries|The standard for data mapping in Elixir, providing safe and composable queries.|
|**Styling**|Tailwind CSS|~> 3.4|UI styling and design system|A utility-first CSS framework that integrates seamlessly with Phoenix.|
|**Web Auth**|Ueberauth (Google)|~> 0.10|Web UI Google OAuth2 flow|A flexible, standard library for authentication in Elixir.|
|**Vertex AI Auth**|Goth|~> 1.3|Backend Google Cloud auth|The standard for managing Google Cloud service account credentials.|
|**Gemini Client**|`gemini_ex`|~> 0.2|LLM adapter for Google Gemini|A modern client with full support for Gemini features and auth methods.|
|**OpenAI Client**|`openai_ex`|~> 0.9|LLM adapter for OpenAI|A comprehensive, community-maintained client for the OpenAI API.|
|**Anthropic Client**|`anthropix`|~> 0.6|LLM adapter for Anthropic|A modern client for the Anthropic Claude API.|
|**TUI Framework**|`ratatouille`|~> 0.3|Terminal User Interface|A promising TUI library based on The Elm Architecture, which maps well to OTP.|
|**Code Quality**|Credo|~> 1.7|Static code analysis|Enforces consistency and teaches Elixir best practices.|
|**Code Formatting**|`mix format`|(built-in)|Universal code formatting|Eliminates stylistic debates and ensures a consistent codebase.|
|**Testing**|ExUnit|(built-in)|Unit and integration testing|Elixir's powerful and expressive built-in testing framework.|
|**Property Testing**|StreamData|~> 0.6|Property-based testing|Generates a wide range of test data to find edge cases in pure functions.|
|**Deployment**|Docker Compose|latest|Local hosting and environment mgmt|Provides a reproducible, self-contained environment for all services.|

## Data Models

### User

- **Purpose:** Represents a user who can log in to the system. This model is used when authentication is enabled.
    
- **Key Attributes:**
    
    - `id`: `uuid` - Primary key.
        
    - `email`: `string` - The user's email, used for identification.
        
    - `name`: `string` - The user's display name.
        
    - `provider`: `string` - The OAuth provider (e.g., "google").
        
    - `provider_uid`: `string` - The user's unique ID from the OAuth provider.
        
- **Relationships:**
    
    - Has many `Sessions`.
        
    - Has many `LLMConfigurations`.
        
    - Has many `ToolPermissions`.
        

#### TypeScript Interface

```
// To be stored in a shared package
export interface User {
  id: string;
  email: string;
  name: string;
}
```

### Session

- **Purpose:** Represents a single conversation session. This is the core model for the checkpoint/restore functionality.
    
- **Key Attributes:**
    
    - `id`: `uuid` - Primary key.
        
    - `user_id`: `uuid` (nullable) - Foreign key to the `User`. `NULL` for anonymous sessions.
        
    - `anonymous_session_id`: `string` (nullable) - A unique token for anonymous browser sessions.
        
    - `name`: `string` - A user-given name for the session (e.g., "Refactoring the auth module").
        
    - `agent_state`: `jsonb` - A serialized representation of the `Agent` GenServer's state, including the full message history.
        
- **Relationships:**
    
    - Belongs to a `User` (if not anonymous).
        

#### TypeScript Interface

```
// To be stored in a shared package
export interface Session {
  id: string;
  userId?: string;
  name: string;
  // agent_state is backend-only
}
```

### LLMConfiguration

- **Purpose:** Securely stores user-provided API keys or OAuth tokens for different LLM providers.
    
- **Key Attributes:**
    
    - `id`: `uuid` - Primary key.
        
    - `user_id`: `uuid` - Foreign key to the `User`.
        
    - `provider`: `string` - The LLM provider (e.g., "gemini", "openai", "anthropic").
        
    - `auth_type`: `string` - The type of credential ("api_key" or "oauth_token").
        
    - `credentials`: `string` (encrypted) - The encrypted API key or refresh token.
        
- **Relationships:**
    
    - Belongs to a `User`.
        

#### TypeScript Interface

```
// To be stored in a shared package
// Note: Credentials are intentionally omitted from the frontend interface.
export interface LLMConfiguration {
  id: string;
  userId: string;
  provider: 'gemini' | 'openai' | 'anthropic';
  authType: 'api_key' | 'oauth_token';
}
```

### ToolPermission

- **Purpose:** Manages user-specific settings for powerful tools, such as the shell command tool.
    
- **Key Attributes:**
    
    - `id`: `uuid` - Primary key.
        
    - `user_id`: `uuid` - Foreign key to the `User`.
        
    - `tool_name`: `string` - The name of the tool (e.g., "shell").
        
    - `is_enabled`: `boolean` - Whether the user has enabled this tool.
        
    - `sandbox_bypassed`: `boolean` - Whether the user has chosen to bypass the sandbox for this tool.
        
- **Relationships:**
    
    - Belongs to a `User`.
        

#### TypeScript Interface

```
// To be stored in a shared package
export interface ToolPermission {
  id: string;
  userId: string;
  toolName: string;
  isEnabled: boolean;
  sandboxBypassed: boolean;
}
```

## API Specification

### REST API Specification

```
openapi: 3.0.1
info:
  title: Elixir Gemini Agent API
  version: v1.0.0
  description: API for the Elixir Gemini Agent, primarily for TUI/CLI authentication and future integrations.
servers:
  - url: /api/v1
    description: API v1
paths:
  /cli/auth/initiate:
    post:
      summary: Initiate CLI Device Auth
      description: Starts the device authorization flow for a CLI client.
      operationId: initiateCliAuth
      responses:
        '200':
          description: Successfully initiated flow.
          content:
            application/json:
              schema:
                type: object
                properties:
                  device_code:
                    type: string
                    description: The code the CLI client will use to poll for the token.
                  user_code:
                    type: string
                    description: A short code for the user to enter on the verification page.
                  verification_uri:
                    type: string
                    description: The URL the user must visit to authorize the device.
                  expires_in:
                    type: integer
                    description: The number of seconds until the codes expire.
                  interval:
                    type: integer
                    description: The recommended polling interval in seconds.
  /cli/auth/token:
    post:
      summary: Poll for CLI Auth Token
      description: Polls the server to check if the user has completed the authorization flow.
      operationId: pollForCliToken
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                device_code:
                  type: string
                  description: The device_code received from the /initiate endpoint.
      responses:
        '200':
          description: Authorization successful.
          content:
            application/json:
              schema:
                type: object
                properties:
                  access_token:
                    type: string
                  token_type:
                    type: string
                    example: "Bearer"
                  expires_in:
                    type: integer
        '400':
          description: Bad request, or authorization is still pending.
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
                    enum: [authorization_pending, slow_down, expired_token, invalid_request]
```

## Components

### MyAppWeb (Phoenix Application)

- **Responsibility:** This is the primary user-facing component. It handles all HTTP requests, serves the Phoenix LiveView frontend, manages WebSockets for real-time communication, and exposes the REST API for the TUI. It is the entry point for all user interactions.
    
- **Key Interfaces:**
    
    - Renders LiveViews for the web UI.
        
    - Exposes the `/api/v1` REST endpoints.
        
    - Manages the `UserSocket` for LiveView connections.
        
- **Dependencies:** `Agents` context, `Accounts` context.
    
- **Technology Stack:** Phoenix, Phoenix LiveView, Tailwind CSS.
    

### Agents (Phoenix Context)

- **Responsibility:** This is the core of the agentic engine. It manages the lifecycle of agent processes, handles conversation state, and orchestrates the ReAct loop. It is the central business logic component.
    
- **Key Interfaces:**
    
    - `Agents.start_agent_for_user(user)`: Starts a new `Agent` GenServer.
        
    - `Agents.send_prompt(agent_pid, prompt)`: Sends a new prompt to an agent.
        
    - `Agents.save_session(agent_pid, name)`: Persists an agent's state.
        
    - `Agents.restore_session(session_id)`: Restores an agent's state.
        
- **Dependencies:** `LLMProviders` context, `Tooling` context, `Ecto.Repo`.
    
- **Technology Stack:** Elixir, OTP (GenServer, Supervisor).
    

### Accounts (Phoenix Context)

- **Responsibility:** Manages all user-related data and authentication logic. It handles user creation, session management, and the storage of credentials and permissions.
    
- **Key Interfaces:**
    
    - `Accounts.get_or_create_user_from_oauth(auth_details)`: Finds or creates a user from an OAuth callback.
        
    - `Accounts.get_user(id)`: Retrieves a user.
        
    - `Accounts.store_llm_config(user, config)`: Saves an LLM configuration.
        
    - `Accounts.get_tool_permission(user, tool_name)`: Retrieves a tool permission.
        
- **Dependencies:** `Ecto.Repo`.
    
- **Technology Stack:** Elixir, Ecto.
    

### LLMProviders (Phoenix Context & Behaviour)

- **Responsibility:** This component provides the model-agnostic abstraction for communicating with various Large Language Models. It defines the `LLMProvider` behaviour and contains the concrete adapter modules for each supported service.
    
- **Key Interfaces:**
    
    - `LLMProviders.get_provider(provider_name)`: Returns the configured provider module.
        
    - The `LLMProvider` behaviour defines the contract: `completion/2`, `stream_completion/2`, `tool_completion/3`.
        
- **Dependencies:** `gemini_ex`, `openai_ex`, `anthropix`.
    
- **Technology Stack:** Elixir (Behaviours).
    

### Tooling (Phoenix Context & Behaviour)

- **Responsibility:** Manages the registration, definition, and execution of tools available to the agent. It defines the `Tool` behaviour and the `deftool` DSL for creating new tools.
    
- **Key Interfaces:**
    
    - `Tooling.get_tool_definitions()`: Returns the JSON schema for all available tools.
        
    - `Tooling.execute_tool(tool_name, args)`: Executes a specific tool.
        
    - The `Tool` behaviour defines the contract: `definition/0`, `execute/1`.
        
- **Dependencies:** None.
    
- **Technology Stack:** Elixir (Metaprogramming, Behaviours).
    

### Component Diagrams

```
graph TD
    subgraph Phoenix Web Layer
        WebApp[MyAppWeb]
    end

    subgraph Core Logic
        AgentsCtx[Agents Context]
        AccountsCtx[Accounts Context]
        LLMCtx[LLMProviders Context]
        ToolingCtx[Tooling Context]
    end

    subgraph Database
        DB[(PostgreSQL)]
    end

    WebApp --> AgentsCtx
    WebApp --> AccountsCtx
    AgentsCtx --> LLMCtx
    AgentsCtx --> ToolingCtx
    AgentsCtx --> DB
    AccountsCtx --> DB

```

## Source Tree

```
/
├── assets/             # Frontend assets (JS, CSS) processed by esbuild
├── config/             # Application configuration files
├── deps/               # Mix dependencies
├── lib/
│   ├── my_app/         # Core application logic (TheMaestro)
│   │   ├── accounts/   # Accounts Context
│   │   │   ├── user.ex
│   │   │   └── ...
│   │   ├── agents/     # Agents Context
│   │   │   ├── agent.ex  # The GenServer
│   │   │   └── ...
│   │   ├── llm_providers/ # LLMProviders Context
│   │   │   ├── provider.ex # The Behaviour
│   │   │   ├── gemini.ex   # Gemini Adapter
│   │   │   └── ...
│   │   ├── tooling/      # Tooling Context
│   │   │   ├── tool.ex     # The Behaviour
│   │   │   ├── tooling.ex  # The DSL
│   │   │   └── tools/      # Directory for tool modules
│   │   ├── application.ex # OTP Application entry point
│   │   └── repo.ex        # Ecto Repo module
│   └── my_app_web/     # Phoenix web interface
│       ├── channels/
│       ├── components/   # LiveView components, layouts
│       ├── controllers/
│       ├── live/         # LiveViews
│       ├── router.ex
│       ├── templates/
│       └── ...
├── priv/               # Private data (static assets, ecto migrations)
├── test/               # Test files mirroring the lib structure
├── demos/              # Runnable demos for each epic
├── tutorials/          # Educational tutorials for each story
├── gemini-cli-source/  # Reference source code
├── Dockerfile          # For building the production image
├── docker-compose.yml  # For local development and deployment
└── mix.exs             # Mix project file
```

## Infrastructure and Deployment

This section details the self-hosted infrastructure using Docker. The goal is a reproducible and portable environment for both development and production.

### Dockerfile

This multi-stage `Dockerfile` creates an optimized production image for the Phoenix application.

```
# Dockerfile

# STAGE 1: Build Stage
# Use the official Elixir image which includes Hex and Rebar
FROM hexpm/elixir:1.17.0-erlang-26.2.2-alpine-3.18.4 AS build

# Set build-time arguments
ARG MIX_ENV=prod

# Install build dependencies
RUN apk add --no-cache build-base git

# Set the working directory
WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy over the mix files
COPY mix.exs mix.lock ./
COPY config config/

# Install dependencies
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy over the application source
COPY priv priv/
COPY lib lib/
COPY assets assets/

# Compile assets
RUN mix assets.deploy

# Compile the release
RUN mix release

# STAGE 2: Final Stage
# Use a smaller, final image
FROM alpine:3.18.4 AS app

# Set environment variables
ENV MIX_ENV=prod

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Set the working directory
WORKDIR /app

# Copy the compiled release from the build stage
COPY --from=build /app/_build/prod/rel/my_app .

# Expose the application port
EXPOSE 4000

# Define the entrypoint
ENTRYPOINT ["bin/my_app", "start"]
```

### Docker Compose Configuration

This `docker-compose.yml` file defines the services for local development.

```
# docker-compose.yml
version: '3.8'

services:
  db:
    image: postgres:16
    container_name: my_app_db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: my_app_dev
    ports:
      - "5432:5432"
    volumes:
      - db_data:/var/lib/postgresql/data

  app:
    build: .
    container_name: my_app
    depends_on:
      - db
    environment:
      MIX_ENV: dev
      DATABASE_URL: ecto://postgres:password@db/my_app_dev
      # Add other necessary env vars for API keys, etc.
      # SECRET_KEY_BASE should be generated and set here
    ports:
      - "4000:4000"
    volumes:
      - .:/app
      # Exclude directories to prevent overwriting compiled code in the container
      - /app/deps
      - /app/_build

volumes:
  db_data:
```

### Local Development Workflow

1. **Initial Setup**:
    
    - Create a `.env` file from `.env.example` and populate it with secrets (e.g., `SECRET_KEY_BASE`, LLM API keys).
        
    - Run `docker-compose build` to build the application image.
        
2. **Starting Services**:
    
    - Run `docker-compose up` to start the application and the database.
        
3. **Database Setup**:
    
    - In a separate terminal, run `docker-compose exec app mix ecto.create`.
        
    - Run `docker-compose exec app mix ecto.migrate`.
        
4. **Accessing the App**:
    
    - The Phoenix application will be available at `http://localhost:4000`.
        

## Error Handling Strategy

### General Approach

The application will follow Elixir's idiomatic error handling philosophy, preferring explicit error handling with tagged tuples over exceptions for predictable, non-fatal errors.

- **Error Model**: Functions within contexts will return `{:ok, value}` on success and `{:error, reason}` on failure. The `reason` will typically be a descriptive atom or a custom error struct.
    
- **Exception Usage**: Exceptions (and "bang" functions like `Ecto.Repo.insert!/1`) will be used primarily at the boundaries of the system (e.g., in LiveView event handlers or API controllers) where a failure is considered unrecoverable for that specific request and should result in a crash, which is then handled by the supervisor or a `Plug.ErrorHandler`.
    
- **Error Module**: A dedicated `MyApp.Error` module will define custom exception structs for different error types (e.g., `ValidationError`, `NotFoundError`, `PermissionError`) to provide richer error information.
    

### Logging Standards

- **Library**: The built-in `Logger` will be used for all application logging.
    
- **Format**: Logs will be structured (e.g., JSON) in production for easier parsing by log management systems.
    
- **Levels**:
    
    - `:debug` - Verbose information for development.
        
    - `:info` - Standard operational messages.
        
    - `:warn` - Potentially problematic situations that don't cause a crash.
        
    - `:error` - Unrecoverable errors and crashes.
        
- **Required Context**: All log messages must include a `request_id` to correlate logs for a single user interaction.
    

### Error Handling Patterns

#### External API Errors (LLM Providers)

- **Retry Policy**: A library like `Retry` will be used to implement an exponential backoff retry strategy for transient network errors when calling external APIs.
    
- **Circuit Breaker**: A library like `Fuse` will be used to prevent repeated calls to a failing external service.
    
- **Error Translation**: Each LLM adapter will be responsible for translating provider-specific errors into a standardized `{:error, reason}` tuple.
    

#### Business Logic Errors

- **Custom Exceptions**: The `MyApp.Error` module will be used to raise specific, meaningful exceptions when an operation cannot proceed (e.g., `MyApp.Error.PermissionError`).
    
- **User-Facing Errors**: In the `MyAppWeb` layer, these custom exceptions will be caught and translated into user-friendly flash messages for LiveView or standardized JSON error responses for the REST API.
    

## Coding Standards

These standards are **mandatory** for all AI agents and human developers to ensure a consistent, high-quality codebase.

### Core Standards

- **Languages & Runtimes:** Elixir `~> 1.17` and Erlang/OTP `26`.
    
- **Style & Linting:** The project will strictly enforce `mix format` and `Credo` via CI. No unformatted or non-compliant code will be merged.
    
- **Test Organization:** Test files must mirror the `lib/` directory structure. A test for `lib/my_app/agents/agent.ex` must be located at `test/my_app/agents/agent_test.exs`.
    

### Naming Conventions

|   |   |   |
|---|---|---|
|**Element**|**Convention**|**Example**|
|Modules|`PascalCase`|`MyApp.Agents.Agent`|
|Functions|`snake_case`|`start_agent_for_user`|
|Variables|`snake_case`|`current_user`|
|DB Tables|`snake_case` (plural)|`users`, `llm_configurations`|
|DB Columns|`snake_case`|`provider_uid`|

### Critical Rules

- **Context Boundaries:** The `MyAppWeb` module (and its children) **MUST NOT** call `Ecto` or any database functions directly. All database and business logic access must go through the public functions of a context module (e.g., `MyApp.Accounts`, `MyApp.Agents`).
    
- **Explicit Error Handling:** Functions in contexts must return `{:ok, value}` or `{:error, reason}`. Exceptions should only be used at the system's boundaries (LiveViews, Controllers).
    
- **No `console.log` equivalent:** Use the `Logger` module for all logging. `IO.inspect` is for temporary debugging only and must not be committed.
    
- **Configuration:** Never hardcode secrets or configuration values. All configuration must be read from the application environment (`Application.get_env/3`).
    

## Test Strategy and Standards

### **(updated)** Testing Philosophy

- **Approach:** The project will follow a test-after-development approach with a strong emphasis on comprehensive coverage. The goal is to build a robust safety net that enables confident refactoring and future development.
    
- **Coverage Goals:** A minimum of **90% test coverage** will be enforced via CI for all core logic in the `lib/my_app/` directory.
    
- **Test Pyramid:** The strategy will prioritize fast and isolated unit tests, with fewer, more comprehensive integration tests, and a minimal set of E2E tests for critical user flows.
    
- **Property-Based Testing:** We will leverage **property-based testing** using the `StreamData` library for pure functions to test a wide range of automatically generated inputs, helping to uncover edge cases that example-based tests might miss.
    
- **Doctests:** As a core principle of "living documentation," all pure, public functions within contexts **MUST** have doctests.
    

### Test Types and Organization

#### Unit Tests

- **Framework:** ExUnit (built-in).
    
- **File Convention:** `_test.exs` suffix, mirroring the source directory.
    
- **Location:** `test/my_app/`.
    
- **Mocking:** The `Mox` library will be used for creating mocks and stubs, particularly for isolating contexts from each other and from external APIs during unit testing.
    
- **AI Agent Requirements:**
    
    - Generate tests for all public functions in a module.
        
    - Cover the "happy path" success case.
        
    - Cover at least one common error case (e.g., invalid input).
        
    - Follow the AAA pattern (Arrange, Act, Assert).
        

#### **(updated)** Integration Tests

- **Scope:** The primary goal of integration tests is to verify that the system's components work together as expected. This includes testing the integration between contexts and the **real database**.
    
- **Location:** `test/my_app/integration/`.
    
- **Test Infrastructure:** The local Docker Compose environment is critical. Integration tests will run against a **real PostgreSQL instance** to ensure that Ecto queries and data manipulations behave exactly as they will in production. A dedicated `MIX_ENV=test` database will be used and reset between test runs. Mocks should be avoided at this level.
    

#### **(updated)** End-to-End (E2E) Tests

- **Framework:** `Wallaby` will be used for browser-based E2E testing of Phoenix LiveView flows.
    
- **Scope:** E2E tests are considered a form of **integration testing** and are of high importance. They will verify critical, complete user flows from the user's browser, through the LiveView, into the core contexts, and interacting with the database.
    
- **Environment:** E2E tests will run against a fully running application in the `MIX_ENV=test` environment, interacting with the system just as a real user would.
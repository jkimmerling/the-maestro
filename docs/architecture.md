# The Maestro - Architecture Specification

Version: 2.0

Status: COMPLETE - BMAD IMPLEMENTATION-READY

## 1. Overview

This document outlines the technical architecture for **The Maestro**, an LLM orchestration platform. The system is designed as a monolithic Elixir application built on the Phoenix framework, prioritizing developer productivity, real-time interactivity, and direct system access for the AI agents. It will be supplemented by a standalone Terminal User Interface (TUI) client that communicates with the main application via a dedicated API.

### 1.1. Architectural Goals & Constraints

- **Primary Goal: Developer Enablement:** The architecture must maximize the power and flexibility available to the single user. The AI agents are to be treated as trusted collaborators, not sandboxed entities.
    
- **Real-time Interaction:** All user-facing interfaces (Web and TUI) must be fully real-time, providing immediate feedback on agent status, "thoughts," and tool execution.
    
- **Maintainability:** As a solo-developer project, the codebase must be clear, well-structured, and easy to maintain. The choice of a Phoenix monolith supports this by keeping all core logic in a single, cohesive application.
    
- **High Concurrency:** The system must leverage Elixir/OTP to efficiently manage dozens of concurrent LLM sessions and background tasks without performance degradation.
    
- **Constraint: Single-Tenancy:** The entire system is designed for a single user. There are no requirements for multi-tenancy, complex user roles, or permissions.
    
- **Constraint: Exact API Fidelity:** A hard constraint is that all communication with external LLM providers must precisely replicate the headers and authentication flows of the `llxprt` and `gemini-cli` reference applications.
    

## 2. System Architecture & Logical View

The system is composed of a primary Phoenix web application and a separate TUI client application.

### 2.1. System Architecture Diagram

```
+--------------------------------------------------------------------------+
| User (Alex, the Power Developer)                                         |
+--------------------------------------------------------------------------+
      |                                      |
      | (Web Browser)                        | (Terminal)
      |                                      |
+-----v--------------------------------------+------v---------------------+
| Phoenix Web Application (The Maestro Core) |      | TUI Application     |
|============================================|      | (Standalone Client) |
|                                            |      |                     |
|  +------------------+  +-----------------+ |      +---------------------+
|  | Web UI (LiveView)|  | TUI API (JSON)  |<------>|   (Ratatouille)     |
|  +------------------+  +-----------------+ |      +---------------------+
|           ^                    ^           |
|           | (WebSocket/HTTP)   | (WebSocket/HTTP) |
|  +--------v--------------------v---------+ |
|  |   Application Core / Business Logic   | |
|  |---------------------------------------| |
|  | +-----------------+ +---------------+ | |
|  | | Session Manager | | Tool Executor | | |
|  | +-----------------+ +---------------+ | |
|  +---------------------------------------+ |
|           |                    |           |
|  +--------v--------------------v---------+ |      +---------------------+
|  |    Provider & Auth Integration Layer    |------>| External LLM APIs   |
|  |---------------------------------------| |      | (Anthropic, OpenAI, |
|  | +-----------------+ +---------------+ | |      |        Gemini)      |
|  | | Tesla/Finch HTTP| | Auth Handlers | | |      +---------------------+
|  | +-----------------+ +---------------+ | |
|  +---------------------------------------+ |      +---------------------+
|           |                                |------>| External MCP Servers|
|  +--------v-------------------------------+ |      +---------------------+
|  |      Persistence & Caching Layer      | |
|  |---------------------------------------| |
|  | +------------+ +---------+ +---------+| |
|  | | Ecto/Postgres| |  Redis  | |  Oban   | |
|  | +------------+ +---------+ +---------+| |
|  +---------------------------------------+ |
+--------------------------------------------+

```

### 2.2. Component Breakdown

- **Web UI (Phoenix LiveView):** The primary user interface. Built entirely with server-rendered HTML over WebSockets. This component is responsible for all management tasks: credentials, sessions, tools, and agent templates.
    
- **TUI API (JSON API & WebSockets):** A versioned, stateless JSON API for general commands (list sessions, create session) and a stateful WebSocket connection for real-time message streaming. This de-couples the TUI from the main application's business logic.
    
- **Application Core:**
    
    - **Session Manager (OTP Supervisor & GenServers):** A dynamic supervisor will manage one `Session.Server` (a GenServer) per active chat session. This process will hold the session's state (model, provider, tools, recent message history) in memory for rapid access, act as the primary interface for the LiveView process, and coordinate calls to the other core components.
        
    - **Tool Executor:** A stateless module that acts as a router for tool calls. It will receive a tool name and parameters, look up the tool's definition and status in the database, and delegate to the appropriate implementation module (e.g., `Tools.FileSystem`, `Tools.CodeExecution`).
        
- **Provider & Auth Integration Layer:**
    
    - **Tesla/Finch HTTP Client:** The single point of contact for all outbound API requests. It will use named Finch pools for each provider to manage connection limits and timeouts effectively.
        
    - **Auth Handlers:** A set of modules, one per provider, responsible for implementing the precise logic for API key and OAuth 2.0 authentication flows. These modules will fetch credentials from the database and construct the necessary Tesla middleware to inject the correct headers.
        
- **Persistence & Caching Layer:**
    
    - **Ecto/PostgreSQL:** The source of truth for all application data.
        
    - **Redis:** Primarily used for presence tracking and ephemeral state that doesn't need to be persisted, such as which sessions are currently open in the UI.
        
    - **Oban:** The background job processor. Its primary, critical role is to handle the periodic refreshing of OAuth tokens.
        

## 3. Process View & Concurrency

The system's concurrency model is built on OTP.

- **Application Supervision Tree:** The main application supervisor will manage several key children:
    
    - The Phoenix Endpoint (for web requests).
        
    - The Ecto Repo.
        
    - The Oban supervisor.
        
    - The `SessionManager` dynamic supervisor.
        
- **Request Lifecycle (LiveView):**
    
    1. User connects to a session's LiveView.
        
    2. The LiveView process starts a `Session.Server` GenServer process via the `SessionManager` if one isn't already running for that session ID.
        
    3. The LiveView process subscribes to the session's PubSub topic (e.g., `maestro:session_123`).
        
    4. When the user sends a message, the LiveView process sends a cast message to the `Session.Server`.
        
    5. The `Session.Server` constructs the API call, sends it to the Provider Integration Layer, and receives the streaming response.
        
    6. As chunks arrive, the `Session.Server` broadcasts them over the PubSub topic.
        
    7. The LiveView process receives the broadcasted chunks and updates the UI.
        

## 4. Data Flow & Data Model

The data model is centered around the `sessions` and `messages` tables.

- **Data Model:** The schemas are defined in the PRD. The key relationship is `sessions` -> `conversations` -> `messages`. This ensures a complete, auditable log of every interaction. The `saved_authentications` table stores all secrets encrypted at rest using `cloak_ecto`.
    
- **Data Flow (New Message):**
    
    1. A message is sent from a UI (LiveView or TUI) to a `Session.Server` process.
        
    2. The `Session.Server` fetches the full conversation history from the `messages` table in Postgres.
        
    3. It constructs the API request payload.
        
    4. The request is sent through the `Tesla/Finch` client, which adds the appropriate authentication headers.
        
    5. The streaming response is received.
        
    6. The full request and final response payloads are written to the `messages` table, along with the calculated token counts and cost.
        
    7. The response is broadcast via PubSub to the UI.
        

## 5. Deployment & Infrastructure

- **Deployment Strategy:** The application will be deployed as a single monolith using Elixir releases. This creates a self-contained, portable artifact.
    
- **Infrastructure Requirements:**
    
    - A server (VM or container) capable of running the Elixir BEAM.
        
    - A managed PostgreSQL database.
        
    - A managed Redis instance.
        
- **Configuration:** All sensitive information (database URLs, API secrets, etc.) will be managed via environment variables and loaded at runtime, following 12-factor app principles.
    

## 6. Security & Error Handling

- **Security:**
    
    - **Credential Storage:** All API keys and OAuth tokens in the `saved_authentications` table **must** be encrypted at rest using a library like `cloak_ecto`.
        
    - **API Access:** The TUI API will be protected by a static, long-lived API token that must be sent in a header.
        
    - **Web UI:** Standard Phoenix session management will be used for the web interface.
        
- **Fault Tolerance:** The use of OTP supervisors is central. If a `Session.Server` process crashes due to an unexpected error, the `SessionManager` supervisor will restart it, allowing the user to reconnect and resume their session without bringing down the entire application. Finch's connection pooling also provides resilience against transient network issues with the external APIs.
    

## 7. Technology Stack

- **Language:** Elixir
    
- **Web Framework:** Phoenix 1.7+
    
- **Web UI:** Phoenix LiveView
    
- **Database:** PostgreSQL 15+
    
- **ORM:** Ecto
    
- **Background Jobs:** Oban
    
- **In-Memory Store:** Redis
    
- **HTTP Client:** Tesla with Finch adapter
    
- **TUI Framework:** Ratatouille
    
- **TUI Packaging:** Burrito


## 8. Component Implementation Specifications

**Goal:** Provide implementation-ready specifications for each core component to enable immediate development.

### 8.1. Session Manager Implementation

#### **Process Architecture**
```elixir
# Supervision tree structure
SessionManager (DynamicSupervisor)
├── Session.Server (GenServer) - session_id: "abc123"
├── Session.Server (GenServer) - session_id: "def456"
└── Session.Server (GenServer) - session_id: "ghi789"
```

#### **Session.Server GenServer Specification**

**State Structure:**
```elixir
%Session.State{
  session_id: "abc123",
  provider: :anthropic,
  model: "claude-3-opus-20240229",
  auth_type: :oauth,
  system_prompt: "You are a helpful coding assistant...",
  working_directory: "/Users/alex/projects/app",
  enabled_tools: ["read_file", "write_file", "execute_code"],
  enabled_mcps: ["context7", "playwright"],
  conversation_history: [...],  # Last 10 messages for context
  streaming_state: :idle | :streaming | :waiting_tool,
  current_request_id: "req_123"
}
```

**Critical GenServer Callbacks:**
```elixir
# Handle user message
def handle_cast({:send_message, message, opts}, state) do
  # 1. Fetch full conversation history from DB
  # 2. Construct provider-specific API payload
  # 3. Stream response via Provider layer
  # 4. Broadcast chunks via PubSub
  # 5. Save complete request/response to DB
end

# Handle streaming chunks from provider
def handle_info({:stream_chunk, chunk_data, request_id}, state) do
  # 1. Parse chunk based on provider format
  # 2. Broadcast to PubSub topic "maestro:session_#{session_id}"
  # 3. Update streaming state
end

# Handle tool calls
def handle_cast({:execute_tool, tool_name, parameters}, state) do
  # 1. Validate tool is enabled for session
  # 2. Delegate to Tool.Executor
  # 3. Return result to ongoing conversation
end
```

#### **Provider Integration Layer Implementation**

**Tesla Client Configuration:**
```elixir
# lib/maestro/providers/client.ex
def build_client(provider, auth_config) do
  base_middleware = [
    Tesla.Middleware.Logger,
    Tesla.Middleware.Retry,
    Tesla.Middleware.JSON
  ]
  
  auth_middleware = case {provider, auth_config.type} do
    {:anthropic, :api_key} -> [
      {Tesla.Middleware.Headers, [
        {"x-api-key", auth_config.api_key},
        {"anthropic-version", "2023-06-01"},
        {"anthropic-beta", "messages-2023-12-15"},
        {"User-Agent", "llxprt/1.0"},
        {"Accept", "application/json"},
        {"X-Client-Version", "1.0.0"}
      ]}
    ]
    {:anthropic, :oauth} -> [
      {Tesla.Middleware.Headers, [
        {"Authorization", "Bearer #{auth_config.access_token}"},
        {"anthropic-version", "2023-06-01"},
        # ... exact header order per PRD requirements
      ]}
    ]
    # OpenAI and Gemini configurations...
  end
  
  Tesla.client(base_middleware ++ auth_middleware, 
               {Tesla.Adapter.Finch, name: provider_pool(provider)})
end
```

### 8.2. Tool Execution Architecture

#### **Tool Registry Pattern**
```elixir
# lib/maestro/tools/registry.ex
defmodule Maestro.Tools.Registry do
  @doc "Get all enabled tools from database"
  def enabled_tools do
    from(t in Tool, where: t.is_enabled == true)
    |> Repo.all()
    |> Enum.map(&tool_to_spec/1)
  end
  
  @doc "Execute tool with validation"
  def execute(tool_name, parameters, session_context) do
    with {:ok, tool_spec} <- get_tool_spec(tool_name),
         :ok <- validate_tool_enabled(tool_spec, session_context),
         {:ok, result} <- delegate_execution(tool_spec, parameters, session_context) do
      {:ok, result}
    else
      {:error, reason} -> {:error, "Tool execution failed: #{reason}"}
    end
  end
end
```

#### **File System Tool Implementation**
```elixir
# lib/maestro/tools/file_system.ex
defmodule Maestro.Tools.FileSystem do
  @doc "Read file with working directory context"
  def read_file(path, %{working_directory: wd}) do
    absolute_path = resolve_path(path, wd)
    
    with :ok <- validate_access(absolute_path),
         {:ok, content} <- File.read(absolute_path) do
      {:ok, %{path: path, content: content, size: byte_size(content)}}
    else
      {:error, :enoent} -> {:error, "File not found: #{path}"}
      {:error, :eacces} -> {:error, "Permission denied: #{path}"}
      error -> error
    end
  end
  
  @doc "Write file with directory creation"
  def write_file(path, content, %{working_directory: wd}) do
    absolute_path = resolve_path(path, wd)
    
    with :ok <- ensure_parent_directory(absolute_path),
         :ok <- validate_write_access(absolute_path),
         :ok <- File.write(absolute_path, content) do
      {:ok, %{path: path, bytes_written: byte_size(content)}}
    else
      error -> error
    end
  end
  
  # Security: Prevent directory traversal
  defp resolve_path(path, working_directory) do
    Path.expand(path, working_directory)
    |> validate_within_bounds(working_directory)
  end
end
```


## 9. Security Architecture

**Goal:** Implement comprehensive security design addressing the threat model from PRD requirements.

### 9.1. Threat Model & Security Controls

#### **Attack Vectors & Mitigations**

| **Threat** | **Impact** | **Mitigation** | **Implementation** |
|------------|------------|----------------|-------------------|
| Credential Theft | HIGH | Encrypted storage | ClakEcto with AES-256 |
| Code Injection via Tools | HIGH | Input sanitization | Validation + sandboxing |
| Path Traversal | MEDIUM | Path validation | Bounded file access |
| Token Hijacking | MEDIUM | Secure storage | HTTP-only, encrypted tokens |
| API Key Exposure | HIGH | Environment isolation | Never log sensitive data |

### 9.2. Credential Security Architecture

#### **Encryption Implementation**
```elixir
# config/config.exs
config :maestro, Maestro.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.get_env("ENCRYPTION_KEY")),
      iv_length: 12
    }
  ]

# lib/maestro/schemas/saved_authentication.ex
defmodule Maestro.Schemas.SavedAuthentication do
  use Ecto.Schema
  
  schema "saved_authentications" do
    field :provider, Ecto.Enum, values: [:anthropic, :openai, :gemini]
    field :auth_type, Ecto.Enum, values: [:api_key, :oauth]
    field :credentials, Maestro.EncryptedCredentials  # Encrypted JSONB
    field :expires_at, :utc_datetime
    timestamps()
  end
end

# Custom encrypted type
defmodule Maestro.EncryptedCredentials do
  use Cloak.Ecto.JSON, vault: Maestro.Vault
end
```

#### **OAuth Token Management**
```elixir
# lib/maestro/auth/oauth_manager.ex
defmodule Maestro.Auth.OAuthManager do
  @doc "Refresh token with 5-minute warning buffer"
  def refresh_if_needed(%SavedAuthentication{} = auth) do
    case expires_soon?(auth.expires_at) do
      true -> refresh_token(auth)
      false -> {:ok, auth}
    end
  end
  
  defp expires_soon?(expires_at) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second) < 300  # 5 min buffer
  end
  
  @doc "Background job for token refresh"
  def refresh_token(%SavedAuthentication{provider: provider} = auth) do
    with {:ok, response} <- request_token_refresh(provider, auth.credentials.refresh_token),
         {:ok, updated_auth} <- update_credentials(auth, response) do
      {:ok, updated_auth}
    else
      {:error, reason} -> 
        # Log error and notify user through WebSocket
        notify_auth_failure(auth, reason)
        {:error, reason}
    end
  end
end
```

### 9.3. Tool Security Implementation

#### **Code Execution Sandboxing**
```elixir
# lib/maestro/tools/code_execution.ex
defmodule Maestro.Tools.CodeExecution do
  @timeout 30_000  # 30 second timeout
  @max_output_size 1_048_576  # 1MB output limit
  
  def execute(code, language, %{working_directory: wd}) do
    with {:ok, temp_file} <- create_temp_file(code, language),
         {:ok, command} <- build_execution_command(temp_file, language),
         {:ok, result} <- run_sandboxed(command, wd) do
      {:ok, result}
    after
      cleanup_temp_file(temp_file)
    end
  end
  
  defp run_sandboxed(command, working_directory) do
    case System.cmd("timeout", ["30", command], 
                    cd: working_directory,
                    stderr_to_stdout: true,
                    into: "",
                    max_buffer_size: @max_output_size) do
      {output, 0} -> {:ok, %{output: output, exit_code: 0}}
      {output, code} -> {:ok, %{output: output, exit_code: code}}
    end
  rescue
    e in System.CmdError -> {:error, "Execution failed: #{e.message}"}
  end
end
```


## 10. Performance Architecture

**Goal:** Design architecture to meet PRD performance requirements and handle specified load.

### 10.1. Concurrency & Scaling Design

#### **Connection Pool Configuration**
```elixir
# config/config.exs
config :maestro, :finch_pools,
  anthropic: [
    size: 50,           # 50 connections per pool
    count: 1,           # 1 pool
    conn_opts: [
      transport_opts: [timeout: 30_000],
      proxy: nil
    ],
    pool_opts: [max_idle_time: 30_000]
  ],
  openai: [size: 50, count: 1, conn_opts: [transport_opts: [timeout: 30_000]]],
  gemini: [size: 50, count: 1, conn_opts: [transport_opts: [timeout: 30_000]]]

# Application start - initialize pools
def start(_type, _args) do
  children = [
    # Named Finch pools for each provider
    {Finch, name: :anthropic_pool, pools: config(:finch_pools)[:anthropic]},
    {Finch, name: :openai_pool, pools: config(:finch_pools)[:openai]},
    {Finch, name: :gemini_pool, pools: config(:finch_pools)[:gemini]},
    
    # Main application processes
    Maestro.Repo,
    {Oban, Application.fetch_env!(:maestro, Oban)},
    Maestro.SessionManager,
    MaestroWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: Maestro.Supervisor]
  Supervisor.start_link(children, opts)
end
```

#### **Memory Management Strategy**
```elixir
# lib/maestro/session/server.ex - Memory-conscious conversation handling
defmodule Maestro.Session.Server do
  @max_memory_messages 50  # Keep last 50 messages in memory
  @conversation_refresh_interval 300_000  # Refresh every 5 minutes
  
  def handle_cast({:send_message, message}, state) do
    # Fetch recent conversation context from DB, not full history
    recent_context = get_recent_context(state.session_id, @max_memory_messages)
    
    # Build API payload with context window management
    api_payload = build_context_aware_payload(message, recent_context, state.provider)
    
    # Stream response and update local cache
    {:noreply, state |> update_conversation_cache(message)}
  end
  
  # Periodic cleanup to prevent memory bloat
  def handle_info(:cleanup_cache, state) do
    Process.send_after(self(), :cleanup_cache, @conversation_refresh_interval)
    cleaned_state = trim_conversation_cache(state)
    {:noreply, cleaned_state}
  end
end
```

### 10.2. Database Performance Architecture

#### **Query Optimization Patterns**
```elixir
# lib/maestro/conversations.ex
defmodule Maestro.Conversations do
  @doc "Optimized conversation history retrieval"
  def get_recent_messages(session_id, limit \\ 50) do
    from(m in Message,
      join: c in assoc(m, :conversation),
      where: c.session_id == ^session_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      select: %{
        id: m.id,
        role: m.role,
        content: fragment("?->>'content'", m.raw_request),
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
    |> Enum.reverse()  # Return chronological order
  end
  
  @doc "Paginated conversation history for UI"
  def get_conversation_page(session_id, page_size, offset) do
    base_query = 
      from(m in Message,
        join: c in assoc(m, :conversation),
        where: c.session_id == ^session_id,
        order_by: [desc: m.inserted_at])
    
    messages = 
      base_query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
    
    total_count = Repo.aggregate(base_query, :count)
    
    %{messages: messages, total_count: total_count, has_more: total_count > offset + page_size}
  end
end
```

#### **Database Indexing Strategy**
```sql
-- Critical performance indexes
CREATE INDEX CONCURRENTLY idx_messages_session_id_inserted_at 
  ON messages (session_id, inserted_at DESC);

CREATE INDEX CONCURRENTLY idx_conversations_session_id 
  ON conversations (session_id);

CREATE INDEX CONCURRENTLY idx_saved_auths_provider_type 
  ON saved_authentications (provider, auth_type) 
  WHERE is_enabled = true;

-- Token usage analysis indexes
CREATE INDEX CONCURRENTLY idx_messages_tokens_cost 
  ON messages (inserted_at, total_cost_usd, request_tokens + response_tokens);
```


## 11. Integration Architecture

**Goal:** Define integration patterns for MCP servers and provider APIs to support PRD requirements.

### 11.1. MCP Protocol Implementation

#### **MCP Server Registry & Discovery**
```elixir
# lib/maestro/mcp/registry.ex
defmodule Maestro.MCP.Registry do
  use GenServer
  
  @doc "Discover and cache available MCP tools"
  def init(_) do
    enabled_servers = load_enabled_servers()
    initial_state = %{
      servers: enabled_servers,
      tool_cache: %{},
      last_refresh: DateTime.utc_now()
    }
    
    # Refresh tool cache every 5 minutes
    Process.send_after(self(), :refresh_tools, 300_000)
    
    {:ok, initial_state}
  end
  
  def handle_call({:get_tools, server_name}, _from, state) do
    case Map.get(state.tool_cache, server_name) do
      nil -> 
        # Cache miss - discover tools from server
        tools = discover_server_tools(server_name)
        updated_cache = Map.put(state.tool_cache, server_name, tools)
        {:reply, tools, %{state | tool_cache: updated_cache}}
        
      cached_tools ->
        {:reply, cached_tools, state}
    end
  end
  
  defp discover_server_tools(server_name) do
    %{url: server_url} = get_server_config(server_name)
    
    case HTTPoison.get("#{server_url}/mcp/tools") do
      {:ok, %{status_code: 200, body: body}} ->
        Jason.decode!(body)
        |> Map.get("tools", [])
        
      {:error, reason} ->
        Logger.warn("Failed to discover tools from #{server_name}: #{inspect(reason)}")
        []
    end
  end
end
```

#### **MCP Tool Execution Pattern**
```elixir
# lib/maestro/mcp/executor.ex
defmodule Maestro.MCP.Executor do
  @timeout 30_000
  
  def execute_tool(server_name, tool_name, parameters) do
    with {:ok, server_config} <- get_server_config(server_name),
         {:ok, tool_spec} <- get_tool_specification(server_name, tool_name),
         {:ok, validated_params} <- validate_parameters(parameters, tool_spec),
         {:ok, result} <- call_mcp_server(server_config, tool_name, validated_params) do
      {:ok, result}
    else
      {:error, :server_not_found} -> {:error, "MCP server '#{server_name}' not configured"}
      {:error, :tool_not_found} -> {:error, "Tool '#{tool_name}' not available on #{server_name}"}
      {:error, :invalid_params} = error -> error
      {:error, reason} -> {:error, "MCP execution failed: #{inspect(reason)}"}
    end
  end
  
  defp call_mcp_server(server_config, tool_name, parameters) do
    request_body = Jason.encode!(%{
      tool: tool_name,
      parameters: parameters,
      request_id: generate_request_id()
    })
    
    HTTPoison.post(
      "#{server_config.url}/mcp/execute",
      request_body,
      [{"Content-Type", "application/json"}],
      timeout: @timeout,
      recv_timeout: @timeout
    )
    |> handle_mcp_response()
  end
  
  defp handle_mcp_response({:ok, %{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"success" => true, "result" => result}} -> {:ok, result}
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, _} -> {:error, "Invalid MCP response format"}
    end
  end
  
  defp handle_mcp_response({:ok, %{status_code: status_code}}) do
    {:error, "MCP server error: HTTP #{status_code}"}
  end
  
  defp handle_mcp_response({:error, %HTTPoison.Error{reason: reason}}) do
    {:error, "MCP connection failed: #{reason}"}
  end
end
```

### 11.2. Provider-Specific Integration Patterns

#### **Streaming Response Handler**
```elixir
# lib/maestro/providers/streaming.ex
defmodule Maestro.Providers.Streaming do
  @doc "Handle provider-specific streaming formats"
  def handle_stream_chunk(chunk, provider, request_id) do
    case parse_chunk(chunk, provider) do
      {:data, content} ->
        Phoenix.PubSub.broadcast(
          Maestro.PubSub,
          "maestro:session_#{request_id}",
          {:stream_chunk, content, :data}
        )
        
      {:tool_call, tool_data} ->
        # Handle tool execution request from LLM
        execute_tool_async(tool_data, request_id)
        
      {:end_stream} ->
        Phoenix.PubSub.broadcast(
          Maestro.PubSub,
          "maestro:session_#{request_id}",
          {:stream_end, request_id}
        )
        
      {:error, error} ->
        Phoenix.PubSub.broadcast(
          Maestro.PubSub,
          "maestro:session_#{request_id}",
          {:stream_error, error}
        )
    end
  end
  
  # Provider-specific chunk parsing
  defp parse_chunk(chunk, :anthropic) do
    case String.trim(chunk) do
      "data: " <> data ->
        case Jason.decode(data) do
          {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
            {:data, text}
          {:ok, %{"type" => "message_stop"}} ->
            {:end_stream}
          _ ->
            {:continue}
        end
        
      _ -> {:continue}
    end
  end
  
  defp parse_chunk(chunk, :openai) do
    case String.trim(chunk) do
      "data: " <> data when data != "[DONE]" ->
        case Jason.decode(data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} when is_binary(content) ->
            {:data, content}
          {:ok, %{"choices" => [%{"delta" => %{"tool_calls" => tool_calls}}]}} when is_list(tool_calls) ->
            {:tool_call, tool_calls}
          _ ->
            {:continue}
        end
        
      "data: [DONE]" -> {:end_stream}
      _ -> {:continue}
    end
  end
end
```


## 12. Quality Assurance Architecture

**Goal:** Implement architectural patterns that support the comprehensive testing strategy from PRD.

### 12.1. Testing Infrastructure Architecture

#### **Test Environment Management**
```elixir
# config/test.exs - Isolated test configuration
config :maestro, Maestro.Repo,
  username: "postgres",
  password: "postgres",
  database: "maestro_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Test-specific overrides
config :maestro, :finch_pools,
  anthropic: [size: 1, count: 1],  # Minimal pools for testing
  openai: [size: 1, count: 1],
  gemini: [size: 1, count: 1]

# Mock provider endpoints in test
config :maestro, :provider_endpoints,
  anthropic: "http://localhost:#{System.get_env("ANTHROPIC_MOCK_PORT", "4001")}",
  openai: "http://localhost:#{System.get_env("OPENAI_MOCK_PORT", "4002")}",
  gemini: "http://localhost:#{System.get_env("GEMINI_MOCK_PORT", "4003")}"
```

#### **Provider API Mocking Architecture**
```elixir
# test/support/mocks/provider_mock.ex
defmodule Maestro.Test.ProviderMock do
  use Plug.Router
  
  plug :match
  plug :dispatch
  
  # Mock Anthropic API endpoint
  post "/v1/messages" do
    conn = fetch_headers(conn)
    
    # Validate exact header order per PRD requirements
    case validate_anthropic_headers(conn) do
      :ok -> 
        mock_streaming_response(conn, :anthropic)
      {:error, missing_header} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing header: #{missing_header}"}))
    end
  end
  
  defp validate_anthropic_headers(conn) do
    required_headers = [
      {"x-api-key", "_"},
      {"anthropic-version", "2023-06-01"},
      {"anthropic-beta", "messages-2023-12-15"},
      {"user-agent", "llxprt/1.0"},
      {"accept", "application/json"},
      {"x-client-version", "1.0.0"}
    ]
    
    Enum.find(required_headers, :ok, fn {header, _} ->
      case get_req_header(conn, header) do
        [] -> {:error, header}
        _ -> nil
      end
    end)
  end
  
  defp mock_streaming_response(conn, provider) do
    conn = 
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> send_chunked(200)
    
    # Send mock streaming chunks
    mock_chunks = get_mock_chunks(provider)
    Enum.each(mock_chunks, fn chunk ->
      {:ok, conn} = chunk(conn, chunk)
      Process.sleep(10)  # Simulate realistic timing
    end)
    
    conn
  end
end
```

### 12.2. Monitoring & Observability Architecture

#### **Metrics Collection Framework**
```elixir
# lib/maestro/telemetry.ex
defmodule Maestro.Telemetry do
  def setup do
    :telemetry.attach_many(
      "maestro-telemetry",
      [
        [:maestro, :session, :message, :start],
        [:maestro, :session, :message, :stop],
        [:maestro, :session, :message, :exception],
        [:maestro, :tool, :execution, :start],
        [:maestro, :tool, :execution, :stop],
        [:maestro, :provider, :api, :start],
        [:maestro, :provider, :api, :stop]
      ],
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:maestro, :provider, :api, :stop], measurements, metadata, _config) do
    # Track API response times and success rates
    :telemetry.execute(
      [:maestro, :metrics, :api_latency],
      %{duration: measurements.duration},
      %{provider: metadata.provider, success: metadata.success}
    )
    
    # Track token usage and costs
    if metadata.token_usage do
      :telemetry.execute(
        [:maestro, :metrics, :token_usage],
        %{
          request_tokens: metadata.token_usage.request_tokens,
          response_tokens: metadata.token_usage.response_tokens,
          total_cost: metadata.token_usage.total_cost
        },
        %{provider: metadata.provider, model: metadata.model}
      )
    end
  end
  
  # Custom metrics for session management
  def handle_event([:maestro, :session, :message, :stop], measurements, metadata, _config) do
    :telemetry.execute(
      [:maestro, :metrics, :session_activity],
      %{duration: measurements.duration},
      %{session_id: metadata.session_id, message_type: metadata.message_type}
    )
  end
end
```


## 13. Architectural Decision Records (ADRs)

**Goal:** Document key architectural decisions with rationale to support future development and maintenance.

### ADR-001: Phoenix Monolith vs Microservices

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Single-user application with complex real-time requirements
- Solo developer maintenance constraints
- Need for rapid development and deployment

**Decision:** 
Implement as Phoenix monolith with separate TUI client

**Rationale:**
- **Simplicity**: Single deployment, single database, unified logging
- **Performance**: No network latency between components
- **Development Speed**: Shared code, single test suite, easier debugging
- **OTP Benefits**: Built-in supervision, actor model for sessions

**Consequences:**
- ✅ Faster development and maintenance
- ✅ Better performance for real-time features
- ✅ Simpler deployment and monitoring
- ❌ Less flexibility for independent scaling
- ❌ All components share failure domains

### ADR-002: Tesla + Finch for HTTP Client

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Need exact header fidelity with reference implementations
- Multiple provider APIs with different requirements
- High-performance concurrent connections required

**Decision:** 
Use Tesla middleware pattern with Finch connection pooling

**Rationale:**
- **Header Control**: Tesla middleware allows exact header ordering
- **Performance**: Finch provides efficient HTTP/2 connection pooling
- **Flexibility**: Easy to swap adapters or add provider-specific middleware
- **Testing**: Tesla makes mocking and testing straightforward

**Consequences:**
- ✅ Precise control over HTTP requests
- ✅ Excellent performance under load
- ✅ Easy to test and mock
- ❌ Additional dependency complexity

### ADR-003: GenServer Per Session Pattern

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Need to maintain session state and conversation context
- Real-time streaming requirements
- Multiple concurrent sessions per user

**Decision:** 
One GenServer process per active session under DynamicSupervisor

**Rationale:**
- **Isolation**: Session failures don't affect others
- **Performance**: In-memory state for fast access
- **Real-time**: Direct PubSub broadcasting from session processes
- **OTP Benefits**: Automatic restart and supervision

**Consequences:**
- ✅ Excellent fault tolerance
- ✅ High performance for concurrent sessions
- ✅ Natural fit for real-time features
- ❌ Memory usage scales with active sessions
- ❌ State management complexity

### ADR-004: Database-First Tool Configuration

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Tools need to be dynamically enabled/disabled
- Different sessions may have different tool availability
- Need audit trail of tool usage

**Decision:** 
Store tool definitions and enablement in database with registry pattern

**Rationale:**
- **Flexibility**: Runtime tool configuration without code changes
- **Auditing**: Track tool usage and configuration changes
- **Security**: Granular control over tool availability
- **Extensibility**: Easy to add new tools and MCP servers

**Consequences:**
- ✅ Runtime configurability
- ✅ Complete audit trail
- ✅ Fine-grained security control
- ❌ Database dependency for tool registry
- ❌ Slightly more complex tool execution path
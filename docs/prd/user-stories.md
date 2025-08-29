# 4. User Stories

## **Epic 1: Foundational Authentication & API Fidelity**

**Goal:** To create a multi-provider HTTP client that _exactly_ mirrors the authentication and request patterns of the `llxprt` and `gemini-cli` reference applications.

**Micro Stories:**

- **1.1: Core HTTP Client Setup**
    
    - **As the system,** I need a Tesla-based HTTP client configured to use Finch for connection pooling.
        
    - **Acceptance Criteria:**
        
        - A new Elixir module, `LLMOrchestrator.Providers.Client`, is created.
            
        - The application's `children` list in `application.ex` includes separate Finch pools for Anthropic (`https://api.anthropic.com`), OpenAI (`https://api.openai.com`), and Google (`https://generativelanguage.googleapis.com`).
            
        - The `Client` module contains a `build_client/1` function that accepts a provider atom (`:anthropic`, `:openai`, `:gemini`) and returns a Tesla client configured with basic middleware (JSON, Logger, Retry) and the correct Finch adapter.
            
- **1.2: Anthropic API Key Authentication**
    
    - **As the system,** I need to make a request to the Anthropic API using a static API key, ensuring the headers exactly match the `llxprt` reference.
        
    - **Reference:** `llxprt` source code for Anthropic header construction.
        
    - **Acceptance Criteria:**
        
        - The `Client.build_client/1` function, when called with `:anthropic`, constructs a Tesla client for API Key auth.
            
        - The client's middleware injects the following headers in **this exact order**:
            
            1. `x-api-key`: The value loaded from config.
                
            2. `anthropic-version`: "2023-06-01"
                
            3. `anthropic-beta`: "messages-2023-12-15"
                
            4. `User-Agent`: "llxprt/1.0"
                
            5. `Accept`: "application/json"
                
            6. `X-Client-Version`: "1.0.0"
                
        - A test can successfully make a simple API call and receive a valid `200 OK` response.
            
- **1.3: Anthropic OAuth - URL Generation & Token Exchange**
    
    - **As the system,** I need to generate an Anthropic OAuth 2.0 URL and handle the token exchange.
        
    - **Reference:** Anthropic's official OAuth documentation.
        
    - **Acceptance Criteria:**
        
        - The `LLMOrchestrator.Auth` module can generate a valid Anthropic OAuth 2.0 authorization URL.
            
        - The module can accept an authorization code and exchange it for an `access_token` and `refresh_token` from Anthropic's token endpoint.
            
- **1.4: Anthropic OAuth - Authenticated Call & Refresh**
    
    - **As the system,** I need to use an Anthropic OAuth access token for API calls and refresh it.
        
    - **Acceptance Criteria:**
        
        - The `Client.build_client/1` function, when configured for Anthropic OAuth, injects the `Authorization: Bearer [ACCESS_TOKEN]` header.
            
        - An Oban worker can use a stored refresh token to get a new access token from Anthropic.
            
- **1.5: OpenAI API Key Authentication**
    
    - **As the system,** I need to make a request to the OpenAI API using a Bearer token, ensuring the headers exactly match the `llxprt` reference.
        
    - **Reference:** 
        `llxprt` source code for OpenAI header construction.
        The OPENAI_API_KEY is stored as an ENV variable, it is also in ~/.zshrc
        
    - **Acceptance Criteria:**
        
        - The `Client.build_client/1` function, when called with `:openai`, constructs a Tesla client for API Key auth.
            
        - The client's middleware injects the following headers in **this exact order**:
            
            1. `Authorization`: "Bearer [API_KEY]"
                
            2. `OpenAI-Organization`: The org ID from config.
                
            3. `OpenAI-Beta`: "assistants v2"
                
            4. `User-Agent`: "llxprt/1.0"
                
            5. `Accept`: "application/json"
                
            6. `X-Client-Version`: "1.0.0"
                
        - A test can successfully make a simple API call and receive a valid `200 OK` response.
            
- **1.6: OpenAI OAuth - URL Generation & Token Exchange**
    
    - **As the system,** I need to generate an OpenAI OAuth 2.0 URL and handle the token exchange.
        
    - **Reference:** 
    OpenAI's official OAuth documentation.
    The OPENAI_API_KEY is stored as an ENV variable, it is also in ~/.zshrc
        
    - **Acceptance Criteria:**
        
        - The `LLMOrchestrator.Auth` module can generate a valid OpenAI OAuth 2.0 authorization URL.
            
        - The module can accept an authorization code and exchange it for an `access_token` and `refresh_token` from OpenAI's token endpoint.
            
- **1.7: OpenAI OAuth - Authenticated Call & Refresh**
    
    - **As the system,** I need to use an OpenAI OAuth access token for API calls and refresh it.
        
    - **Acceptance Criteria:**
        
        - The `Client.build_client/1` function, when configured for OpenAI OAuth, injects the `Authorization: Bearer [ACCESS_TOKEN]` header.
            
        - An Oban worker can use a stored refresh token to get a new access token from OpenAI.
            
- **1.8: Gemini OAuth - URL Generation & Token Exchange**
    
    - **As the system,** I need to generate a Google OAuth 2.0 URL and handle the token exchange, mimicking the `gemini-cli` flow.
        
    - **Reference:** `gemini-cli` OAuth implementation and Google Identity docs: [https://developers.google.com/identity/protocols/oauth2/native-app](https://developers.google.com/identity/protocols/oauth2/native-app "null")
        
    - **Acceptance Criteria:**
        
        - The `LLMOrchestrator.Auth` module generates a valid Google OAuth 2.0 URL with PKCE.
            
        - The module can exchange an authorization code and `code_verifier` for an `access_token` and `refresh_token` from Google's token endpoint (`https://oauth2.googleapis.com/token`).
            
- **1.9: Gemini OAuth - Authenticated Call & Refresh**
    
    - **As the system,** I need to use a Gemini OAuth access token to make an API call and implement a background job to refresh it.
        
    - **Reference:** `gemini-cli` authenticated requests.
        
    - **Acceptance Criteria:**
        
        - The `Client.build_client/1` function, when configured for Gemini OAuth, injects the `Authorization: Bearer [ACCESS_TOKEN]` header.
            
        - An Oban worker can use a stored refresh token to request a new access token from Google.
            
- **1.10: Response Streaming Foundation**
    
    - **As the system,** I need the HTTP client to process a chunked HTTP response and send each chunk to a calling process.
        
    - **Acceptance Criteria:**
        
        - A function exists that takes a provider, a request body, and the `pid` of a calling process.
            
        - When making a streaming request, each chunk of the response body is received by the client.
            
        - For each chunk received, a message (e.g., `{:stream_chunk, chunk_data}`) is sent to the calling process's `pid`.
            
        - A final message (e.g., `:stream_end`) is sent when the response is complete.
            

## **Epic 2: Core System & Persistence**

**Goal:** To establish the backend infrastructure, including database schemas and background job processing, to support all application functions.

**Micro Stories:**

- **2.1: Ecto & PostgreSQL Setup**
    
    - **As the system,** I need Ecto configured with a PostgreSQL adapter and a primary repository module.
        
    - **Acceptance Criteria:**
        
        - The application's dependencies in `mix.exs` include `ecto_sql` and `postgrex`.
            
        - A repository module (e.g., `LLMOrchestrator.Repo`) is created and configured in `config/config.exs`.
            
        - A `priv/repo/migrations` directory is created.
            
        - A test can successfully execute a simple Ecto query (e.g., `Repo.all(from p in "pg_database")`) to verify the database connection.
            
- **2.2: `saved_authentications` Schema & Migrations**
    
    - **As the system,** I need a database table to securely store user-provided credentials for each provider.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.SavedAuthentication` is created.
            
        - The schema includes fields for `provider` (enum), `auth_type` (enum: :api_key, :oauth), `credentials` (jsonb, encrypted), `expires_at` (utc_datetime, nullable), and timestamps.
            
        - A migration file is generated and successfully run to create the `saved_authentications` table in the database.
            
        - The `credentials` field must use an encryption library like `cloak_ecto` to ensure tokens are stored encrypted at rest.
            
- **2.3: `sessions` Schema & Migrations**
    
    - **As the system,** I need a database table to store the configuration and state for each individual LLM chat session.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.Session` is created.
            
        - The schema includes fields for `session_id` (string, unique), `agent_name` (string), `provider` (enum), `model` (string), `auth_type` (enum: :api_key, :oauth), `working_directory` (string), `system_prompt` (text), and timestamps.
            
        - A migration file is generated and successfully run to create the `sessions` table.
            
- **2.4: `conversations` and `messages` Schemas & Migrations**
    
    - **As the system,** I need database tables to store the complete history of every API call and response for auditing and context rebuilding.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.Conversation` is created with a `session_id` and timestamps.
            
        - An Ecto schema `LLMOrchestrator.Schema.Message` is created that `belongs_to` a `Conversation`.
            
        - The `messages` table includes fields for `role` (enum: :system, :user, :assistant, :tool), `raw_request` (jsonb), `raw_response` (jsonb), `latency_ms` (integer), and timestamps.
            
        - Migration files are generated and successfully run to create both tables with a foreign key relationship.
            
- **2.5: Basic Oban Configuration**
    
    - **As the system,** I need the Oban library configured to process background jobs using the PostgreSQL database.
        
    - **Acceptance Criteria:**
        
        - The `oban` dependency is added to `mix.exs`.
            
        - Oban is configured in `config/config.exs` to use the primary application `Repo`.
            
        - A basic queue (e.g., `default`) is defined.
            
        - Oban is added to the application's supervision tree.
            
        - A test can successfully insert and execute a simple "hello world" Oban worker.
            
- **2.6: Basic Redis Integration**
    
    - **As the system,** I need the Redix library configured to connect to a Redis server for managing real-time session state.
        
    - **Acceptance Criteria:**
        
        - The `redix` dependency is added to `mix.exs`.
            
        - Redix is configured in `config/config.exs` with the Redis server URL.
            
        - Redix is added to the application's supervision tree.
            
        - A test can successfully execute a `PING` command and receive a `PONG` response to verify the connection.
            

## **Epic 3: Agent Capabilities & Tooling**

**Goal:** To empower agents with a comprehensive, unrestricted set of tools for file system access, code execution, MCP integration, and inter-agent collaboration.

**Micro Stories:**

- **3.1: `agent_templates` Schema & Migrations**
    
    - **As the system,** I need a database table to store reusable agent configurations, including their persona, model, and toolset.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.AgentTemplate` is created.
            
        - The schema includes fields for `name` (string, unique), `role` (string), `system_prompt` (text), `preferred_provider` (string), `preferred_model` (string), `tools` (array of strings), and `mcps` (array of strings).
            
        - A migration file is generated and successfully run to create the `agent_templates` table.
            
- **3.2: `tools` Schema & Migrations**
    
    - **As the system,** I need a database table to define and manage the availability of all internal tools.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.Tool` is created.
            
        - The schema includes `name` (string, unique), `description` (text), `parameters` (jsonb), and `is_enabled` (boolean, default: true).
            
        - A migration is run to create the `tools` table.
            
        - A seed script is created to populate the table with the initial set of tools (read_file, write_file, etc.).
            
- **3.3: `mcp_servers` Schema & Migrations**
    
    - **As the system,** I need a database table to store connection details for external MCP servers.
        
    - **Acceptance Criteria:**
        
        - An Ecto schema `LLMOrchestrator.Schema.McpServer` is created.
            
        - The schema includes `name` (string, unique), `url` (string), `description` (text), and `is_enabled` (boolean, default: true).
            
        - A migration is run to create the `mcp_servers` table.
            
- **3.4: File System Tool - Read & Write**
    
    - **As an agent,** I need the ability to read the contents of a file and write new content to a file at a specified path, but only if the tool is enabled in the database.
        
    - **Acceptance Criteria:**
        
        - A `Tool` module exposes `read_file(path)` and `write_file(path, content)` functions.
            
        - Before executing, the functions check the `tools` table to ensure `read_file` and `write_file` are enabled.
            
        - `write_file` automatically creates parent directories if they don't exist.
            
        - These tools operate relative to the session's `working_directory`.
            
- **3.5: Code Execution Tool - Direct Execution**
    
    - **As an agent,** I need to execute arbitrary code snippets, but only if the `execute_code` tool is enabled in the database.
        
    - **Acceptance Criteria:**
        
        - A `Tool` module exposes `execute(code, language, opts)`.
            
        - The function checks the `tools` table to ensure `execute_code` is enabled.
            
        - The function supports at least `elixir`, `python`, `javascript`, and `bash`.
            
        - It uses `System.cmd/3` to run the code, capturing and returning both stdout and stderr.
            
- **3.6: MCP (Model Context Protocol) Integration from DB**
    
    - **As an agent,** I need to be able to discover and interact with external MCP servers that are configured and enabled in the database.
        
    - **Acceptance Criteria:**
        
        - The system queries the `mcp_servers` table for all records where `is_enabled` is true.
            
        - A `Tool` is available to list tools from a registered MCP server.
            
        - A `Tool` is available to invoke a specific tool on an MCP server with given parameters.
            
- **3.7: Sub-Agent as a Tool**
    
    - **As a primary agent,** I need to be able to invoke another, specialized agent as a tool to delegate a complex task, but only if the `sub_agent` tool is enabled.
        
    - **Acceptance Criteria:**
        
        - The system can dynamically register any saved `AgentTemplate` as an available tool.
            
        - The `sub_agent` tool's availability is controlled via the `tools` table.
            
        - When a primary agent calls a sub-agent tool, a new, temporary session is initiated for the sub-agent.
            
        - The final response from the sub-agent is returned as the result of the tool call to the primary agent.
            
- **3.8: Tooling Research & Dictionary Creation**
    
    - **As the project owner,** I need a comprehensive document that inventories all tools available in the `llxprt` and `gemini-cli` source code.
        
    - **Acceptance Criteria:**
        
        - An agent will analyze the source code of both `llxprt` and `gemini-cli`.
            
        - A new file, `tool_dictionary.md`, is created at `docs/specs/`.
            
        - This file contains a list of every tool found in both reference projects, which will be used to seed the `tools` table.
            

## **Epic 4: Web User Interface**

**Goal:** To create a comprehensive, real-time web interface using Phoenix LiveView for managing all aspects of the application.

**Micro Stories:**

- **4.1: Authentication Management UI**
    
    - **As a user,** I need a page where I can view, add, and remove my API keys and OAuth credentials for each provider.
        
    - **Acceptance Criteria:**
        
        - A LiveView page at `/auth` lists all credentials from the `saved_authentications` table.
            
        - The page provides a form to add a new API key for a selected provider.
            
        - The page provides a button for each OAuth provider that, when clicked, generates the auth URL and displays it for me to copy.
            
        - There is a text input to paste the return code to complete the OAuth handshake.
            
        - Each saved credential has a "delete" button.
            
- **4.2: Tool Management UI**
    
    - **As a user,** I need a settings page where I can see all available internal tools and enable or disable them globally.
        
    - **Acceptance Criteria:**
        
        - A LiveView page at `/settings/tools` lists all tools from the `tools` table.
            
        - Each tool has a toggle switch that updates the `is_enabled` field in the database.
            
        - The UI provides a way to view the description and parameters for each tool.
            
- **4.3: MCP Server Management UI**
    
    - **As a user,** I need a settings page where I can add, edit, and remove configurations for external MCP servers.
        
    - **Acceptance Criteria:**
        
        - A LiveView page at `/settings/mcp` lists all servers from the `mcp_servers` table.
            
        - The page includes a form to add a new MCP server (name, URL, description).
            
        - Each server in the list has an "edit" button and a "delete" button.
            
        - Each server has a toggle switch to control its `is_enabled` status.
            
- **4.4: Main Dashboard & Session Creation UI**
    
    - **As a user,** I need a main dashboard to view my active sessions and create new ones.
        
    - **Acceptance Criteria:**
        
        - A LiveView page at `/` serves as the main dashboard.
            
        - The page displays a card for each active session, retrieved from the `sessions` table.
            
        - Each card shows summary information (e.g., `agent_name`, `provider`, `model`).
            
        - Clicking a card navigates to the chat page for that session (`/sessions/:id`).
            
        - The page includes a "New Session" button that opens a form to configure and start a new session, creating a new record in the `sessions` table.
            
        - A panel on the dashboard displays real-time system stats (CPU/memory usage), potentially using a library like `live_dashboard`.
            
- **4.5: Chat Interface - Message Display**
    
    - **As a user,** I need a real-time chat interface to interact with an agent and see its history.
        
    - **Acceptance Criteria:**
        
        - A LiveView page at `/sessions/:id` displays the full message history from the `messages` table for the given session.
            
        - User messages, agent responses, and tool outputs are clearly distinguished visually.
            
        - The UI updates in real-time via Phoenix PubSub as new messages (including streaming "thoughts") are generated.
            
        - A "thinking..." indicator is displayed while the agent is processing a request.
            
        - A toggle button allows the user to expand/collapse the detailed streaming "thoughts" for each agent message.
            
- **4.6: Chat Interface - On-the-fly Controls**
    
    - **As a user,** I need to be able to change the session's configuration on the fly from the chat page.
        
    - **Acceptance Criteria:**
        
        - Dropdown menus on the chat page allow me to change the `provider`, `model`, and `auth_type` for the current session.
            
        - A side panel or modal allows me to view and toggle the availability of specific tools and MCPs for the current session only.
            
        - Changes made in the UI are reflected in the session's context for the _next_ message sent to the agent.
            

## **Epic 5: Token & Cost Management**

**Goal:** To accurately track token usage and the associated monetary cost for every API call and display it to the user.

**Micro Stories:**

- **5.1: Add Token Tracking Fields to `messages` Schema**
    
    - **As the system,** I need to store token usage and cost details for every message exchange.
        
    - **Acceptance Criteria:**
        
        - The `messages` Ecto schema is updated to include `request_tokens` (integer), `response_tokens` (integer), and `total_cost_usd` (decimal).
            
        - A new migration file is generated and successfully run to add these columns to the `messages` table.
            
- **5.2: Parse Token Usage from Provider Responses**
    
    - **As the system,** I need to extract the token count information from the API responses of all three providers, as each has a different format.
        
    - **Acceptance Criteria:**
        
        - A new module, `LLMOrchestrator.TokenTracker`, is created.
            
        - It contains separate functions (`parse_anthropic_usage`, `parse_openai_usage`, `parse_gemini_usage`) that take a raw API response body.
            
        - Each function correctly extracts the input/request and output/response token counts and returns them in a standardized map, e.g., `%{request_tokens: X, response_tokens: Y}`.
            
        - The functions are resilient to missing usage data in the response.
            
- **5.3: Calculate and Store Cost per Message**
    
    - **As the system,** I need to calculate the approximate monetary cost of each API call based on the model and token count.
        
    - **Acceptance Criteria:**
        
        - The `TokenTracker` module has a `calculate_cost/3` function that takes a model name, request tokens, and response tokens.
            
        - A configuration file (`config/token_costs.exs`) stores the cost per million tokens (input and output) for various models (e.g., `claude-3-opus-20240229`, `gpt-4-turbo`, `gemini-1.5-pro-latest`).
            
        - After a successful API call, the system uses this function to calculate the cost and saves it to the `total_cost_usd` field in the corresponding `messages` record.
            
- **5.4: Aggregate Token Counts for Session UI**
    
    - **As a user,** I need to see the total token usage and cost for my current session, updated in real-time.
        
    - **Acceptance Criteria:**
        
        - The chat page LiveView (`/sessions/:id`) performs a query to sum the `request_tokens`, `response_tokens`, and `total_cost_usd` for all messages associated with the current session.
            
        - The aggregated totals (e.g., "Total Tokens: 15,234", "Session Cost: $0.08") are displayed prominently on the chat UI.
            
        - This display updates automatically after each new message is received from the agent.
            
- **5.5: Fallback Token Counting**
    
    - **As the system,** I need a reliable way to estimate token counts locally if the provider's API response does not include usage data.
        
    - **Acceptance Criteria:**
        
        - An Elixir tokenization library (e.g., `Bunt`) is added as a dependency.
            
        - The `TokenTracker` module has a new function, `count_tokens_local/2`, that takes a string of text and a model name, and returns the estimated token count.
            
        - The main token parsing logic is updated: if the API response lacks usage data, it must call `count_tokens_local` on the raw request and response content to populate the `request_tokens` and `response_tokens` fields.
            

## **Epic 6: Terminal User Interface (TUI)**

**Goal:** To create a standalone, multi-platform TUI client that connects to the main application's API for a fast, keyboard-driven user experience.

**Micro Stories:**

- **6.1: TUI API - Secure Connection**
    
    - **As the TUI client,** I need a secure way to authenticate with the main Phoenix application's API.
        
    - **Acceptance Criteria:**
        
        - The Phoenix app exposes a new API endpoint (e.g., `/api/v1/tui/connect`).
            
        - The TUI client can be configured with a static API token.
            
        - The API uses a plug to verify this token on all TUI-related endpoints, rejecting unauthorized requests.
            
- **6.2: TUI API - Session Management & Streaming**
    
    - **As the TUI client,** I need API endpoints to list, create, and connect to chat sessions, including full support for streaming.
        
    - **Acceptance Criteria:**
        
        - An API endpoint exists to list all available sessions.
            
        - An API endpoint exists to create a new session.
            
        - A WebSocket endpoint (e.g., `/socket/tui`) is created for real-time communication.
            
        - The TUI client can connect to this WebSocket, join a specific session's channel (e.g., `tui:session_id`), and receive all messages, including the detailed "thought" process streams, as they are generated by the backend.
            
- **6.3: TUI Application - Basic Layout & Connection**
    
    - **As a user,** I need a basic TUI application that can connect to the backend and display a list of my sessions.
        
    - **Reference:** `ratatouille` library for TUI construction and the `source/the-maestro` project for a bootstrap example of display and interactivity.
        
    - **Acceptance Criteria:**
        
        - A new Elixir project is created for the TUI.
            
        - The TUI uses a library like `ratatouille` to render the interface.
            
        - On startup, the TUI reads its configuration (API URL and token) and calls the API to fetch and display a list of available sessions.
            
- **6.4: TUI Application - Tabbed Chat Interface**
    
    - **As a user,** I need to be able to select a session and interact with it in a tabbed interface, allowing me to switch between multiple active chats.
        
    - **Acceptance Criteria:**
        
        - The TUI displays active sessions as tabs at the bottom or top of the screen.
            
        - I can use keyboard shortcuts (e.g., Ctrl+Tab) to cycle between tabs.
            
        - Each tab maintains its own connection to a session channel via the WebSocket and displays the message history.
            
        - A text input area at the bottom of the screen allows me to send messages to the currently active session.
            
- **6.5: TUI Application - Standalone Executable**
    
    - **As a user,** I need to be able to run the TUI application as a single, standalone executable on my machine without needing to install Elixir.
        
    - **Reference:** `burrito` library for packaging.
        
    - **Acceptance Criteria:**
        
        - The TUI project is configured with the `burrito` library.
            
        - A `mix release` command is defined that builds the TUI into a single, executable file for at least one target platform (e.g., macOS, Linux, or Windows).
            
        - The resulting executable can be run from any directory and successfully connects to the main application.


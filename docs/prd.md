# The Maestro - Product Requirements Document (PRD)

Version: 2.0

Status: COMPLETE - 100% COMPREHENSIVE

## 1. Introduction & Goals

**Product Name:** The Maestro

**Introduction:** The Maestro is a specialized, single-user LLM orchestration platform designed to function as a personal AI agent development team. It provides a unified interface, accessible via both a web UI and a terminal UI (TUI), for managing multiple concurrent LLM sessions across different providers (Anthropic, OpenAI, Google Gemini). The core purpose is to empower a solo developer to leverage a team of AI agents that can collaborate on coding projects with extensive access to tools, files, and custom contexts.

**Project Goals:**

- **Goal 1: Unify Multi-Provider Agents:** Create a single application to run and manage concurrent sessions with models from Anthropic, OpenAI, and Google Gemini, enabling them to work in concert.
    
- **Goal 2: Achieve Exact API Fidelity:** Ensure all authentication and API communication with providers _exactly_ mimics the behavior of the `llxprt` and `gemini-cli` reference applications, down to the order of headers.
    
- **Goal 3: Provide Powerful Tooling:** Equip LLM agents with a comprehensive and unrestricted set of tools, including file system access, code execution, and the ability to use other agents as sub-agents.
    
- **Goal 4: Enable Deep Customization:** Allow for dynamic, on-the-fly configuration of each agent session, including system prompts, personas, working directories, and available tools.
    
- **Goal 5: Offer Dual Interfaces:** Deliver a rich, real-time web interface using Phoenix LiveView and a separate, standalone TUI client for flexible interaction.
    

## 2. The Problem & The User

#### **Problem Statement**

A solo developer managing complex software projects lacks the tooling to efficiently orchestrate multiple, specialized AI agents as a cohesive development team. Interacting with LLMs through separate, isolated chat interfaces is fragmented and manually intensive. There is no unified platform that allows a developer to run concurrent sessions across different providers, grant them direct access to a project's files and tools, and manage their context dynamically. This fragmentation prevents the developer from truly leveraging AI as a force multiplier and a collaborative coding partner.

#### **User Personas**

This platform is built for a single, specific user type:

- **Persona:** Alex, the Power Developer
    
- **Role:** Solo Technical Founder / Principal Engineer
    
- **Description:** Alex is a highly skilled developer building a sophisticated application using Elixir. As a solo operator, they handle everything from architecture and backend development to frontend and TUI implementation. Alex is not looking for a simple AI assistant; they need a command center to build and direct their own team of specialized AI agents.
    
- **Needs & Goals:**
    
    - To augment their workflow by offloading coding, research, and documentation tasks to a team of AI agents.
        
    - To maintain full control over the agents' environment, including file access, available tools, and dynamic system prompts.
        
    - To use the best model for the job (e.g., Claude for code generation, Gemini for research) within a single, unified project context.
        
    - To have flexible access to the system through either a powerful web UI or a fast, keyboard-driven TUI.
        
    - To prioritize power and flexibility over restrictive security measures; the agents should have the same level of access as Alex does.
        

## 3. Scope & Features (High-Level Epics)

1. **Epic 1: Foundational Authentication & API Fidelity:**
    
    - This is the highest priority epic. It involves creating a multi-provider HTTP client layer and authentication management system that **exactly mirrors** the implementation, headers, and authentication flows of the `llxprt` and `gemini-cli` applications for Anthropic, OpenAI, and Gemini. This includes API key and OAuth methods.
        
2. **Epic 2: Core System & Persistence:**
    
    - This epic covers the backend infrastructure, including setting up the PostgreSQL database schemas for conversations, sessions, and credentials. It also includes configuring Redis for real-time state management and Oban for background jobs like token refreshing.
        
3. **Epic 3: Agent Capabilities & Tooling:**
    
    - This epic focuses on empowering the agents. It includes implementing a comprehensive set of tools for file system access, code execution, and system commands. Crucially, this epic also covers the full implementation of the **Model Context Protocol (MCP)** to allow agents to discover and use MCP servers, as well as the functionality to use other configured agents as sub-agents.
        
4. **Epic 4: Web User Interface:**
    
    - This covers the creation of the Phoenix LiveView-based web application. It includes the authentication management pages, the card-based session dashboard with system monitoring, and the real-time chat interface with on-the-fly customization of personas, models, and tools.
        
5. **Epic 5: Token & Cost Management:**
    
    - This covers the implementation of token usage tracking. The system will monitor and attribute token consumption to specific activities (conversation, tool use, etc.) and store this data with the conversation history.
        
6. **Epic 6: Terminal User Interface (TUI):**
    
    - This epic involves building the standalone, multi-platform TUI client. It will connect to the main application via a dedicated API. Key features include tab-based management of multiple sessions and the **API capability to receive passthrough streams** of the agents' "thought" processes.
        

## 4. Features & Requirements

### **Epic 1: Foundational Authentication & API Fidelity**

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
        
    - **Reference:** `llxprt` source code for OpenAI header construction.
        
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
        
    - **Reference:** OpenAI's official OAuth documentation.
        
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
            

### **Epic 2: Core System & Persistence**

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
            

### **Epic 3: Agent Capabilities & Tooling**

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
            

### **Epic 4: Web User Interface**

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
            

### **Epic 5: Token & Cost Management**

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
            

### **Epic 6: Terminal User Interface (TUI)**

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


## 5. Success Metrics & KPIs

**Goal:** Define measurable criteria for project success and ongoing performance monitoring.

### **Primary Success Metrics**

- **Technical Performance:**
    
    - **API Fidelity:** 100% compatibility with `llxprt` and `gemini-cli` reference implementations (verified through automated header/response comparison tests)
        
    - **System Reliability:** 99.5% uptime for web interface, <2 second response time for API calls
        
    - **Multi-Provider Support:** Successfully authenticate and maintain concurrent sessions with all 3 providers (Anthropic, OpenAI, Google Gemini)
        
- **User Experience:**
    
    - **Session Management:** Support for minimum 10 concurrent agent sessions without performance degradation
        
    - **Tool Integration:** 95% success rate for file operations, code execution, and MCP server interactions
        
    - **Interface Responsiveness:** Web UI real-time updates <500ms latency, TUI keyboard response <100ms
        

### **Key Performance Indicators (KPIs)**

- **Functionality KPIs:**
    
    - **Authentication Success Rate:** >99% for both API key and OAuth flows
        
    - **Message Delivery:** 100% message persistence and retrieval accuracy
        
    - **Token Tracking Accuracy:** <5% variance between tracked and actual provider-reported token usage
        
- **Quality KPIs:**
    
    - **Code Coverage:** >90% for critical paths (authentication, session management, tool execution)
        
    - **Error Rate:** <1% for core operations (session creation, message sending, tool execution)
        
    - **Data Integrity:** 100% accuracy in conversation history and session state persistence
        

### **Success Validation Criteria**

- **MVP Success:** Alex (target persona) can successfully run 3+ concurrent sessions across different providers, execute file operations and code, and switch seamlessly between web UI and TUI
    
- **Production Ready:** System handles 20+ concurrent sessions, integrates with 5+ MCP servers, and maintains <2 second response times under load
    
- **Long-term Success:** Platform becomes Alex's primary development interface, replacing isolated AI chat tools, with measurable productivity gains in coding tasks


## 6. Timeline & Roadmap

**Goal:** Establish clear delivery milestones and dependencies for all epics.

### **High-Level Timeline**

- **Phase 1 (Weeks 1-4): Foundation** - Epic 1 & 2 (Authentication & Core System)
    
- **Phase 2 (Weeks 5-8): Agent Capabilities** - Epic 3 (Tooling & MCP Integration)
    
- **Phase 3 (Weeks 9-12): User Interfaces** - Epic 4 & 5 (Web UI & Token Management)
    
- **Phase 4 (Weeks 13-16): TUI & Polish** - Epic 6 (Terminal Interface)
    

### **Detailed Milestone Breakdown**

#### **Phase 1: Foundation (Critical Path)**

**Week 1-2: Authentication Infrastructure**

- Epic 1.1-1.5: Anthropic API Key + OAuth implementation
    
- Epic 1.6-1.7: OpenAI API Key + OAuth implementation
    
- **Risk:** OAuth approval delays from providers
    

**Week 3-4: Core System Setup**

- Epic 2.1-2.4: Database schemas and migrations
    
- Epic 2.5-2.6: Oban and Redis integration
    
- Epic 1.8-1.10: Gemini OAuth + streaming foundation
    

#### **Phase 2: Agent Capabilities**

**Week 5-6: Tool Framework**

- Epic 3.1-3.4: Agent templates and core file system tools
    
- Epic 3.8: Tool inventory and database seeding
    

**Week 7-8: Advanced Tooling**

- Epic 3.5-3.7: Code execution, MCP integration, sub-agent capabilities
    

#### **Phase 3: User Interfaces**

**Week 9-10: Web UI Foundation**

- Epic 4.1-4.3: Authentication management and settings pages
    
- Epic 5.1-5.3: Token tracking implementation
    

**Week 11-12: Chat Interface**

- Epic 4.4-4.6: Dashboard and real-time chat interface
    
- Epic 5.4-5.5: Token aggregation and fallback counting
    

#### **Phase 4: TUI & Finalization**

**Week 13-14: TUI Development**

- Epic 6.1-6.3: API endpoints and basic TUI application
    

**Week 15-16: TUI Polish & Packaging**

- Epic 6.4-6.5: Tabbed interface and standalone executable
    

### **Critical Path Dependencies**

- **Week 1-2:** OAuth approvals from providers (potential 1-2 week delay risk)
    
- **Week 3:** Database design must be finalized before UI development begins
    
- **Week 9:** Core tooling framework must be complete before web UI integration
    
- **Week 13:** Web API must be stable before TUI development


## 7. Risk Assessment & Mitigation

**Goal:** Identify potential project risks and establish mitigation strategies.

### **High-Impact Risks**

#### **1. Provider API Changes/Deprecation**

- **Risk Level:** HIGH
    
- **Impact:** Could break authentication or streaming functionality
    
- **Probability:** Medium (providers frequently update APIs)
    
- **Mitigation:**
    
    - Implement comprehensive API monitoring and alerting
        
    - Maintain multiple authentication methods per provider
        
    - Create API compatibility test suite with daily execution
        
    - Establish direct communication channels with provider developer relations teams
        

#### **2. OAuth Approval Delays**

- **Risk Level:** HIGH
    
- **Impact:** Could delay Phase 1 by 2-4 weeks
    
- **Probability:** Medium (OAuth apps require manual approval)
    
- **Mitigation:**
    
    - Submit OAuth applications immediately upon project start
        
    - Develop with API keys first, add OAuth as secondary implementation
        
    - Prepare detailed OAuth application documentation highlighting security measures
        
    - Have backup authentication strategies ready
        

#### **3. Performance Under Load**

- **Risk Level:** MEDIUM
    
- **Impact:** Poor user experience with multiple concurrent sessions
    
- **Probability:** Medium (Elixir/Phoenix handles concurrency well, but LLM APIs may be slow)
    
- **Mitigation:**
    
    - Implement connection pooling and request queuing
        
    - Add session-level resource limits and monitoring
        
    - Design asynchronous message handling from the start
        
    - Include load testing in Phase 3
        

### **Medium-Impact Risks**

#### **4. MCP Server Integration Complexity**

- **Risk Level:** MEDIUM
    
- **Impact:** May delay Epic 3 or reduce MCP functionality
    
- **Probability:** Medium (MCP is relatively new protocol)
    
- **Mitigation:**
    
    - Start MCP integration early in Phase 2
        
    - Create MCP server mocking for development
        
    - Focus on 2-3 high-value MCP servers initially
        
    - Design MCP integration as optional/pluggable feature
        

#### **5. Token Counting Accuracy**

- **Risk Level:** MEDIUM
    
- **Impact:** Inaccurate cost tracking and billing estimation
    
- **Probability:** Low (provider APIs generally include usage data)
    
- **Mitigation:**
    
    - Implement multiple token counting methods (API-provided + local estimation)
        
    - Regular validation against provider billing data
        
    - Conservative cost estimation as default
        
    - User-configurable cost limits and alerts
        

### **Low-Impact Risks**

#### **6. Database Migration Issues**

- **Risk Level:** LOW
    
- **Impact:** Development delays during schema changes
    
- **Mitigation:** Comprehensive migration testing and rollback procedures
    

#### **7. TUI Cross-Platform Compatibility**

- **Risk Level:** LOW
    
- **Impact:** Limited platform support for standalone executable
    
- **Mitigation:** Focus on primary platform (macOS/Linux), add Windows support in future iteration


## 8. Dependencies & Assumptions

**Goal:** Document external dependencies and underlying assumptions that could impact project success.

### **External Dependencies**

#### **Critical Dependencies**

- **Provider API Availability:**
    
    - Anthropic Claude API (api.anthropic.com)
        
    - OpenAI API (api.openai.com)
        
    - Google Generative AI API (generativelanguage.googleapis.com)
        
    - **Risk:** Service outages or API changes could break functionality
        
- **OAuth Approval Process:**
    
    - Anthropic OAuth application approval
        
    - OpenAI OAuth application approval
        
    - Google Cloud Console OAuth setup
        
    - **Risk:** Approval delays could impact timeline by 2-4 weeks
        

#### **Technical Dependencies**

- **Infrastructure:**
    
    - PostgreSQL database server
        
    - Redis server for session state management
        
    - Elixir/Erlang runtime environment
        
- **Third-Party Libraries:**
    
    - Phoenix LiveView for real-time web UI
        
    - Tesla HTTP client for API communication
        
    - Oban for background job processing
        
    - Ratatouille for TUI construction
        
    - Burrito for executable packaging
        

### **Key Assumptions**

#### **Technical Assumptions**

- **API Stability:** Provider APIs will maintain backward compatibility during development period
    
- **Rate Limits:** Current provider rate limits will accommodate development and testing needs
    
- **Authentication Methods:** All providers will continue supporting both API key and OAuth authentication
    
- **Streaming Support:** All target providers support server-sent events or similar streaming protocols
    

#### **User Assumptions**

- **Single-User Focus:** Target user (Alex) prefers power/flexibility over security restrictions
    
- **Technical Proficiency:** User is comfortable with command-line tools and technical configuration
    
- **Development Workflow:** User's primary use case is software development with file system access needs
    
- **Provider Selection:** User wants choice between providers based on task suitability, not cost optimization
    

#### **Business Assumptions**

- **Personal Use:** System designed for single-user, personal use rather than team collaboration
    
- **Self-Hosted:** User prefers self-hosted solution over SaaS offering
    
- **Integration Priority:** Direct API integration preferred over web scraping or unofficial methods
    

### **Assumption Validation Plans**

- **Technical Validation:** Create proof-of-concept implementations for each provider during Week 1
    
- **User Validation:** Regular check-ins with target persona (Alex) throughout development
    
- **API Validation:** Maintain automated tests against all provider APIs to detect changes early


## 9. Out of Scope

**Goal:** Clearly define what features and capabilities are explicitly NOT included in this version.

### **Explicitly Excluded Features**

#### **Multi-User & Collaboration**

- **Team Features:** No user management, permissions, or role-based access control
    
- **Session Sharing:** No ability to share sessions or conversations with other users
    
- **Collaborative Editing:** No real-time collaboration on documents or code
    
- **User Authentication:** No login system - single-user application assumed to run on trusted machine
    

#### **Advanced Analytics & Reporting**

- **Usage Analytics:** No detailed usage patterns, productivity metrics, or performance analytics dashboard
    
- **Cost Optimization:** No automatic provider switching based on cost or performance
    
- **Conversation Analytics:** No sentiment analysis, topic modeling, or conversation insights
    
- **Export/Reporting:** No PDF reports, conversation exports, or business intelligence features
    

#### **Enterprise Features**

- **Audit Logging:** No compliance-grade audit trails or security logging
    
- **High Availability:** No clustering, load balancing, or failover mechanisms
    
- **Backup/Recovery:** No automated backup systems or disaster recovery procedures
    
- **Enterprise Integration:** No LDAP, SAML, or enterprise SSO integration
    

### **Technical Limitations**

#### **Scalability Constraints**

- **Concurrent Users:** Designed for single user only
    
- **Session Limits:** Practical limit of ~50 concurrent sessions (not tested beyond this)
    
- **Data Retention:** No automated archiving or data lifecycle management
    

#### **Security Constraints**

- **Network Security:** No VPN integration, IP whitelisting, or network-level security
    
- **Encryption:** Basic credential encryption only, no end-to-end message encryption
    
- **Compliance:** No SOC2, HIPAA, or other compliance framework support
    

#### **Integration Limitations**

- **Version Control:** No direct Git integration or version control features
    
- **IDE Integration:** No VS Code extensions, IntelliJ plugins, or similar IDE integrations
    
- **Cloud Storage:** No integration with cloud storage providers (AWS S3, Google Drive, etc.)
    

### **Future Considerations**

#### **Potential V2 Features**

- Multi-user support with authentication system
    
- Advanced conversation search and organization
    
- Plugin system for custom tools beyond MCP
    
- Mobile companion app for session monitoring
    

#### **Integration Roadmap**

- VS Code extension for inline agent interaction
    
- Git hooks for automatic code review using agents
    
- CI/CD pipeline integration for automated testing with agents
    

### **Boundary Clarifications**

- **File System Access:** Unlimited within user's permissions, but no privilege escalation
    
- **Code Execution:** Supports common languages but no custom runtime environments
    
- **Provider Support:** Limited to Anthropic, OpenAI, and Google Gemini initially
    
- **MCP Protocol:** Implements current MCP specification, may not support future protocol versions without updates


## 10. Non-Functional Requirements

**Goal:** Define performance, security, reliability, and usability requirements that ensure system quality.

### **Performance Requirements**

#### **Response Time & Throughput**

- **API Response Time:** 95th percentile < 2 seconds for LLM provider API calls
    
- **Web UI Responsiveness:** Page loads < 1 second, real-time updates < 500ms
    
- **TUI Performance:** Keyboard input response < 100ms, screen refresh < 50ms
    
- **Database Queries:** 95th percentile < 500ms for conversation history retrieval
    
- **Concurrent Session Support:** Handle 20+ active sessions simultaneously without degradation
    

#### **Resource Utilization**

- **Memory Usage:** < 2GB RAM for 10 concurrent sessions, < 4GB for 20 sessions
    
- **CPU Usage:** < 20% average CPU utilization during normal operation
    
- **Storage:** < 100MB storage growth per 1000 messages (including metadata)
    
- **Network:** Support for limited bandwidth scenarios (>= 1Mbps for acceptable performance)
    

### **Reliability & Availability Requirements**

#### **System Availability**

- **Web Interface Uptime:** 99.5% availability (target ~4 hours downtime per year)
    
- **Data Persistence:** 100% message and session state persistence accuracy
    
- **Graceful Degradation:** System remains functional if 1 of 3 LLM providers is unavailable
    
- **Error Recovery:** Automatic retry for transient failures, graceful handling of permanent failures
    

#### **Data Integrity**

- **Message Accuracy:** 100% fidelity between sent/received messages and stored conversation history
    
- **Session State:** Real-time synchronization between web UI, TUI, and backend state
    
- **Credential Security:** Encrypted storage of all API keys and OAuth tokens
    
- **Backup Strategy:** Daily automated database backups with 30-day retention
    

### **Security Requirements**

#### **Authentication & Authorization**

- **Credential Encryption:** AES-256 encryption for stored API keys and OAuth tokens
    
- **Local Access Only:** No network-exposed authentication endpoints (single-user, local deployment)
    
- **Session Security:** Secure session management with timeout handling
    
- **API Token Management:** Secure storage and automatic refresh of OAuth tokens
    

#### **Data Protection**

- **Local Data Storage:** All data stored locally, no external data transmission except to LLM providers
    
- **Provider API Security:** Use secure HTTPS connections with certificate validation for all provider communications
    
- **Audit Trail:** Log all API calls, tool executions, and system configuration changes
    
- **Data Sanitization:** Input validation and output sanitization to prevent injection attacks
    

### **Usability & Accessibility Requirements**

#### **Web UI Standards**

- **Responsive Design:** Support for screen sizes from 1024x768 to 4K displays
    
- **Accessibility:** WCAG 2.1 AA compliance for keyboard navigation and screen readers
    
- **Browser Support:** Compatible with Chrome 90+, Firefox 88+, Safari 14+
    
- **Real-time Updates:** Live conversation updates without page refreshes
    

#### **TUI Standards**

- **Cross-Platform:** Support for macOS, Linux (Ubuntu 20.04+), Windows 10+
    
- **Terminal Compatibility:** Works with common terminals (iTerm2, Terminal.app, Windows Terminal)
    
- **Keyboard Navigation:** Full functionality available via keyboard shortcuts
    
- **Screen Reader Support:** Basic compatibility with terminal screen readers
    

### **Scalability Requirements**

#### **Data Volume**

- **Conversation History:** Support for 100,000+ messages per session without performance impact
    
- **Session Management:** Handle 100+ saved sessions with instant switching
    
- **File Operations:** Process files up to 100MB through agent tools
    
- **Database Growth:** Graceful handling of databases up to 10GB
    

#### **Extensibility**

- **Tool Plugin Architecture:** Support for 50+ simultaneous tools without performance degradation
    
- **MCP Server Integration:** Connect to 20+ MCP servers simultaneously
    
- **Provider Extensibility:** Architecture supports adding new LLM providers without core changes
    
- **Configuration Scaling:** Handle complex agent templates with 1000+ character system prompts
    

### **Compatibility Requirements**

#### **System Requirements**

- **Operating Systems:** macOS 11+, Ubuntu 20.04+, Windows 10+
    
- **Runtime Dependencies:** Elixir 1.14+, PostgreSQL 13+, Redis 6.2+
    
- **Hardware:** Minimum 4GB RAM, 10GB storage, 1GHz dual-core processor
    
- **Network:** Broadband internet connection for LLM provider API access
    

#### **Integration Requirements**

- **File System:** Read/write access to user's file system within standard permissions
    
- **Process Execution:** Ability to execute common development tools (python, node, etc.)
    
- **Network Access:** HTTPS outbound access to LLM provider APIs
    
- **Database:** PostgreSQL with standard connection pooling


## 11. Business Justification

**Goal:** Articulate the business value, competitive advantages, and strategic rationale for building The Maestro.

### **Problem-Solution Fit**

#### **Current Pain Points**

- **Fragmented AI Interactions:** Developers currently use separate interfaces for different LLM providers, creating context-switching overhead and workflow fragmentation
    
- **Limited Tool Integration:** Existing AI chat interfaces lack direct access to development tools, file systems, and project contexts
    
- **Single-Provider Lock-in:** Most solutions tie users to a single LLM provider, preventing optimal model selection per task
    
- **Manual Context Management:** Developers manually copy-paste code, files, and context between AI tools and development environments
    

#### **The Maestro Solution Value**

- **Unified Command Center:** Single interface managing multiple AI providers with shared project context
    
- **Native Development Integration:** Direct file system access, code execution, and development tool integration
    
- **Provider Flexibility:** Choose optimal models per task (Claude for code, GPT-4 for analysis, Gemini for research)
    
- **Seamless Context Sharing:** Persistent project context across all agent interactions
    

### **Target Market Analysis**

#### **Primary Market: Power Developers**

- **Market Size:** ~500K solo technical founders and senior developers globally working on complex projects
    
- **Market Characteristics:**
    
    - High technical proficiency and comfort with self-hosted solutions
        
    - Multi-platform development requiring diverse AI capabilities
        
    - Budget flexibility for productivity tools ($50-500/month LLM API costs)
        
    - Value efficiency and power-user features over simplicity
        

#### **Competitive Landscape**

**Direct Competitors:**
- **Cursor IDE:** AI-integrated development environment, but limited to single provider and IDE-locked
    
- **GitHub Copilot Chat:** Code-focused AI assistant, but limited tooling and single-provider
    
- **Continue.dev:** Open-source AI coding assistant, but lacks multi-provider orchestration
    

**Competitive Advantages:**
- **Multi-Provider Orchestration:** Unique ability to run concurrent sessions across 3+ providers
    
- **Unrestricted Tool Access:** Full file system and code execution capabilities
    
- **Dual Interface Strategy:** Both rich web UI and efficient TUI for different use cases
    
- **MCP Protocol Support:** Future-proof integration with emerging AI tool ecosystem
    

### **ROI & Value Proposition**

#### **Developer Productivity Gains**

- **Context Switching Reduction:** Eliminate 20+ daily context switches between AI tools and development environment
    
- **Optimal Model Selection:** 30-50% better task outcomes through provider-task matching
    
- **Automated Workflows:** 60-80% reduction in manual file operations and code execution through agent delegation
    
- **Research Efficiency:** 40-60% faster technical research through specialized agent configurations
    

#### **Cost-Benefit Analysis**

**Development Investment:**
- **Time:** 16 weeks development time (1 developer)
    
- **Infrastructure:** $50-100/month hosting costs for development
    
- **API Costs:** $200-500/month during development and testing
    

**Value Delivered:**
- **Time Savings:** 2-4 hours/day productivity gains through workflow optimization
    
- **Quality Improvement:** Reduced errors through AI-assisted code review and testing
    
- **Learning Acceleration:** Faster adoption of new technologies through specialized AI research agents
    
- **Flexibility Value:** Ability to adapt to changing LLM landscape without vendor lock-in
    

### **Strategic Rationale**

#### **Technology Strategy**

- **Future-Proofing:** Architecture designed to adapt to rapidly evolving LLM landscape
    
- **Vendor Independence:** Multi-provider approach reduces risk of single-provider service changes
    
- **Open Integration:** MCP protocol support enables ecosystem participation
    
- **Self-Hosted Control:** Full data control and customization for power users
    

#### **Market Positioning**

- **Power User Focus:** Target sophisticated developers who value flexibility over simplicity
    
- **Developer Tool Category:** Position as essential development infrastructure, not just AI assistant
    
- **Premium Positioning:** Justify higher development investment through advanced capabilities
    
- **Community Potential:** Open architecture enables community contributions and extensions
    

### **Success Metrics & Business Impact**

#### **Adoption Metrics**

- **Primary Success:** Daily active use by target persona (Alex) within 2 weeks of deployment
    
- **Engagement:** Average 4+ hours daily usage with 10+ agent interactions
    
- **Retention:** 90%+ daily usage consistency over 30-day period
    
- **Expansion:** Addition of new providers and tools based on usage patterns
    

#### **Business Impact**

- **Productivity ROI:** 25-40% improvement in development velocity for complex projects
    
- **Quality ROI:** 30-50% reduction in bugs through AI-assisted development and review
    
- **Learning ROI:** 50-75% faster technology adoption through specialized research agents
    
- **Cost ROI:** Break-even within 4-6 weeks through productivity gains vs. development investment
    

### **Risk-Adjusted Value**

#### **Value Certainty**

- **High Certainty:** Core functionality (multi-provider chat) provides immediate value
    
- **Medium Certainty:** Advanced features (MCP integration, sub-agents) provide differentiated value
    
- **Lower Certainty:** TUI adoption may vary based on user preferences
    

#### **Investment Protection**

- **Modular Architecture:** Core value delivered even if advanced features are delayed
    
- **Open Standards:** MCP and standard APIs reduce vendor lock-in risks
    
- **Self-Hosted:** No ongoing service dependencies or subscription risks
    
- **Educational Value:** Development process provides deep LLM integration expertise


## 12. Testing Strategy

**Goal:** Define comprehensive testing approaches to ensure system reliability, security, and performance.

### **Testing Pyramid & Approach**

#### **Unit Testing (Foundation - 70%)**

- **Coverage Target:** 90%+ for critical business logic
    
- **Focus Areas:**
    
    - Authentication modules (API key validation, OAuth flows)
        
    - HTTP client functionality (header construction, response parsing)
        
    - Database operations (CRUD, migrations, data integrity)
        
    - Tool execution logic (file operations, code execution safety)
        
    - Token counting and cost calculation accuracy
        
- **Testing Framework:** ExUnit with property-based testing using StreamData
    
- **Mocking Strategy:** Mock external API calls, use in-memory databases for isolated tests
    

#### **Integration Testing (Middle - 25%)**

- **API Integration Tests:**
    
    - Real provider API calls with test credentials (rate-limited)
        
    - Database integration with PostgreSQL test instances
        
    - Redis session state management
        
    - Oban background job processing
        
- **Component Integration:**
    
    - LiveView UI components with backend services
        
    - WebSocket connections for real-time updates
        
    - MCP server communication protocols
        
    - Tool execution with file system interactions
        

#### **End-to-End Testing (Top - 5%)**

- **User Journey Tests:**
    
    - Complete authentication flows for all three providers
        
    - Multi-session management and context switching
        
    - Agent tool usage workflows (file operations, code execution)
        
    - TUI-to-backend communication and session synchronization
        

### **Test Categories & Scenarios**

#### **Functional Testing**

**Authentication Testing:**
- Valid/invalid API key handling for each provider
    
- OAuth flow completion and token refresh cycles
    
- Credential encryption/decryption accuracy
    
- Authentication failure graceful handling
    

**Session Management Testing:**
- Multiple concurrent session creation and management
    
- Session state persistence across restarts
    
- Real-time session updates via WebSockets
    
- Session cleanup and resource management
    

**Tool Execution Testing:**
- File system operations (read, write, directory creation)
    
- Code execution in multiple languages (Python, JavaScript, Bash)
    
- MCP server integration and tool discovery
    
- Sub-agent invocation and response handling
    

#### **Non-Functional Testing**

**Performance Testing:**
- Load testing with 20+ concurrent sessions
    
- API response time measurement under load
    
- Memory usage monitoring during extended sessions
    
- Database query performance with large conversation histories
    

**Security Testing:**
- Credential storage encryption validation
    
- Input sanitization and injection attack prevention
    
- File system access boundary enforcement
    
- Code execution sandboxing effectiveness
    

**Reliability Testing:**
- Provider API failure handling and graceful degradation
    
- Database connection failure recovery
    
- Redis session state recovery after outages
    
- Long-running session stability (24+ hour sessions)
    

### **Provider-Specific Testing**

#### **Multi-Provider Compatibility**

- **Header Fidelity Testing:** Automated comparison of generated headers vs. reference implementations
    
- **Response Format Validation:** Ensure consistent handling of different provider response formats
    
- **Token Counting Accuracy:** Validate token usage parsing across all providers
    
- **Streaming Consistency:** Test real-time message streaming for each provider
    

#### **Provider API Mocking**

- **Development Mocks:** High-fidelity mocks for development and unit testing
    
- **Error Simulation:** Mock various API error conditions (rate limits, service outages)
    
- **Response Variation:** Test handling of different response formats and edge cases
    
- **Performance Simulation:** Mock varying API response times and network conditions
    

### **UI Testing Strategy**

#### **Web UI Testing**

- **LiveView Testing:** Phoenix LiveView test helpers for real-time interactions
    
- **Browser Testing:** Automated browser testing with Wallaby for cross-browser compatibility
    
- **Accessibility Testing:** Automated WCAG 2.1 AA compliance verification
    
- **Visual Regression Testing:** Screenshot-based testing for UI consistency
    

#### **TUI Testing**

- **Integration Testing:** Test TUI-to-API communication layers
    
- **Input/Output Testing:** Automated keyboard input and screen output validation
    
- **Cross-Platform Testing:** Automated testing on macOS, Linux, and Windows environments
    
- **Terminal Compatibility:** Testing across different terminal emulators
    

### **Data & State Testing**

#### **Database Testing**

- **Migration Testing:** Automated testing of all database migrations (up and down)
    
- **Data Integrity:** Validation of conversation history accuracy and completeness
    
- **Concurrent Access:** Testing database operations under concurrent session load
    
- **Backup/Recovery:** Automated backup creation and restoration validation
    

#### **State Management Testing**

- **Session State Synchronization:** Multi-client session state consistency
    
- **Redis Persistence:** Session state recovery after Redis restarts
    
- **Real-time Updates:** WebSocket message delivery accuracy and ordering
    
- **State Migration:** Testing state format changes and backward compatibility
    

### **Security Testing Framework**

#### **Authentication Security**

- **OAuth Security:** PKCE implementation validation and token lifecycle management
    
- **Credential Protection:** Encryption key management and secure storage validation
    
- **Session Security:** Session hijacking prevention and timeout enforcement
    
- **API Security:** Request signing and header manipulation prevention
    

#### **Tool Security**

- **File System Boundaries:** Testing access control within user permissions
    
- **Code Execution Safety:** Sandboxing effectiveness and privilege escalation prevention
    
- **Input Validation:** Testing injection attack prevention across all input vectors
    
- **Network Security:** Validating secure HTTPS communications with providers
    

### **Testing Infrastructure**

#### **Continuous Integration**

- **GitHub Actions:** Automated test execution on all commits and pull requests
    
- **Test Environment Management:** Isolated test databases and Redis instances
    
- **Provider API Testing:** Rate-limited real API tests with test credentials
    
- **Performance Benchmarking:** Automated performance regression detection
    

#### **Test Data Management**

- **Synthetic Data:** Generated conversation histories and session states for testing
    
- **Privacy Protection:** No real user data in test environments
    
- **Data Seeding:** Consistent test data setup across environments
    
- **Test Cleanup:** Automated cleanup of test artifacts and temporary data
    

### **Quality Gates & Acceptance Criteria**

#### **Pre-Release Requirements**

- **Test Coverage:** 90%+ unit test coverage for critical paths
    
- **Integration Success:** 100% pass rate for provider integration tests
    
- **Performance Validation:** All performance requirements met under test load
    
- **Security Clearance:** Complete security testing with zero high-severity findings
    

#### **Deployment Validation**

- **Smoke Tests:** Basic functionality validation post-deployment
    
- **Health Checks:** Automated monitoring of all system components
    
- **Performance Monitoring:** Real-time performance metric collection
    
- **Error Rate Monitoring:** Automated alerting for error rate thresholds
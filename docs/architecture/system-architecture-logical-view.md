# 2. System Architecture & Logical View

The system is composed of a primary Phoenix web application and a separate TUI client application.

## 2.1. System Architecture Diagram

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

## 2.2. Component Breakdown

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
        

# Story 6.1: MCP Protocol Foundation & Transport Layer

## User Story
**As a** Developer,  
**I want** to implement the foundational MCP protocol client and transport layer abstractions,  
**so that** the system can communicate with MCP servers using standard protocol patterns.

## Acceptance Criteria

### MCP Protocol Implementation
1. **Protocol Compliance**: Implement MCP protocol specification:
   - JSON-RPC 2.0 message format
   - Standard MCP method calls (`initialize`, `list_tools`, `call_tool`, etc.)
   - Error handling following MCP error codes and formats
   - Version negotiation and capability exchange

2. **Core Protocol Messages**: Support essential MCP operations:
   ```elixir
   # Initialize handshake
   %{
     jsonrpc: "2.0",
     id: request_id,
     method: "initialize", 
     params: %{
       protocolVersion: "2024-11-05",
       capabilities: %{
         tools: %{listChanged: true},
         resources: %{subscribe: true, listChanged: true}
       },
       clientInfo: %{name: "the_maestro", version: "1.0.0"}
     }
   }
   ```

3. **Message Routing**: Implement request/response correlation and handling:
   - Request ID tracking and correlation
   - Async response handling
   - Error propagation
   - Timeout management

### Transport Layer Abstraction
4. **Transport Behaviour**: Define transport abstraction:
   ```elixir
   defmodule TheMaestro.MCP.Transport do
     @callback start_link(config :: map()) :: {:ok, pid()} | {:error, term()}
     @callback send_message(transport :: pid(), message :: map()) :: :ok | {:error, term()}
     @callback close(transport :: pid()) :: :ok
   end
   ```

5. **Stdio Transport**: Implement subprocess communication:
   - Process spawning and management
   - Stdin/stdout JSON streaming
   - Process cleanup and error handling
   - Working directory and environment management

6. **SSE Transport**: Implement Server-Sent Events transport:
   - HTTP client with SSE support
   - Event stream parsing
   - Connection management and reconnection
   - Authentication header support

7. **HTTP Transport**: Implement HTTP streaming transport:
   - HTTP POST with streaming responses
   - Request/response correlation
   - Connection pooling
   - Custom headers and authentication

### Connection Management
8. **Connection Lifecycle**: Manage MCP server connections:
   ```elixir
   defmodule TheMaestro.MCP.Connection do
     # States: :disconnected, :connecting, :connected, :error
     defstruct [:transport, :state, :server_info, :capabilities, :tools]
   end
   ```

9. **Heartbeat & Health Checking**: Monitor connection health:
   - Periodic ping/heartbeat messages
   - Connection timeout detection
   - Automatic reconnection logic
   - Graceful degradation on failure

10. **Error Recovery**: Robust error handling:
    - Transport-specific error handling
    - Connection retry mechanisms
    - Partial failure handling
    - Error reporting to agent system

### Protocol Message Handling  
11. **Request/Response Handling**: 
    - Asynchronous request processing
    - Response correlation by ID
    - Request timeout handling
    - Error response processing

12. **Notification Handling**: Support MCP notifications:
    - Tool list changes (`notifications/tools/list_changed`)
    - Resource updates
    - Capability changes
    - Progress notifications

13. **Bidirectional Communication**: Support server-initiated messages:
    - Notification reception
    - Progress updates
    - Resource change notifications
    - Capability announcements

## Technical Implementation

### Module Structure
```elixir
lib/the_maestro/mcp/
├── protocol.ex              # Core MCP protocol implementation
├── transport/
│   ├── transport.ex         # Transport behaviour
│   ├── stdio.ex            # Stdio transport implementation
│   ├── sse.ex              # Server-Sent Events transport
│   └── http.ex             # HTTP streaming transport
├── connection.ex           # Connection management
├── message_router.ex       # Request/response correlation
└── error_handler.ex        # MCP-specific error handling
```

### JSON-RPC Message Processing
14. **Message Serialization**: JSON encoding/decoding with:
    - Proper JSON-RPC 2.0 format validation
    - Error message formatting
    - Parameter validation
    - Response correlation

15. **Protocol Validation**: Validate MCP protocol compliance:
    - Method name validation  
    - Parameter schema validation
    - Response format validation
    - Error code compliance

### Integration Points
16. **Tooling System Integration**: Connect to existing tool system:
    - Tool discovery from MCP servers
    - Tool registration in agent tooling registry
    - Tool execution delegation to MCP servers

17. **Agent System Integration**: Integration with agent framework:
    - MCP client lifecycle management
    - Connection status reporting
    - Tool availability updates

## Configuration Schema
18. **Transport Configuration**: Support configuration formats:
    ```elixir
    config :the_maestro, :mcp,
      servers: %{
        "example_server" => %{
          transport: :stdio,
          command: "python",
          args: ["-m", "example_mcp_server"],
          env: %{"API_KEY" => {:system, "EXAMPLE_API_KEY"}},
          cwd: "./mcp-servers",
          timeout: 30_000
        }
      }
    ```

## Error Handling & Logging
19. **MCP Error Codes**: Implement standard MCP error handling:
    - `ParseError` (-32700)
    - `InvalidRequest` (-32600)  
    - `MethodNotFound` (-32601)
    - `InvalidParams` (-32602)
    - `InternalError` (-32603)
    - Custom error codes as defined by MCP spec

20. **Comprehensive Logging**: Detailed logging for debugging:
    - Protocol message tracing
    - Connection state changes
    - Transport-specific events
    - Error conditions and recovery

## Testing Strategy
21. **Protocol Testing**: Comprehensive protocol testing:
    - Message format validation
    - Error condition testing
    - Timeout handling
    - Connection lifecycle testing

22. **Transport Testing**: Transport-specific testing:
    - Mock MCP servers for each transport type
    - Network failure simulation
    - Performance testing under load
    - Security testing for HTTP transports

## Dependencies
- JSON library (Jason) for message serialization
- HTTP client library for SSE/HTTP transports
- Process management utilities for Stdio transport
- Existing tooling system from Epic 1

## Definition of Done
- [ ] MCP protocol client implementation completed
- [ ] All three transport types (Stdio, SSE, HTTP) functional
- [ ] Connection management and lifecycle implemented
- [ ] Message routing and correlation operational
- [ ] Error handling following MCP specification
- [ ] Protocol validation and compliance verified
- [ ] Integration with existing tooling system
- [ ] Comprehensive test coverage for all transports
- [ ] Performance benchmarks established
- [ ] Documentation and examples created
- [ ] Tutorial created in `tutorials/epic6/story6.1/`
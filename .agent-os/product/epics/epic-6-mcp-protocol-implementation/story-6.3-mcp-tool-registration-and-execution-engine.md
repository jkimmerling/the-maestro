# Story 6.3: MCP Tool Registration & Execution Engine

## User Story
**As an** Agent,  
**I want** to seamlessly discover, register, and execute tools from MCP servers,  
**so that** I can extend my capabilities with external tools while maintaining the same interface as built-in tools.

## Acceptance Criteria

### Tool Discovery & Registration
1. **Tool Enumeration**: Discover tools from connected MCP servers:
   - Call `tools/list` method on each connected server
   - Parse tool definitions and schemas
   - Validate tool parameter schemas for compatibility
   - Handle tool list changes via notifications

2. **Schema Processing**: Process and sanitize tool schemas:
   ```elixir
   # Raw MCP tool definition
   %{
     "name" => "read_file",
     "description" => "Read contents of a file",
     "inputSchema" => %{
       "type" => "object",
       "properties" => %{
         "path" => %{"type" => "string", "description" => "File path to read"}
       },
       "required" => ["path"]
     }
   }
   
   # Processed for agent system
   %TheMaestro.Tooling.Tool{
     name: "read_file",
     description: "Read contents of a file",
     parameters: [
       %{name: "path", type: :string, required: true, description: "File path to read"}
     ],
     executor: &TheMaestro.MCP.ToolExecutor.execute/3
   }
   ```

3. **Tool Validation**: Validate MCP tools for agent compatibility:
   - Parameter type validation
   - Required field validation
   - Description completeness
   - Name uniqueness and sanitization

4. **Dynamic Registration**: Register tools with existing agent tooling system:
   - Integration with existing `deftool` DSL
   - Tool availability updates
   - Tool metadata preservation
   - Source server attribution

### Tool Execution Engine
5. **Execution Coordinator**: Coordinate tool execution between agent and MCP server:
   ```elixir
   defmodule TheMaestro.MCP.ToolExecutor do
     def execute(tool_name, parameters, context) do
       with {:ok, server_id} <- find_tool_server(tool_name),
            {:ok, connection} <- get_server_connection(server_id),
            {:ok, result} <- call_mcp_tool(connection, tool_name, parameters) do
         process_tool_result(result, context)
       else
         {:error, reason} -> handle_execution_error(reason, tool_name, parameters)
       end
     end
   end
   ```

6. **Parameter Marshalling**: Convert agent parameters to MCP format:
   - Type conversion and validation
   - Required parameter checking
   - Default value application
   - Parameter sanitization

7. **MCP Tool Invocation**: Execute tools on MCP servers:
   - Send `tools/call` requests to appropriate servers
   - Handle async execution patterns
   - Manage request timeouts
   - Process execution results

8. **Result Processing**: Handle MCP tool results:
   - Parse `CallToolResult` responses
   - Extract content blocks (text, images, resources)
   - Format results for agent consumption
   - Handle rich media content

### Tool Namespace Management
9. **Name Conflict Resolution**: Handle tool name conflicts across servers:
   - Automatic prefixing for conflicts (`server_name__tool_name`)
   - First-registered priority system
   - Clear tool attribution in agent context
   - Conflict resolution logging

10. **Tool Routing**: Route tool calls to correct MCP servers:
    - Maintain tool-to-server mapping
    - Handle prefixed and unprefixed tool names
    - Server availability checking
    - Fallback server selection

11. **Tool Metadata Management**: Preserve tool source information:
    ```elixir
    %TheMaestro.MCP.ToolMetadata{
      tool_name: "read_file",
      server_id: "filesystem_server",
      original_name: "read_file",
      prefixed_name: nil,
      capabilities: [:text_output],
      trust_level: :untrusted,
      last_used: ~U[2024-01-01 00:00:00Z]
    }
    ```

### Rich Content Handling
12. **Multi-Part Responses**: Handle complex MCP tool responses:
    - Text content extraction
    - Image/media content processing
    - Resource link resolution
    - Binary data handling

13. **Content Type Processing**: Support all MCP content types:
    ```elixir
    # Text content
    %{"type" => "text", "text" => "File contents..."}
    
    # Image content
    %{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}
    
    # Resource content
    %{"type" => "resource", "resource" => %{"uri" => "file:///path", "text" => "content"}}
    
    # Audio content
    %{"type" => "audio", "data" => base64_data, "mimeType" => "audio/wav"}
    ```

14. **Agent Context Integration**: Integrate rich content into agent context:
    - Text content for LLM processing
    - Media content for multimodal models
    - Resource references for follow-up actions
    - Content metadata preservation

### Error Handling & Recovery
15. **Execution Error Handling**: Comprehensive error handling:
    - Tool not found errors
    - Server unavailable errors
    - Parameter validation errors
    - Execution timeout errors
    - MCP protocol errors

16. **Graceful Degradation**: Handle partial failures:
    - Tool unavailability notifications
    - Alternative tool suggestions
    - Fallback to built-in tools
    - Error context preservation

17. **Retry Logic**: Intelligent retry mechanisms:
    - Transient error retry
    - Exponential backoff
    - Circuit breaker integration
    - Retry limit enforcement

### Performance Optimization
18. **Tool Caching**: Cache tool definitions and metadata:
    - Tool schema caching
    - Result caching for idempotent operations
    - Connection pooling for tool execution
    - Performance metrics collection

19. **Async Execution**: Support asynchronous tool execution:
    - Non-blocking tool calls
    - Progress notifications
    - Cancellation support
    - Concurrent execution limits

20. **Resource Management**: Efficient resource utilization:
    - Connection reuse
    - Memory-efficient content handling
    - Cleanup of temporary resources
    - Resource leak prevention

## Technical Implementation

### Core Modules
```elixir
lib/the_maestro/mcp/tools/
├── registry.ex              # Tool registration and management
├── executor.ex              # Tool execution coordinator
├── result_processor.ex      # MCP result processing
├── content_handler.ex       # Rich content handling
├── namespace_manager.ex     # Tool naming and conflicts
└── metadata_store.ex        # Tool metadata management
```

### Tool Registration System
21. **Registration Pipeline**: Systematic tool registration:
    ```elixir
    MCP Server → Tool Discovery → Schema Validation → 
    Conflict Resolution → Agent Registration → Availability Notification
    ```

22. **Tool State Management**: Track tool states:
    ```elixir
    %ToolState{
      name: "read_file",
      server_id: "filesystem_server",
      status: :available | :unavailable | :error,
      schema: tool_schema,
      metadata: tool_metadata,
      last_update: timestamp
    }
    ```

### Integration with Existing Systems
23. **Agent Tooling Integration**: Seamless integration with existing tool system:
    - Extend existing `Tool` behaviour
    - Integration with `deftool` macro system
    - Tool availability events
    - Usage statistics tracking

24. **LLM Provider Integration**: Provide tools to LLM providers:
    - Tool schema conversion for different providers
    - Function calling integration
    - Tool result formatting
    - Provider-specific optimizations

### Security & Trust Management
25. **Trust-based Execution**: Implement trust-based tool execution:
    - Server trust levels
    - Tool-specific trust settings
    - User confirmation flows
    - Audit logging

26. **Parameter Sanitization**: Secure parameter handling:
    - Input validation
    - Path traversal prevention
    - Injection attack prevention
    - Sensitive data filtering

27. **Sandboxing Integration**: Respect existing sandboxing:
    - Sandbox-aware tool execution
    - Resource access controls
    - Network restrictions
    - File system limitations

### Monitoring & Observability
28. **Execution Metrics**: Comprehensive metrics collection:
    - Tool execution latency
    - Success/failure rates
    - Resource utilization
    - Error patterns

29. **Audit Logging**: Detailed audit trails:
    - Tool execution logs
    - Parameter logging (sanitized)
    - Result summaries
    - Security events

30. **Performance Monitoring**: Performance tracking:
    - Execution time monitoring
    - Memory usage tracking
    - Network latency measurements
    - Bottleneck identification

## Rich Content Processing Details
31. **Image Processing**: Handle image content from MCP tools:
    - Base64 decoding
    - Format validation
    - Size limitations
    - Multimodal model integration

32. **Resource Handling**: Process resource references:
    - URI resolution
    - Access permission checking
    - Content fetching
    - Caching strategies

33. **Binary Data Management**: Efficient binary data handling:
    - Streaming for large content
    - Temporary file management
    - Memory usage optimization
    - Cleanup procedures

## Testing Strategy
34. **Tool Execution Testing**: Comprehensive testing:
    - Mock MCP servers with various tool types
    - Error condition simulation
    - Performance testing
    - Security testing

35. **Content Handling Testing**: Rich content testing:
    - Multi-part response testing
    - Binary content handling
    - Resource resolution testing
    - Error recovery testing

36. **Integration Testing**: End-to-end testing:
    - Agent-to-MCP tool execution
    - Multiple server scenarios
    - Failure recovery testing
    - Performance benchmarking

## Dependencies
- Story 6.1 (MCP Protocol Foundation)
- Story 6.2 (MCP Server Discovery)
- Existing agent tooling system from Epic 1
- Agent execution framework

## Definition of Done
- [ ] MCP tool discovery and registration implemented
- [ ] Tool execution engine operational with all content types
- [ ] Tool namespace management and conflict resolution
- [ ] Rich content handling (text, images, resources, binary data)
- [ ] Integration with existing agent tooling system
- [ ] Security and trust management implemented
- [ ] Error handling and recovery mechanisms
- [ ] Performance optimization and caching
- [ ] Monitoring and observability features
- [ ] Comprehensive test coverage including rich content scenarios
- [ ] Documentation with examples of tool execution patterns
- [ ] Tutorial created in `tutorials/epic6/story6.3/`
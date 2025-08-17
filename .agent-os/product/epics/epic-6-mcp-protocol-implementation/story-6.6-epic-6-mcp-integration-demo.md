# Story 6.6: Epic 6 MCP Integration Demo

## User Story
**As a** Developer and User,  
**I want** a comprehensive demonstration of MCP integration capabilities,  
**so that** I can understand, test, and showcase the complete MCP implementation.

## Acceptance Criteria

### Demo Application Structure
1. **Demo Directory Structure**: Create comprehensive demo structure:
   ```
   demos/epic6/
   ├── README.md                    # Main demo guide
   ├── mcp_settings.json           # Sample MCP configuration
   ├── demo_servers/               # Sample MCP servers
   │   ├── filesystem_server.py    # File system MCP server
   │   ├── calculator_server.js    # Mathematical operations server
   │   ├── weather_api_server/     # Weather API integration
   │   └── database_tools_server/  # Database interaction tools
   ├── demo_script.exs            # Automated demo execution
   ├── interactive_demo.exs       # Interactive demo with user input
   └── testing/
       ├── test_configurations.json # Test configurations
       ├── security_tests.exs      # Security demonstration
       └── performance_tests.exs   # Performance benchmarking
   ```

2. **Sample MCP Servers**: Provide diverse example servers:
   - **File System Server**: Demonstrate file operations with security
   - **Calculator Server**: Show mathematical operations and parameter validation
   - **Weather API Server**: External API integration with HTTP transport
   - **Database Tools**: Database operations with trust management

### Comprehensive Demo Scenarios
3. **Real MCP Integration Demo**: Demonstrate actual production MCP capabilities:
   ```elixir
   # demos/epic6/demo_script.exs
   IO.puts("🤖 The Maestro - Epic 6 Real MCP Integration Demo")
   IO.puts("=" |> String.duplicate(50))
   
   # Start the application with real MCP servers
   {:ok, _} = Application.ensure_all_started(:the_maestro)
   
   # Wait for real MCP server connections (Context7, Tavily)
   Process.sleep(3000)
   
   # Create demo agent with real MCP capabilities
   agent_id = "real_mcp_demo_#{System.system_time(:second)}"
   {:ok, _pid} = TheMaestro.Agents.start_agent(agent_id)
   
   # Demonstrate Context7 documentation retrieval
   IO.puts("\n📚 Context7 Documentation Demo")
   message = "Look up the latest FastAPI documentation for async route handlers"
   TheMaestro.Agents.send_message(agent_id, message)
   
   # Demonstrate Tavily web search
   IO.puts("\n🔍 Tavily Web Search Demo") 
   message = "Search for the latest MCP protocol specifications and updates"
   TheMaestro.Agents.send_message(agent_id, message)
   ```

4. **Real Server Discovery & Connection Demo**: Show actual MCP server discovery:
   - **Context7 stdio discovery**: NPX-based server startup and tool registration
   - **Tavily HTTP discovery**: Remote API endpoint validation and authentication
   - **Context7 SSE discovery**: WebSocket-style connection establishment
   - **Tool discovery**: Real tools like `resolve-library-id`, `search`, `extract`
   - **Connection monitoring**: Live status of production MCP endpoints
   - **Error handling**: API rate limits, authentication failures, network issues

5. **Tool Execution Demo**: Demonstrate tool execution flows:
   - Simple tool execution (calculator operations)
   - File system operations with security confirmation
   - Rich content handling (images, binary data)
   - Error handling and recovery
   - Performance monitoring

### Security & Trust Demonstration
6. **Real Security Flow Demo**: Demonstrate production security features:
   ```elixir
   # Demonstrate untrusted Tavily server tool execution
   IO.puts("\n🔒 Security Demo: Untrusted Tavily Tool Execution")
   
   # This should trigger confirmation flow for web search
   message = "Search for sensitive corporate information about our competitors and extract their private data"
   TheMaestro.Agents.send_message(agent_id, message)
   
   # Demonstrate different trust levels with real servers
   IO.puts("\n🛡️ Trust Level Demonstration")
   IO.puts("Context7 (trusted): Documentation lookup - no confirmation needed")
   IO.puts("Tavily (untrusted): Web search - requires user confirmation")
   
   # Test API key security
   IO.puts("\n🔐 API Key Security Demo")
   # Demonstrate encrypted API key storage and rotation
   ```

7. **Trust Management Demo**: Show trust management capabilities:
   - Server trust configuration
   - Tool-specific trust settings
   - User confirmation flows
   - Trust revocation and modification
   - Audit trail demonstration

8. **Parameter Sanitization Demo**: Demonstrate security validation:
   - Path traversal prevention
   - Command injection prevention
   - Sensitive data detection
   - Input validation and sanitization

### Multi-Server Coordination
9. **Real Multi-Server Demo**: Demonstrate coordination between actual production servers:
   - **Tool coordination**: Context7 `resolve-library-id` → Tavily `search` for additional context
   - **Server priority**: Context7 stdio vs SSE transport performance comparison
   - **Cross-server workflows**: Documentation lookup followed by web research validation
   - **Performance comparison**: Stdio vs HTTP vs SSE transport latency measurements
   - **Load distribution**: Balancing between Context7 and Tavily based on query type

10. **Transport Type Demo**: Show all transport mechanisms:
    - Stdio transport with local Python server
    - HTTP transport with REST API server
    - SSE transport with streaming server
    - Authentication flow for each transport type

### Rich Content Handling
11. **Real Rich Content Demo**: Demonstrate actual multi-modal content from production servers:
    ```elixir
    # Demonstrate Context7 documentation with code examples
    message = "Get React hooks documentation with TypeScript examples and display syntax highlighted code"
    
    # Demonstrate Tavily search with rich results
    message2 = "Search for MCP protocol diagrams and return images, videos, and structured data"
    
    # Demonstrate real content extraction
    message3 = "Extract and process documentation from the official MCP GitHub repository"
    
    # Show Context7 library documentation with embedded examples
    message4 = "Look up FastAPI async documentation with working code samples"
    ```

12. **Content Type Processing**: Show handling of various content types:
    - Text content integration with LLM context
    - Image display in UI and TUI
    - Audio playback capabilities
    - Binary data storage and retrieval
    - Resource link resolution

### CLI Tools Demonstration
13. **Real CLI Management Demo**: Demonstrate MCP CLI tools with production servers:
    ```bash
    # Real server management demonstration
    ./maestro mcp list
    # Shows: context7_stdio (running), context7_sse (connected), tavily_http (connected)
    ./maestro mcp status
    # Shows real connection status, latency, API quotas
    ./maestro mcp test --all
    # Tests actual API endpoints and authentication
    
    # Real tool management demonstration  
    ./maestro mcp tools
    # Lists: resolve-library-id, get-library-docs, search, extract, crawl
    ./maestro mcp tools --describe context7.resolve-library-id
    ./maestro mcp run tavily.search --query "MCP protocol examples" --max_results 5
    
    # Real configuration management
    ./maestro mcp export --include-api-keys=false
    ./maestro mcp import real_mcp_configs.json --validate-api-keys
    ```

14. **Monitoring & Diagnostics Demo**: Show monitoring capabilities:
    - Real-time server status monitoring
    - Performance metrics collection
    - Error rate analysis
    - Resource usage tracking
    - Audit trail review

### Performance & Scalability Demo
15. **Performance Benchmarking**: Demonstrate performance characteristics:
    - Tool execution latency measurement
    - Concurrent execution limits
    - Memory usage monitoring
    - Network throughput testing
    - Error recovery performance

16. **Scalability Demo**: Show system scalability:
    - Multiple simultaneous agents using MCP tools
    - High-frequency tool execution
    - Large response handling
    - Resource limit enforcement
    - Connection pool management

### Integration Scenarios
17. **UI Integration Demo**: Demonstrate MCP integration in web interface:
    - Tool selection and execution in UI
    - Rich content display (images, media)
    - Security confirmation dialogs
    - Real-time status updates
    - Error handling in UI context

18. **TUI Integration Demo**: Show terminal interface integration:
    - Tool execution in TUI environment
    - Text-based rich content handling
    - Terminal-friendly confirmation flows
    - Status indicators and progress
    - Error display and recovery

### Error Handling & Recovery
19. **Failure Scenario Demo**: Demonstrate robust error handling:
    - Server connection failures
    - Tool execution timeouts
    - Network connectivity issues
    - Invalid parameter handling
    - Security violation responses

20. **Recovery Demo**: Show system recovery capabilities:
    - Automatic reconnection
    - Fallback server selection
    - Graceful degradation
    - Error state recovery
    - System stability under failure

## Technical Implementation

### Demo Infrastructure
21. **Real Demo Orchestration**: Automated demo execution with production MCPs:
    ```elixir
    defmodule TheMaestro.Demos.Epic6.RealMCP do
      def run_full_demo() do
        with :ok <- setup_real_mcp_environment(),
             :ok <- start_context7_stdio_server(),
             :ok <- connect_to_tavily_http(),
             :ok <- establish_context7_sse_connection(),
             :ok <- wait_for_all_connections(),
             :ok <- validate_api_authentication(),
             :ok <- run_real_demo_scenarios(),
             :ok <- demonstrate_real_security_features(),
             :ok <- show_production_cli_capabilities(),
             :ok <- cleanup_demo() do
          IO.puts("✅ Epic 6 Real MCP Integration Demo completed successfully!")
          IO.puts("📊 Servers tested: Context7 (stdio/sse), Tavily (http)")
          IO.puts("🔧 Transports validated: stdio, http, sse")
        else
          {:error, reason} -> 
            IO.puts("❌ Real MCP Demo failed: #{inspect(reason)}")
            cleanup_demo()
        end
      end
      
      defp setup_real_mcp_environment() do
        # Load API keys from environment
        case {System.get_env("CONTEXT7_API_KEY"), System.get_env("TAVILY_API_KEY")} do
          {nil, _} -> {:error, "Missing CONTEXT7_API_KEY"}
          {_, nil} -> {:error, "Missing TAVILY_API_KEY"}
          {_, _} -> :ok
        end
      end
      
      defp start_context7_stdio_server() do
        # Start Context7 via NPX
        case System.cmd("npx", ["-y", "@upstash/context7-mcp@latest"]) do
          {_, 0} -> :ok
          _ -> {:error, "Failed to start Context7 stdio server"}
        end
      end
    end
    ```

22. **Production MCP Server Integrations**: Real working MCP server connections:
    - **Context7 NPX Integration**: Official @upstash/context7-mcp package
    - **Tavily HTTP API**: Production-ready web search and research API
    - **Multi-transport Support**: stdio, HTTP, and SSE implementations
    - **API Security**: Real authentication and rate limiting
    - **Performance Monitoring**: Actual latency and throughput measurements

### Demo Configuration
23. **Real MCP Configurations**: Production-ready configuration examples:
    ```json
    {
      "mcpServers": {
        "context7_stdio": {
          "command": "npx",
          "args": ["-y", "@upstash/context7-mcp@latest"],
          "transportType": "stdio",
          "trust": true,
          "description": "Context7 documentation server via stdio",
          "env": {
            "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"
          }
        },
        "context7_sse": {
          "httpUrl": "https://mcp.context7.dev/sse",
          "transportType": "sse", 
          "trust": true,
          "timeout": 30000,
          "description": "Context7 documentation server via SSE",
          "headers": {
            "Authorization": "Bearer ${CONTEXT7_API_KEY}"
          }
        },
        "tavily_http": {
          "httpUrl": "https://mcp.tavily.com/mcp",
          "transportType": "http",
          "trust": false,
          "timeout": 15000,
          "description": "Tavily web search and research server",
          "env": {
            "TAVILY_API_KEY": "${TAVILY_API_KEY}"
          }
        }
      },
      "globalSettings": {
        "defaultTimeout": 30000,
        "confirmationLevel": "medium",
        "auditLogging": true,
        "apiKeyManagement": {
          "requireEncryption": true,
          "rotationEnabled": true
        }
      }
    }
    ```

### Interactive Demo Features
24. **User Interaction**: Interactive demo components:
    - User choice points in demo flow
    - Real-time status updates
    - Progress indicators
    - Error simulation options
    - Performance monitoring displays

25. **Educational Content**: Learning-focused demo elements:
    - Step-by-step explanations
    - Code examples with comments
    - Architecture diagrams
    - Best practices demonstrations
    - Troubleshooting examples

### Documentation & Tutorials
26. **Comprehensive README**: Detailed demo documentation:
    - Prerequisites and setup instructions
    - Step-by-step demo execution
    - Expected output examples
    - Troubleshooting guide
    - Advanced usage scenarios

27. **Video Walkthrough Support**: Enable video demonstration:
    - Clear visual outputs
    - Timed delays for narration
    - Highlighted important elements
    - Clean terminal output
    - Professional presentation format

## Validation & Testing
28. **Demo Validation**: Ensure demo reliability:
    - Automated demo testing
    - Cross-platform validation
    - Performance benchmarking
    - Security testing
    - User experience validation

29. **Regression Testing**: Demo stability assurance:
    - Version compatibility testing
    - Configuration validation
    - Server compatibility testing
    - Performance regression detection
    - Security regression testing

## Dependencies
- Complete Epic 6 implementation (Stories 6.1-6.5)
- **Context7 API Access**: 
  - Context7 API key from Upstash (https://upstash.com/context7)
  - NPM/Node.js environment for @upstash/context7-mcp package
- **Tavily API Access**:
  - Tavily API key from Tavily AI (https://tavily.com)
  - HTTP client capability for REST API calls
- **Development Environment**:
  - Node.js/NPM for Context7 stdio transport
  - Elixir HTTP client for Tavily and Context7 SSE
  - Environment variable management for API keys
- Documentation and tutorial systems

## Definition of Done
- [ ] **Real MCP Infrastructure**: Demo directory structure with production MCP integrations
- [ ] **Context7 Integration**: Both stdio and SSE transport implementations working
- [ ] **Tavily Integration**: HTTP transport implementation with real web search capabilities
- [ ] **Multi-Transport Demo**: All three transport types (stdio, HTTP, SSE) operational
- [ ] **API Authentication**: Secure API key management and authentication flows
- [ ] **Automated Real Demo**: Script covering all major features with actual MCP servers
- [ ] **Interactive Real Demo**: User participation with live MCP tool execution
- [ ] **Production Security**: Trust management with real server authentication
- [ ] **Multi-Server Coordination**: Context7 + Tavily working together seamlessly
- [ ] **Real Rich Content**: Actual documentation and search results display
- [ ] **Production CLI Tools**: CLI management of real MCP servers and tools
- [ ] **Performance Benchmarking**: Real latency and throughput measurements
- [ ] **UI/TUI Integration**: Real MCP content display in both interfaces
- [ ] **Error Handling**: Production error scenarios (rate limits, auth failures)
- [ ] **Comprehensive Documentation**: Setup guides for real API access
- [ ] **Production Validation**: Testing suite with actual MCP endpoints
- [ ] **API Setup Tutorial**: Guide for obtaining and configuring API keys
- [ ] **Video Walkthrough**: Demo of real MCP interactions and capabilities
- [ ] **Cross-Platform Compatibility**: Verified on multiple environments with real APIs
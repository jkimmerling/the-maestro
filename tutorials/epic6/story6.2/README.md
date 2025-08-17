# Tutorial: MCP Server Discovery & Connection Management

This tutorial demonstrates how to use the MCP (Model Context Protocol) Server Discovery and Connection Management system implemented in Epic 6 Story 6.2.

## Overview

The MCP system provides:
- **Server Discovery**: Automatic loading of MCP servers from configuration
- **Connection Management**: Persistent connection pool with health monitoring
- **Tool Management**: Tool discovery with namespace conflict resolution
- **Load Balancing**: Distribution of requests across multiple servers
- **Failover Handling**: Automatic reconnection and circuit breaker protection

## Architecture

```
TheMaestro.MCP.Supervisor
├── TheMaestro.MCP.Registry (Server & tool tracking)
├── TheMaestro.MCP.ConnectionManager (Connection pool)
└── TheMaestro.MCP.ConnectionSupervisor (Individual connections)
```

## Configuration

### MCP Settings File

Create `mcp_settings.json` in your project root:

```json
{
  "mcpServers": {
    "fileSystem": {
      "command": "python",
      "args": ["-m", "filesystem_mcp"],
      "env": {
        "ALLOWED_DIRS": "/tmp,/workspace"
      },
      "trust": false,
      "priority": 5
    },
    "weatherAPI": {
      "url": "https://weather.example.com/sse",
      "headers": {
        "Authorization": "Bearer $WEATHER_API_TOKEN"
      },
      "trust": true,
      "priority": 10
    },
    "localTool": {
      "command": "node",
      "args": ["./tools/local-tool.js"],
      "env": {
        "DEBUG": "true"
      },
      "trust": true,
      "priority": 8
    }
  }
}
```

### Environment Variables

The system supports environment variable interpolation:

```json
{
  "env": {
    "API_KEY": "$MY_API_TOKEN",           // Simple format
    "DATABASE_URL": "${DB_CONNECTION}"    // Braced format
  }
}
```

## Usage Examples

### 1. Basic Server Discovery

```elixir
# Discover servers from configuration
{:ok, servers} = TheMaestro.MCP.Discovery.discover_servers("mcp_settings.json")

# Start connections for discovered servers
Enum.each(servers, fn server_config ->
  TheMaestro.MCP.ConnectionManager.start_connection(
    TheMaestro.MCP.ConnectionManager, 
    server_config
  )
end)
```

### 2. Manual Server Management

```elixir
# Add a server at runtime
server_config = %{
  id: "dynamicServer",
  transport: :stdio,
  command: "python",
  args: ["-m", "my_server"],
  env: %{},
  trust: false
}

{:ok, connection_pid} = TheMaestro.MCP.ConnectionManager.add_server(
  TheMaestro.MCP.ConnectionManager,
  server_config
)

# Remove a server
:ok = TheMaestro.MCP.ConnectionManager.remove_server(
  TheMaestro.MCP.ConnectionManager,
  "dynamicServer"
)
```

### 3. Connection Management

```elixir
# Get a specific connection
{:ok, connection_info} = TheMaestro.MCP.ConnectionManager.get_connection(
  TheMaestro.MCP.ConnectionManager,
  "fileSystem"
)

# List all connections
connections = TheMaestro.MCP.ConnectionManager.list_connections(
  TheMaestro.MCP.ConnectionManager
)

# Check health status
{:ok, health} = TheMaestro.MCP.ConnectionManager.get_health_status(
  TheMaestro.MCP.ConnectionManager,
  "fileSystem"
)
```

### 4. Tool Management with Registry

```elixir
# Register tools for a server
tools = [
  %{name: "read_file", description: "Read file contents"},
  %{name: "write_file", description: "Write file contents"}
]

:ok = TheMaestro.MCP.ConnectionManager.register_tools(
  TheMaestro.MCP.ConnectionManager,
  "fileSystem",
  tools
)

# Get all tools (with namespace resolution)
all_tools = TheMaestro.MCP.ConnectionManager.get_all_tools(
  TheMaestro.MCP.ConnectionManager
)

# Registry-based tool resolution
{:ok, tool} = TheMaestro.MCP.Registry.resolve_tool(
  TheMaestro.MCP.Registry,
  "read_file"
)
```

### 5. Load Balancing and Failover

```elixir
# Get servers that provide a specific tool
servers = TheMaestro.MCP.Registry.get_servers_for_tool(
  TheMaestro.MCP.Registry,
  "weather_lookup"
)

# Get only available (connected) servers
available_servers = TheMaestro.MCP.Registry.get_available_servers_for_tool(
  TheMaestro.MCP.Registry,
  "weather_lookup"
)

# Use highest priority server
{:ok, tool} = TheMaestro.MCP.Registry.resolve_tool(
  TheMaestro.MCP.Registry,
  "weather_lookup"
)
```

### 6. Event Monitoring

```elixir
# Subscribe to registry events
:ok = TheMaestro.MCP.Registry.subscribe_to_events(TheMaestro.MCP.Registry)

# Listen for events
receive do
  {:mcp_registry_event, {:server_registered, server_id}} ->
    IO.puts("Server #{server_id} registered")
    
  {:mcp_registry_event, {:server_status_changed, server_id, status}} ->
    IO.puts("Server #{server_id} status changed to #{status}")
    
  {:mcp_registry_event, {:tools_updated, server_id, tools}} ->
    IO.puts("Tools updated for server #{server_id}: #{length(tools)} tools")
end
```

### 7. Configuration Reload

```elixir
# Hot reload configuration
:ok = TheMaestro.MCP.ConnectionManager.reload_configuration(
  TheMaestro.MCP.ConnectionManager,
  "mcp_settings.json"
)
```

## Tool Namespace Management

When multiple servers provide tools with the same name, the system automatically handles conflicts:

### Automatic Prefixing

```elixir
# Two servers with "search" tool
# server1: search
# server2: search

# Results in namespaced tools:
all_tools = TheMaestro.MCP.Registry.get_all_tools(TheMaestro.MCP.Registry)
# Returns: [
#   %{name: "server1__search", server_id: "server1", ...},
#   %{name: "server2__search", server_id: "server2", ...}
# ]
```

### Priority Resolution

```elixir
# Higher priority server takes precedence
{:ok, tool} = TheMaestro.MCP.Registry.resolve_tool(
  TheMaestro.MCP.Registry,
  "search"
)
# Returns the tool from the highest priority server
```

## Health Monitoring

The system provides comprehensive health monitoring:

### Health Status

```elixir
{:ok, health} = TheMaestro.MCP.ConnectionManager.get_health_status(
  TheMaestro.MCP.ConnectionManager,
  "server_id"
)

# Health status includes:
# - server_id
# - status (:connecting | :connected | :error)
# - last_heartbeat timestamp
# - error_count
# - last_error
```

### Metrics Collection

```elixir
# Record operations for metrics
:ok = TheMaestro.MCP.Registry.record_operation(
  TheMaestro.MCP.Registry,
  "server_id",
  :success,
  150  # latency in ms
)

# Get server metrics
metrics = TheMaestro.MCP.Registry.get_server_metrics(
  TheMaestro.MCP.Registry,
  "server_id"
)

# Metrics include:
# - uptime
# - total_operations
# - error_rate
# - avg_latency
```

## Circuit Breaker Pattern

The connection manager implements circuit breaker protection:

### Configuration

```json
{
  "mcpServers": {
    "unreliableServer": {
      "command": "python",
      "args": ["-m", "unreliable_server"],
      "max_failures": 3,
      "failure_window": 60000
    }
  }
}
```

### Behavior

1. **Closed**: Normal operation, requests pass through
2. **Open**: After max failures, circuit opens, requests fail fast
3. **Half-Open**: After timeout, single request allowed to test recovery

## Error Handling

### Graceful Degradation

```elixir
# System continues operating when some servers fail
case TheMaestro.MCP.ConnectionManager.get_connection(manager, "failed_server") do
  {:ok, connection} -> 
    # Use connection
    :ok
  {:error, :not_found} -> 
    # Server not available, use fallback
    use_fallback_server()
end
```

### Automatic Reconnection

The system automatically attempts to reconnect failed connections with exponential backoff.

## Best Practices

### 1. Server Configuration

- Use descriptive server IDs
- Set appropriate priorities based on reliability
- Configure reasonable timeout values
- Use environment variables for sensitive data

### 2. Tool Naming

- Use unique tool names when possible
- Provide clear descriptions
- Consider namespace conflicts in design

### 3. Health Monitoring

- Subscribe to events for proactive monitoring
- Implement alerting based on metrics
- Monitor error rates and latencies

### 4. Resource Management

- Set reasonable connection limits
- Monitor memory usage for long-running systems
- Implement proper cleanup in error scenarios

## Troubleshooting

### Common Issues

1. **Server Won't Connect**
   - Check command path and arguments
   - Verify environment variables
   - Check logs for detailed error messages

2. **Tool Conflicts**
   - Review tool naming across servers
   - Use priority settings to resolve conflicts
   - Monitor namespaced tool names

3. **Performance Issues**
   - Check server metrics for bottlenecks
   - Monitor connection pool usage
   - Review circuit breaker states

### Debugging Commands

```elixir
# Check supervisor status
Supervisor.which_children(TheMaestro.MCP.Supervisor)

# List all connections
TheMaestro.MCP.ConnectionManager.list_connections(TheMaestro.MCP.ConnectionManager)

# Check registry state
:sys.get_state(TheMaestro.MCP.Registry)
```

## Integration with Agent System

The MCP system integrates with The Maestro's agent tooling system:

```elixir
# Tools discovered by MCP are automatically available to agents
# through the existing tooling registry
```

This completes the basic tutorial for MCP Server Discovery & Connection Management. The system provides a robust foundation for managing external MCP servers with comprehensive monitoring, failover, and tool management capabilities.
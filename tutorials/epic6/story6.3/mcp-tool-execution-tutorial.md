# MCP Tool Registration & Execution Engine Tutorial

This tutorial demonstrates how to use the MCP (Model Context Protocol) tool registration and execution engine to extend agent capabilities with external tools.

## Overview

The MCP Tool Registration & Execution Engine allows agents to:
- Discover and register tools from MCP servers
- Execute tools with parameter marshalling and validation
- Handle rich content responses (text, images, resources, binary data)
- Manage tool namespace conflicts
- Monitor tool execution with comprehensive metrics

## Architecture

```
Agent Request → Tool Registry → Executor → MCP Server → Content Handler → Agent Response
```

### Core Components

1. **Registry** (`TheMaestro.MCP.Tools.Registry`) - Tool discovery and registration
2. **Executor** (`TheMaestro.MCP.Tools.Executor`) - Tool execution coordination
3. **ContentHandler** (`TheMaestro.MCP.Tools.ContentHandler`) - Rich content processing
4. **ToolAdapter** (`TheMaestro.MCP.ToolAdapter`) - Integration with agent tools

## Getting Started

### 1. Tool Discovery and Registration

First, start the MCP tool registry:

```elixir
# Start the registry
{:ok, _pid} = TheMaestro.MCP.Tools.Registry.start_link(name: Registry)

# Register tools from a connected MCP server
server_tools = [
  %{
    name: "read_file",
    description: "Read contents of a file",
    inputSchema: %{
      type: "object",
      properties: %{
        path: %{type: "string", description: "File path to read"}
      },
      required: ["path"]
    }
  }
]

TheMaestro.MCP.Tools.Registry.register_tools(Registry, "filesystem_server", server_tools)
```

### 2. Tool Execution

Execute an MCP tool using the executor:

```elixir
alias TheMaestro.MCP.Tools.Executor

# Set up execution context
context = %{
  server_id: "filesystem_server",
  connection_manager: TheMaestro.MCP.ConnectionManager,
  timeout: 30_000
}

# Execute the tool
{:ok, result} = Executor.execute("read_file", %{"path" => "/example.txt"}, context)

# Access the results
IO.puts("Text content: #{result.text_content}")
IO.puts("Has images: #{result.has_images}")
IO.puts("Execution time: #{result.execution_time_ms}ms")
```

### 3. Rich Content Handling

The system automatically processes different content types:

```elixir
alias TheMaestro.MCP.Tools.ContentHandler

# Example content from MCP tool response
content = [
  %{"type" => "text", "text" => "File analysis complete"},
  %{
    "type" => "image",
    "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
    "mimeType" => "image/png"
  },
  %{
    "type" => "resource",
    "resource" => %{
      "uri" => "file:///data/report.pdf",
      "text" => "Analysis report available"
    }
  }
]

# Process the content
result = ContentHandler.process_content(content)

IO.puts("Combined text: #{result.text_content}")
IO.puts("Has images: #{result.has_images}")
IO.puts("Has resources: #{result.has_resources}")
IO.puts("Total content blocks: #{length(result.processed_blocks)}")
```

### 4. Tool Namespace Management

The registry automatically handles tool name conflicts:

```elixir
# Register tools from multiple servers with potential conflicts
server1_tools = [%{name: "read_file", description: "Server 1 file reader"}]
server2_tools = [%{name: "read_file", description: "Server 2 file reader"}]

Registry.register_tools(Registry, "server1", server1_tools)
Registry.register_tools(Registry, "server2", server2_tools)

# Check resolved tool names
{:ok, tools} = Registry.get_all_tools(Registry)

# First server keeps original name, second gets prefixed
# "read_file" (server1) and "server2__read_file" (server2)
```

### 5. Agent Integration

Use the ToolAdapter to integrate MCP tools with the existing agent system:

```elixir
alias TheMaestro.MCP.ToolAdapter

# Register all MCP tools with the agent system
ToolAdapter.register_mcp_tools()

# Execute through the agent interface
{:ok, result} = ToolAdapter.execute_mcp_tool("read_file", %{"path" => "/test.txt"})

# The result is formatted for agent consumption
IO.inspect(result)
```

## Advanced Usage

### Error Handling

The system provides comprehensive error handling:

```elixir
case Executor.execute("missing_tool", %{}, context) do
  {:ok, result} ->
    IO.puts("Success: #{result.text_content}")
    
  {:error, %Executor.ExecutionError{type: :tool_not_found}} ->
    IO.puts("Tool not found")
    
  {:error, %Executor.ExecutionError{type: :parameter_validation_error, details: details}} ->
    IO.puts("Parameter error: #{inspect(details)}")
    
  {:error, %Executor.ExecutionError{type: :execution_timeout}} ->
    IO.puts("Tool execution timed out")
end
```

### Content Security

The content handler includes security validation:

```elixir
# This will be rejected due to path traversal attempt
dangerous_content = [
  %{
    "type" => "resource",
    "resource" => %{
      "uri" => "file:///../../../etc/passwd",
      "text" => "sensitive data"
    }
  }
]

case ContentHandler.validate_content_security(dangerous_content) do
  :ok -> 
    IO.puts("Content is safe")
  {:error, %{type: :path_traversal_attempt}} ->
    IO.puts("Security violation detected")
end
```

### Performance Monitoring

Tool execution emits telemetry events for monitoring:

```elixir
# Attach telemetry handler
:telemetry.attach("mcp-tool-metrics", [:the_maestro, :mcp, :tool_execution], fn event, measurements, metadata, _config ->
  IO.inspect({event, measurements, metadata})
end, nil)

# Execute tools - metrics will be emitted automatically
Executor.execute("read_file", %{"path" => "/test.txt"}, context)
```

### Content Optimization

Optimize content for different agent types:

```elixir
# For text-only agents
text_optimized = ContentHandler.optimize_content_for_agent(content, %{
  agent_type: :text_only,
  max_content_size: 100_000
})

# For multimodal agents
multimodal_optimized = ContentHandler.optimize_content_for_agent(content, %{
  agent_type: :multimodal,
  preserve_images: true,
  max_content_size: 5_000_000
})
```

## Common Patterns

### 1. Tool Availability Checking

```elixir
if Registry.tool_exists?(Registry, "read_file") do
  # Execute the tool
  Executor.execute("read_file", params, context)
else
  # Handle tool unavailability
  {:error, "Tool not available"}
end
```

### 2. Batch Tool Registration

```elixir
# Register multiple tools efficiently
tools = [
  %{name: "read_file", description: "Read file", inputSchema: %{}},
  %{name: "write_file", description: "Write file", inputSchema: %{}},
  %{name: "list_files", description: "List files", inputSchema: %{}}
]

Registry.register_tools(Registry, "filesystem_server", tools)
```

### 3. Tool Metadata Access

```elixir
{:ok, tool_route} = Registry.find_tool(Registry, "read_file")
IO.puts("Tool server: #{tool_route.server_id}")
IO.puts("Tool description: #{tool_route.tool.description}")
```

## Testing

The system includes comprehensive test coverage. Here's how to test your MCP tool integrations:

```elixir
# In your test files
defmodule MyMCPToolTest do
  use ExUnit.Case
  alias TheMaestro.MCP.Tools.{Registry, Executor}
  
  setup do
    {:ok, registry} = Registry.start_link([])
    
    # Register test tools
    tools = [
      %{name: "test_tool", description: "Test tool", inputSchema: %{}}
    ]
    Registry.register_tools(registry, "test_server", tools)
    
    %{registry: registry}
  end
  
  test "tool execution works", %{registry: registry} do
    context = %{
      server_id: "test_server",
      connection_manager: MockConnectionManager
    }
    
    {:ok, result} = Executor.execute("test_tool", %{}, context)
    assert result.server_id == "test_server"
  end
end
```

## Best Practices

1. **Always validate parameters** before tool execution
2. **Handle all error types** gracefully in your application
3. **Monitor tool performance** using the built-in metrics
4. **Validate content security** for user-facing applications
5. **Use appropriate timeouts** based on tool complexity
6. **Cache tool metadata** to improve performance
7. **Implement proper cleanup** for temporary resources

## Troubleshooting

### Common Issues

1. **Tool Not Found**
   - Verify the tool is registered in the registry
   - Check for namespace conflicts (tool might be prefixed)

2. **Parameter Validation Errors**
   - Ensure all required parameters are provided
   - Check parameter types match the tool schema

3. **Execution Timeouts**
   - Increase timeout values for long-running tools
   - Check MCP server responsiveness

4. **Content Processing Errors**
   - Verify content format matches MCP specification
   - Check for content size limits

### Debug Mode

Enable debug logging for detailed execution traces:

```elixir
Logger.configure(level: :debug)

# Tool execution will now show detailed logs
Executor.execute("read_file", %{"path" => "/test.txt"}, context)
```

## Conclusion

The MCP Tool Registration & Execution Engine provides a robust foundation for extending agent capabilities with external tools. It handles the complexity of MCP protocol communication while providing a simple, reliable interface for tool execution with comprehensive error handling, security validation, and performance monitoring.

For more advanced use cases, see the API documentation and explore the extensive test suite for additional examples.
# Epic 1, Story 1.5: Tooling DSL & Sandboxed File Tool

**Tutorial: Building a Secure Tool System with Test-Driven Development**

## Overview

In this story, we implemented a comprehensive tooling system that allows AI agents to safely execute external capabilities through a sandboxed interface. This tutorial demonstrates how we built this system using Test-Driven Development (TDD) principles.

## What We Built

### 1. Tool Behaviour Interface
A standardized interface that all tools must implement:

```elixir
defmodule TheMaestro.Tooling.Tool do
  @callback definition() :: map()
  @callback execute(map()) :: {:ok, map()} | {:error, term()}
  @callback validate_arguments(map()) :: :ok | {:error, term()}
end
```

### 2. Tool Registry System
A GenServer-based registry for managing and executing tools:

```elixir
# Register a tool
TheMaestro.Tooling.register_tool("read_file", MyModule, definition, executor)

# Execute a tool
TheMaestro.Tooling.execute_tool("read_file", %{"path" => "/safe/path/file.txt"})

# List available tools
TheMaestro.Tooling.get_tool_definitions()
```

### 3. Sandboxed FileSystem Tool
A secure file operations tool with path validation:

```elixir
# Only allows access within pre-configured directories
%{
  "content" => "file content",
  "path" => "/allowed/path/file.txt", 
  "size" => 123
} = FileSystem.execute(%{"path" => "/allowed/path/file.txt"})
```

### 4. Agent Integration
Integration with the Agent GenServer for LLM function calling:

```elixir
# Agent can now discover and execute tools
# Tools are passed to LLM providers for function calling
# Results are formatted and returned to the user
```

## Key Design Principles

### Security First
- **Path Validation**: Prevents directory traversal attacks
- **Sandboxing**: Only operates within allowed directories
- **Input Validation**: Validates all parameters against schemas
- **Error Handling**: Graceful handling of malicious inputs

### Test-Driven Development
We followed strict TDD principles:

1. **RED Phase**: Wrote comprehensive tests that initially failed
2. **GREEN Phase**: Implemented minimal code to make tests pass
3. **REFACTOR Phase**: Ready for optimization while maintaining test coverage

### Extensibility
The system is designed for easy extension:

```elixir
defmodule MyApp.Tools.Calculator do
  use TheMaestro.Tooling.Tool

  @impl true
  def definition do
    %{
      "name" => "calculate",
      "description" => "Performs arithmetic calculations",
      "parameters" => %{
        "type" => "object", 
        "properties" => %{
          "expression" => %{
            "type" => "string",
            "description" => "Mathematical expression"
          }
        },
        "required" => ["expression"]
      }
    }
  end

  @impl true  
  def execute(%{"expression" => expr}) do
    # Safe calculation logic
    {:ok, %{"result" => calculate(expr)}}
  end
end
```

## Test Coverage

We achieved comprehensive test coverage with 28 new tests:

- **Tool Behaviour Tests** (11 tests): Interface validation and patterns
- **Tooling Registry Tests** (11 tests): Registration, execution, concurrency
- **FileSystem Tool Tests** (16 tests): Security, operations, edge cases

### Key Testing Strategies

1. **Security Testing**: Directory traversal prevention
2. **Concurrent Safety**: Thread-safe operations
3. **Error Handling**: Comprehensive edge case coverage
4. **Performance Testing**: Large file handling
5. **Integration Testing**: Agent GenServer integration

## Security Features

### Path Validation
```elixir
# ✅ Allowed
"/tmp/maestro_sandbox/file.txt"

# ❌ Blocked - outside sandbox
"/etc/passwd" 

# ❌ Blocked - directory traversal
"/tmp/maestro_sandbox/../../../etc/passwd"
```

### Configuration
```elixir
config :the_maestro, :file_system_tool,
  allowed_directories: [
    "/tmp/maestro_sandbox",
    "/home/user/safe_projects" 
  ],
  max_file_size: 10 * 1024 * 1024  # 10MB
```

## Architecture Benefits

### OTP Integration
- **GenServer Registry**: Thread-safe tool management
- **Supervision**: Fault-tolerant tool execution
- **Message Passing**: Async tool operations

### LLM Provider Integration
Tools are automatically available to LLM providers via OpenAI Function Calling format:

```json
{
  "name": "read_file",
  "description": "Reads file contents securely",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string", 
        "description": "File path within allowed directories"
      }
    },
    "required": ["path"]
  }
}
```

## Next Steps

1. **Add More Tools**: Shell command, API client, search tools
2. **Enhanced Security**: Rate limiting, resource quotas
3. **Performance**: Caching, parallel execution
4. **Monitoring**: Metrics, logging, observability

## Key Takeaways

1. **TDD Works**: Writing tests first drove better design
2. **Security is Critical**: Sandboxing prevents malicious usage  
3. **Extensibility Matters**: Clean interfaces enable easy tool addition
4. **OTP is Powerful**: GenServers provide robust concurrency
5. **Integration is Key**: Tools must work seamlessly with LLM providers

This implementation provides a solid foundation for extending AI agent capabilities while maintaining security and reliability.
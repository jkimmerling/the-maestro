# Tutorial: Epic 3 Story 3.3 - Sandboxed Shell Command Tool

This tutorial explains how to implement a sandboxed shell command execution tool for the AI agent system, following Epic 3 Story 3.3 requirements.

## Overview

The shell command tool allows the AI agent to execute shell commands in a secure, sandboxed environment. This provides the agent with system-level capabilities while maintaining security through containerization and command validation.

## Architecture

### Core Components

1. **Shell Tool Module** (`lib/the_maestro/tooling/tools/shell.ex`)
   - Main shell execution logic with Docker sandboxing
   - Command validation and security filtering
   - Configuration management

2. **ExecuteCommand Tool** 
   - Implements the `Tool` behavior using `deftool` DSL pattern
   - Provides the `execute_command` tool interface
   - Handles parameter validation and execution delegation

3. **Security Layer**
   - Docker-based sandboxing for command isolation
   - Command validation against blocked operations
   - Configurable allowlists and blocklists
   - Output size and execution time limits

## Implementation Details

### 1. Tool Definition Structure

The shell tool follows the established DSL pattern used throughout the system:

```elixir
defmodule ExecuteCommand do
  use TheMaestro.Tooling.Tool

  @impl true
  def definition do
    %{
      "name" => "execute_command",
      "description" => "Executes a shell command in a sandboxed Docker environment...",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string", "description" => "The shell command to execute"},
          "description" => %{"type" => "string", "description" => "Optional description"},
          "directory" => %{"type" => "string", "description" => "Optional working directory"}
        },
        "required" => ["command"]
      }
    }
  end
end
```

### 2. Security Architecture

#### Docker Sandboxing

Commands are executed in isolated Docker containers with strict security constraints:

```elixir
docker_args = [
  "run",
  "--rm",                    # Remove container after execution
  "--network=none",          # Disable network access
  "--user=nobody:nogroup",   # Run as unprivileged user
  "--read-only",             # Make filesystem read-only
  "--tmpfs=/tmp:rw,noexec,nosuid,size=100m",  # Limited temp space
  "--cpus=0.5",              # Limit CPU usage
  "--memory=256m",           # Limit memory usage
  "--ulimit=nproc=10",       # Limit number of processes
  docker_image,
  "bash", "-c", command
]
```

#### Command Validation

Multiple layers of command validation prevent dangerous operations:

```elixir
def validate_command(command) do
  cond do
    command == "" ->
      {:error, "Command cannot be empty"}
    
    blocked_command?(command) ->
      {:error, "Command contains blocked operations"}
    
    allowed_commands_configured?() and not allowed_command?(command) ->
      {:error, "Command is not in the allowlist"}
    
    true ->
      :ok
  end
end
```

Default blocked commands include:
- `rm -rf` (recursive deletion)
- `dd if=` (disk operations)
- `mkfs` (filesystem creation)
- `shutdown`, `reboot`, `halt` (system control)

### 3. Configuration System

The tool uses application configuration for security and operational settings:

```elixir
config :the_maestro, :shell_tool,
  enabled: true,                    # Enable/disable the shell tool
  sandbox_enabled: true,            # Enable/disable sandboxing (SECURITY)
  docker_image: "ubuntu:22.04",    # Docker image for sandbox
  timeout_seconds: 30,              # Command execution timeout
  max_output_size: 1024 * 1024,     # Maximum output size (1MB)
  allowed_commands: [],             # Optional allowlist (empty = allow all)
  blocked_commands: [               # Blocked dangerous commands
    "rm -rf", "dd if=", "mkfs", "fdisk", "shutdown", "reboot"
  ]
```

### 4. Execution Flow

The shell tool execution follows this flow:

1. **Configuration Check**: Verify tool is enabled
2. **Command Validation**: Check against security policies
3. **Sandbox Decision**: Choose Docker sandbox or direct execution
4. **Docker Setup**: Build secure container configuration
5. **Command Execution**: Run command with timeout and output limits
6. **Result Processing**: Parse output and return structured results

## Testing Strategy

### Unit Tests

Test core functionality without external dependencies:

```elixir
describe "Shell.validate_command/1" do
  test "accepts valid commands" do
    assert Shell.validate_command("ls -la") == :ok
    assert Shell.validate_command("echo hello") == :ok
  end

  test "rejects blocked commands" do
    assert {:error, "Command contains blocked operations"} = 
      Shell.validate_command("rm -rf /")
  end
end
```

### Integration Tests

Test actual command execution with different configurations:

```elixir
test "executes simple commands successfully" do
  {:ok, result} = ExecuteCommand.execute(%{"command" => "echo hello world"})
  
  assert result["command"] == "echo hello world"
  assert result["stdout"] =~ "hello world"
  assert result["exit_code"] == 0
  assert result["sandboxed"] == false  # When sandbox disabled for testing
end
```

## Security Considerations

### Sandboxing Benefits

1. **Process Isolation**: Commands run in completely isolated containers
2. **Network Isolation**: No network access prevents data exfiltration
3. **Filesystem Protection**: Read-only root filesystem prevents system modification
4. **Resource Limits**: CPU, memory, and process limits prevent resource exhaustion
5. **Privilege Dropping**: Commands run as unprivileged user

### Configuration Best Practices

1. **Keep Sandboxing Enabled**: Always use `sandbox_enabled: true` in production
2. **Use Allowlists**: Configure specific allowed commands for maximum security
3. **Monitor Blocked Commands**: Regularly review and update blocked command list
4. **Set Appropriate Limits**: Configure timeouts and output limits for your use case
5. **Docker Security**: Keep Docker and base images updated

### Operational Considerations

1. **Docker Dependency**: Requires Docker installation for full security
2. **Performance Impact**: Sandboxing adds overhead compared to direct execution
3. **Container Management**: Containers are ephemeral and cleaned up automatically
4. **Logging**: All command executions are logged for audit purposes

## Configuration Options

### Development Configuration

For development environments, you might disable sandboxing for faster execution:

```elixir
config :the_maestro, :shell_tool,
  enabled: true,
  sandbox_enabled: false,  # Disable for development speed
  timeout_seconds: 10,
  max_output_size: 1024 * 1024
```

### Production Configuration

For production, maintain maximum security:

```elixir
config :the_maestro, :shell_tool,
  enabled: true,
  sandbox_enabled: true,           # Always enabled in production
  docker_image: "ubuntu:22.04",
  timeout_seconds: 30,
  max_output_size: 1024 * 1024,
  allowed_commands: [              # Restrict to specific commands
    "ls", "cat", "grep", "find", "git"
  ],
  blocked_commands: [              # Comprehensive blocklist
    "rm -rf", "dd if=", "mkfs", "fdisk", "parted",
    "shutdown", "reboot", "halt", "kill -9 -1"
  ]
```

## Integration with Agent System

### Tool Registration

The shell tool is automatically registered during application startup:

```elixir
# In application.ex
def start(_type, _args) do
  # ... supervisor setup ...
  
  case Supervisor.start_link(children, opts) do
    {:ok, _pid} = result ->
      # Register built-in tools
      FileSystem.register_tools()
      Shell.register_tool()     # Register shell tool
      result
  end
end
```

### Agent Usage

The agent can use the shell tool through the standard tool interface:

```elixir
# Agent calls tool with parameters
{:ok, result} = TheMaestro.Tooling.execute_tool("execute_command", %{
  "command" => "ls -la /tmp",
  "description" => "List temporary directory contents"
})

# Result contains execution details
result["stdout"]           # Command output
result["exit_code"]        # Exit code
result["execution_time_ms"] # Execution time
result["sandboxed"]        # Whether command was sandboxed
```

## Comparison with Original Gemini CLI

The implementation closely follows the original gemini-cli shell tool design:

### Similarities

1. **Command Structure**: Same parameter structure (command, description, directory)
2. **Security Focus**: Comprehensive command validation and sandboxing
3. **Output Format**: Detailed execution results with timing and status
4. **Configuration**: Flexible enable/disable and sandbox bypass options

### Enhancements

1. **OTP Integration**: Leverages Elixir's fault tolerance and supervision
2. **Behavior Pattern**: Uses consistent Tool behavior across all tools
3. **Docker Security**: Enhanced container security with resource limits
4. **Configuration System**: Elixir's application configuration system

### Key Differences

1. **Language**: Elixir vs TypeScript/Node.js
2. **Container Strategy**: Docker-focused vs multiple sandbox options
3. **Error Handling**: OTP-style error handling with supervision trees
4. **Testing**: ExUnit-based testing with clear separation of unit/integration tests

## Troubleshooting

### Common Issues

1. **Docker Not Available**: Install Docker or disable sandboxing
2. **Permission Errors**: Check Docker daemon permissions
3. **Timeout Issues**: Adjust timeout_seconds configuration
4. **Command Blocked**: Review blocked_commands list or add to allowed_commands

### Debug Configuration

Enable debug logging to troubleshoot issues:

```elixir
config :logger, level: :debug

# Shell tool will log execution details
# Look for "Shell tool:" prefixed messages
```

## Future Enhancements

1. **Multiple Sandbox Options**: Support for additional isolation technologies
2. **Command History**: Track and audit command execution history
3. **Resource Monitoring**: Real-time resource usage monitoring
4. **Custom Environments**: Configurable Docker images per command type
5. **Async Execution**: Background command execution for long-running tasks

This tutorial provides a comprehensive guide to implementing secure shell command execution in an AI agent system, balancing functionality with security through containerization and validation.
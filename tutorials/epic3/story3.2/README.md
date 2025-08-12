# Epic 3, Story 3.2: Full File System Tool (Write & List)

## Tutorial: Extending the File System Tool with Write and List Capabilities

This tutorial explains how we expanded the Maestro AI agent's file system capabilities by adding `write_file` and `list_directory` tools alongside the existing `read_file` functionality.

### Overview

In Epic 1, we built a basic file reading tool. Now we're enhancing it to support:
- **Writing files** with automatic directory creation
- **Listing directory contents** with detailed metadata
- **Maintaining security** through consistent path validation

### Key Learning Objectives

By the end of this tutorial, you'll understand:
- How to structure multi-tool modules in Elixir
- Path validation and security considerations for file operations
- Tool registration patterns in OTP applications
- Test-driven development for agent tools

## Architecture Changes

### Before: Single Tool Module

Previously, the `FileSystem` module implemented a single tool:

```elixir
defmodule TheMaestro.Tooling.Tools.FileSystem do
  use TheMaestro.Tooling.Tool
  
  @impl true
  def definition do
    # Single tool definition
  end
  
  @impl true  
  def execute(args) do
    # Single tool execution
  end
end
```

### After: Multi-Tool Module with Nested Modules

Now, we organize multiple related tools under a namespace:

```elixir
defmodule TheMaestro.Tooling.Tools.FileSystem do
  # Shared utilities and configuration
  
  defmodule ReadFile do
    use TheMaestro.Tooling.Tool
    # Read file implementation
  end
  
  defmodule WriteFile do
    use TheMaestro.Tooling.Tool
    # Write file implementation
  end
  
  defmodule ListDirectory do
    use TheMaestro.Tooling.Tool
    # List directory implementation
  end
end
```

## Implementation Details

### 1. Shared Path Validation

All file system tools share common security functions:

```elixir
# Validate file paths (existing files)
def validate_path(path) do
  with {:ok, resolved_path} <- resolve_path(path),
       :ok <- check_path_allowed(resolved_path),
       :ok <- check_file_exists(resolved_path) do
    {:ok, resolved_path}
  end
end

# Validate write paths (files that may not exist yet)
def validate_write_path(path) do
  with {:ok, resolved_path} <- resolve_path(path),
       :ok <- check_path_allowed(resolved_path) do
    {:ok, resolved_path}
  end
end

# Validate directory paths
def validate_directory_path(path) do
  with {:ok, resolved_path} <- resolve_path(path),
       :ok <- check_path_allowed(resolved_path),
       :ok <- check_directory_exists(resolved_path) do
    {:ok, resolved_path}
  end
end
```

### 2. WriteFile Tool Implementation

The write tool handles file creation with directory scaffolding:

```elixir
def execute(%{"path" => path, "content" => content}) do
  with {:ok, validated_path} <- validate_write_path(path),
       :ok <- ensure_parent_directory(validated_path),
       :ok <- File.write(validated_path, content) do
    {:ok, %{
      "message" => "Successfully wrote to file",
      "path" => validated_path,
      "size" => byte_size(content)
    }}
  end
end
```

Key features:
- **Automatic directory creation**: `ensure_parent_directory/1` creates any missing parent directories
- **Path validation**: Ensures the target path is within allowed directories
- **Atomic operations**: Uses Elixir's `with` construct for safe error handling

### 3. ListDirectory Tool Implementation

The list tool provides detailed directory metadata:

```elixir
def execute(%{"path" => path}) do
  with {:ok, validated_path} <- validate_directory_path(path),
       {:ok, entries} <- File.ls(validated_path) do
    
    detailed_entries = 
      entries
      |> Enum.map(fn entry ->
        entry_path = Path.join(validated_path, entry)
        case File.stat(entry_path) do
          {:ok, %File.Stat{type: type}} ->
            %{
              "name" => entry,
              "type" => Atom.to_string(type),
              "path" => entry_path
            }
        end
      end)
      |> Enum.sort_by(fn %{"type" => type, "name" => name} ->
        # Directories first, then alphabetical
        {type != "directory", String.downcase(name)}
      end)
    
    {:ok, %{
      "entries" => detailed_entries,
      "path" => validated_path,
      "count" => length(detailed_entries)
    }}
  end
end
```

Features:
- **Rich metadata**: Each entry includes name, type, and full path
- **Smart sorting**: Directories appear first, then files, both alphabetically
- **Type detection**: Uses `File.stat/1` to determine if entry is file, directory, etc.

### 4. Tool Registration Pattern

We register all tools during application startup:

```elixir
def register_tools do
  # Register read_file tool
  TheMaestro.Tooling.register_tool(
    "read_file",
    ReadFile,
    ReadFile.definition(),
    &ReadFile.execute/1
  )
  
  # Register write_file tool  
  TheMaestro.Tooling.register_tool(
    "write_file",
    WriteFile,
    WriteFile.definition(),
    &WriteFile.execute/1
  )
  
  # Register list_directory tool
  TheMaestro.Tooling.register_tool(
    "list_directory", 
    ListDirectory,
    ListDirectory.definition(),
    &ListDirectory.execute/1
  )
end
```

Updated in `application.ex`:
```elixir
case Supervisor.start_link(children, opts) do
  {:ok, _pid} = result ->
    # Register all file system tools
    FileSystem.register_tools()
    result
end
```

## Security Considerations

### Path Traversal Prevention

All tools use the same path resolution and validation:

```elixir
defp resolve_path(path) do
  case Path.type(path) do
    :absolute -> {:ok, Path.expand(path)}
    :relative -> {:ok, Path.expand(path, File.cwd!())}
    :volumerelative -> {:error, "Volume-relative paths are not supported"}
  end
end

defp check_path_allowed(path) do
  allowed_dirs = get_allowed_directories()
  
  path_allowed = Enum.any?(allowed_dirs, fn allowed_dir ->
    String.starts_with?(path, Path.expand(allowed_dir))
  end)
  
  if path_allowed do
    :ok
  else
    {:error, "Path '#{path}' is not within allowed directories"}
  end
end
```

### Configuration-Based Security

Allowed directories are configured in `config.exs`:

```elixir
config :the_maestro, :file_system_tool,
  allowed_directories: [
    "/tmp",
    "/safe/project/directory"
  ],
  max_file_size: 10 * 1024 * 1024  # 10MB
```

## Testing Strategy

### Comprehensive Test Coverage

We created separate test files for each tool:

1. **file_system_test.exs** - Original read functionality tests
2. **file_system_write_test.exs** - Write operation tests
3. **file_system_list_test.exs** - Directory listing tests
4. **file_system_integration_test.exs** - End-to-end workflow tests

### Test Isolation

Each test suite uses its own sandbox directory:

```elixir
setup do
  # Clean sandbox
  @test_sandbox_dir = "/tmp/maestro_test_sandbox_write"
  if File.exists?(@test_sandbox_dir), do: File.rm_rf!(@test_sandbox_dir)
  File.mkdir_p!(@test_sandbox_dir)
  
  # Configure allowed directories
  Application.put_env(:the_maestro, :file_system_tool,
    allowed_directories: [@test_sandbox_dir]
  )
  
  on_exit(fn -> File.rm_rf!(@test_sandbox_dir) end)
end
```

### Integration Testing

The integration tests verify the tools work together:

```elixir
test "can use all three tools together in a workflow" do
  # 1. List empty directory
  assert {:ok, list_result} = Tooling.execute_tool("list_directory", %{"path" => sandbox_dir})
  assert list_result["count"] == 0

  # 2. Write a file
  assert {:ok, _} = Tooling.execute_tool("write_file", %{
    "path" => test_file,
    "content" => content
  })

  # 3. List directory again - should show new file
  assert {:ok, list_result} = Tooling.execute_tool("list_directory", %{"path" => sandbox_dir})
  assert list_result["count"] == 1

  # 4. Read the file back
  assert {:ok, read_result} = Tooling.execute_tool("read_file", %{"path" => test_file})
  assert read_result["content"] == content
end
```

## Key Takeaways

### 1. Module Organization
- Use nested modules to group related tools under a common namespace
- Share common utilities (validation, configuration) at the parent module level
- Maintain backward compatibility with delegation functions

### 2. Security First
- Validate all paths through the same security pipeline
- Use configuration-driven allow-lists for directories
- Prevent path traversal attacks with proper path resolution

### 3. Error Handling
- Use Elixir's `with` construct for clear error propagation
- Provide meaningful error messages for debugging
- Handle edge cases (missing directories, permissions, etc.)

### 4. Testing Approach
- Test each tool in isolation with comprehensive edge cases
- Use integration tests to verify tool interactions
- Create clean test environments with proper setup/teardown

### 5. OTP Integration
- Register tools during application startup
- Use the existing tooling registry for consistent tool management
- Leverage Elixir's supervision tree for fault tolerance

## Running the Implementation

To test the new functionality:

```bash
# Run all file system tests
mix test test/the_maestro/tooling/tools/file_system*

# Start the application and verify tool registration
iex -S mix
iex> TheMaestro.Tooling.get_tool_definitions() |> Enum.map(& &1["name"])
["read_file", "write_file", "list_directory"]

# Test tool execution
iex> TheMaestro.Tooling.execute_tool("write_file", %{"path" => "/tmp/test.txt", "content" => "Hello!"})
{:ok, %{"message" => "Successfully wrote to file", "path" => "/tmp/test.txt", "size" => 6}}

iex> TheMaestro.Tooling.execute_tool("list_directory", %{"path" => "/tmp"})
{:ok, %{"entries" => [...], "path" => "/tmp", "count" => ...}}
```

This implementation successfully extends the Maestro agent with powerful, secure file system capabilities while maintaining the architectural principles of the existing system.
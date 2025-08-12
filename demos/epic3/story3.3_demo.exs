# Epic 3 Story 3.3 Demo: Sandboxed Shell Command Tool
#
# This demo showcases the shell command execution tool with sandboxing capabilities.
# Run this with: mix run demos/epic3/story3.3_demo.exs

IO.puts("=== Epic 3 Story 3.3: Sandboxed Shell Command Tool Demo ===")
IO.puts("")

# Start the application and tooling system
Application.ensure_all_started(:the_maestro)

# Configure shell tool for demo (disable sandboxing for simplicity)
Application.put_env(:the_maestro, :shell_tool, [
  enabled: true,
  sandbox_enabled: false,  # Disable for demo
  timeout_seconds: 10,
  max_output_size: 1024,
  blocked_commands: ["rm -rf", "dd if=", "mkfs", "shutdown"]
])

alias TheMaestro.Tooling.Tools.Shell
alias TheMaestro.Tooling.Tools.Shell.ExecuteCommand

IO.puts("1. Testing shell tool configuration...")

# Test if shell tool is enabled
if Shell.enabled?() do
  IO.puts("   ✓ Shell tool is enabled")
else
  IO.puts("   ✗ Shell tool is disabled")
end

# Test sandbox configuration
if Shell.sandbox_enabled?() do
  IO.puts("   ✓ Sandboxing is enabled (Docker required)")
else
  IO.puts("   ⚠ Sandboxing is disabled (direct execution)")
end

IO.puts("")

IO.puts("2. Testing command validation...")

# Test valid command
case Shell.validate_command("echo hello") do
  :ok -> IO.puts("   ✓ Valid command accepted: echo hello")
  {:error, reason} -> IO.puts("   ✗ Valid command rejected: #{reason}")
end

# Test blocked command
case Shell.validate_command("rm -rf /") do
  :ok -> IO.puts("   ✗ Dangerous command was accepted!")
  {:error, reason} -> IO.puts("   ✓ Dangerous command blocked: #{reason}")
end

IO.puts("")

IO.puts("3. Testing shell command execution...")

# Test simple command execution
IO.puts("   Executing: echo 'Hello from shell tool!'")
case ExecuteCommand.execute(%{"command" => "echo 'Hello from shell tool!'"}) do
  {:ok, result} ->
    IO.puts("   ✓ Command executed successfully")
    IO.puts("     Output: #{String.trim(result["stdout"])}")
    IO.puts("     Exit code: #{result["exit_code"]}")
    IO.puts("     Sandboxed: #{result["sandboxed"]}")
    IO.puts("     Execution time: #{result["execution_time_ms"]}ms")
  
  {:error, reason} ->
    IO.puts("   ✗ Command failed: #{reason}")
end

IO.puts("")

# Test command with description
IO.puts("   Executing command with description: pwd")
case ExecuteCommand.execute(%{
  "command" => "pwd", 
  "description" => "Show current working directory"
}) do
  {:ok, result} ->
    IO.puts("   ✓ Command with description executed")
    IO.puts("     Current directory: #{String.trim(result["stdout"])}")
  
  {:error, reason} ->
    IO.puts("   ✗ Command failed: #{reason}")
end

IO.puts("")

# Test listing files
IO.puts("   Executing: ls -la")
case ExecuteCommand.execute(%{"command" => "ls -la"}) do
  {:ok, result} ->
    IO.puts("   ✓ Directory listing executed")
    lines = String.split(result["stdout"], "\n") |> Enum.take(5)
    IO.puts("     First 5 lines of output:")
    Enum.each(lines, fn line -> 
      if String.trim(line) != "", do: IO.puts("       #{line}")
    end)
  
  {:error, reason} ->
    IO.puts("   ✗ Command failed: #{reason}")
end

IO.puts("")

IO.puts("4. Testing command failure handling...")

# Test non-existent command
case ExecuteCommand.execute(%{"command" => "nonexistentcommand123"}) do
  {:ok, result} ->
    IO.puts("   Command executed with exit code: #{result["exit_code"]}")
    if result["exit_code"] != 0 do
      IO.puts("   ✓ Non-existent command properly failed")
    end
  
  {:error, reason} ->
    IO.puts("   ✓ Non-existent command properly rejected: #{reason}")
end

IO.puts("")

IO.puts("5. Testing tool registration...")

# Check if tool is registered in the tooling system
definitions = TheMaestro.Tooling.get_tool_definitions()
shell_tool = Enum.find(definitions, fn tool -> tool["name"] == "execute_command" end)

if shell_tool do
  IO.puts("   ✓ Shell tool is properly registered")
  IO.puts("     Tool name: #{shell_tool["name"]}")
  IO.puts("     Description: #{String.slice(shell_tool["description"], 0, 50)}...")
else
  IO.puts("   ✗ Shell tool is not registered")
end

IO.puts("")

IO.puts("6. Configuration Summary:")
config = Application.get_env(:the_maestro, :shell_tool, [])
IO.puts("   - Enabled: #{Keyword.get(config, :enabled, false)}")
IO.puts("   - Sandbox enabled: #{Keyword.get(config, :sandbox_enabled, false)}")
IO.puts("   - Docker image: #{Keyword.get(config, :docker_image, "N/A")}")
IO.puts("   - Timeout: #{Keyword.get(config, :timeout_seconds, 0)} seconds")
IO.puts("   - Max output size: #{Keyword.get(config, :max_output_size, 0)} bytes")

blocked_commands = Keyword.get(config, :blocked_commands, [])
IO.puts("   - Blocked commands (#{length(blocked_commands)}): #{Enum.join(Enum.take(blocked_commands, 3), ", ")}...")

IO.puts("")
IO.puts("=== Demo completed! ===")
IO.puts("")
IO.puts("The shell tool provides:")
IO.puts("• Secure command execution with configurable sandboxing")
IO.puts("• Docker-based isolation (when enabled)")
IO.puts("• Command validation and blocking of dangerous operations")
IO.puts("• Configurable timeouts and output size limits")
IO.puts("• Detailed execution results including timing and exit codes")
IO.puts("")

if Shell.sandbox_enabled?() do
  case System.cmd("docker", ["version"], stderr_to_stdout: true) do
    {_output, 0} ->
      IO.puts("✓ Docker is available - sandboxing will work")
    {_output, _} ->
      IO.puts("⚠ Docker not available - commands will run directly")
      IO.puts("  Install Docker to enable full sandboxing capabilities")
  end
else
  IO.puts("⚠ Sandboxing is disabled in configuration")
  IO.puts("  Enable sandbox_enabled: true for maximum security")
end

IO.puts("")
IO.puts("For security in production:")
IO.puts("• Keep sandbox_enabled: true")
IO.puts("• Configure allowed_commands whitelist if needed")
IO.puts("• Review blocked_commands list")
IO.puts("• Set appropriate timeout and output limits")
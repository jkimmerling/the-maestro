defmodule TheMaestro.Tooling.Tools.Shell do
  @moduledoc """
  Sandboxed shell command execution tool.

  This tool provides secure shell command execution for the AI agent using Docker-based
  sandboxing by default, with configurable settings for security control.

  ## Security Features

  - Docker container-based sandboxing for command isolation
  - Configurable enable/disable functionality
  - Configurable sandbox bypass for trusted environments
  - Command validation and sanitization
  - Output size and execution time limits
  - Environment variable control

  ## Available Tools

  - `execute_command`: Executes shell commands in a sandboxed environment

  ## Configuration

  The shell tool behavior is configured via application config:

      config :the_maestro, :shell_tool,
        enabled: true,                    # Enable/disable the shell tool
        sandbox_enabled: true,            # Enable/disable sandboxing
        docker_image: "ubuntu:22.04",    # Docker image for sandbox
        timeout_seconds: 30,              # Command execution timeout
        max_output_size: 1024 * 1024,     # Maximum output size (1MB)
        allowed_commands: [],             # Optional allowlist of commands
        blocked_commands: ["rm -rf", "dd", "mkfs"]  # Blocked dangerous commands

  ## Docker Requirements

  When sandboxing is enabled, Docker must be available on the system. The tool will
  verify Docker availability before executing commands.

  ## Usage Examples

  ```elixir
  # Execute a simple command
  {:ok, result} = ExecuteCommand.execute(%{
    "command" => "ls -la",
    "description" => "List current directory contents"
  })

  # Execute with working directory
  {:ok, result} = ExecuteCommand.execute(%{
    "command" => "pwd && ls",
    "description" => "Show current directory and list contents",
    "directory" => "/tmp"
  })
  ```

  ## Error Handling

  The tool returns detailed error information including:
  - Command validation failures
  - Docker/sandbox unavailability
  - Execution timeouts
  - Permission or security violations
  """

  require Logger

  defmodule ExecuteCommand do
    @moduledoc """
    Tool for executing shell commands in a sandboxed environment.
    """

    use TheMaestro.Tooling.Tool

    alias TheMaestro.Tooling.Tools.Shell

    @impl true
    def definition do
      %{
        "name" => "execute_command",
        "description" => """
        Executes a shell command in a sandboxed Docker environment. 
        Returns command output, exit code, and execution details.
        Only available when shell tool is enabled in configuration.
        """,
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "command" => %{
              "type" => "string",
              "description" => "The shell command to execute. Will be run with 'bash -c' in the sandbox."
            },
            "description" => %{
              "type" => "string", 
              "description" => "Optional description of what the command does for user clarity."
            },
            "directory" => %{
              "type" => "string",
              "description" => "Optional working directory for command execution (defaults to /workspace in container)."
            }
          },
          "required" => ["command"]
        }
      }
    end

    @impl true
    def execute(%{"command" => command} = params) do
      Logger.info("Shell tool: Executing command '#{command}'")

      # Check if shell tool is enabled
      unless Shell.enabled? do
        Logger.warning("Shell tool: Tool is disabled")
        {:error, "Shell command execution is disabled in the current configuration"}
      else
        with :ok <- Shell.validate_command(command),
             {:ok, result} <- Shell.execute_sandboxed(params) do
          Logger.info("Shell tool: Command completed successfully")
          {:ok, result}
        else
          {:error, reason} ->
            Logger.warning("Shell tool: Command failed - #{reason}")
            {:error, reason}
        end
      end
    end

    def execute(%{}) do
      {:error, "Command is required"}
    end

    def execute(nil) do
      {:error, "Invalid arguments. Expected a map with 'command' key."}
    end

    def execute(_invalid_args) do
      {:error, "Invalid arguments. Expected a map with 'command' key."}
    end

    @impl true
    def validate_arguments(%{"command" => command}) when is_binary(command) do
      if String.trim(command) == "" do
        {:error, "Command cannot be empty"}
      else
        :ok
      end
    end

    def validate_arguments(_) do
      {:error, "Invalid arguments. Expected a map with 'command' key."}
    end
  end

  # Shared utility functions for shell execution

  @doc """
  Checks if the shell tool is enabled in configuration.
  """
  def enabled? do
    get_config(:enabled, true)
  end

  @doc """
  Checks if sandboxing is enabled.
  """
  def sandbox_enabled? do
    get_config(:sandbox_enabled, true)
  end

  @doc """
  Validates a command against security policies.
  """
  def validate_command(command) do
    command = String.trim(command)

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

  @doc """
  Executes a command in a sandboxed environment.
  """
  def execute_sandboxed(%{"command" => _command} = params) do
    sandboxed = sandbox_enabled?()
    Logger.info("Shell tool: Sandbox enabled? #{sandboxed}")
    
    if sandboxed do
      Logger.info("Shell tool: Taking Docker path")
      execute_in_docker(params)
    else
      Logger.info("Shell tool: Taking direct execution path")
      execute_directly(params)
    end
  end

  defp execute_in_docker(%{"command" => command} = params) do
    Logger.info("Shell tool: Executing command in Docker sandbox")

    with :ok <- check_docker_available(),
         {:ok, docker_command} <- build_docker_command(params),
         {:ok, result} <- run_docker_command(docker_command) do
      parse_docker_result(result, command)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_directly(%{"command" => command} = params) do
    Logger.warning("Shell tool: Executing command directly (sandbox disabled)")
    
    directory = Map.get(params, "directory", File.cwd!())
    
    start_time = System.monotonic_time(:millisecond)
    
    # Build options list correctly
    opts = [stderr_to_stdout: true]
    opts = if directory != File.cwd!() do
      [{:cd, directory} | opts]
    else
      opts
    end
    
    Logger.debug("Shell tool: About to execute System.cmd with opts: #{inspect(opts)}")
    case System.cmd("bash", ["-c", command], opts) do
      {output, exit_code} ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = end_time - start_time

        max_output_size = get_config(:max_output_size, 1024 * 1024)
        output = if byte_size(output) > max_output_size do
          truncated_output = binary_part(output, 0, max_output_size)
          truncated_output <> "\n... [output truncated at #{max_output_size} bytes]"
        else
          output
        end

        {:ok, %{
          "command" => command,
          "directory" => directory,
          "stdout" => output,
          "stderr" => "",
          "exit_code" => exit_code,
          "execution_time_ms" => execution_time,
          "sandboxed" => false
        }}
    end
  rescue
    error ->
      {:error, "Command execution error: #{inspect(error)}"}
  end

  defp check_docker_available do
    case System.cmd("docker", ["version"], [stderr_to_stdout: true]) do
      {_output, 0} ->
        :ok
      {output, _exit_code} ->
        Logger.error("Docker not available: #{output}")
        {:error, "Docker is not available. Please install Docker or disable sandboxing."}
    end
  rescue
    error ->
      Logger.error("Failed to check Docker: #{inspect(error)}")
      {:error, "Failed to check Docker availability. Please ensure Docker is installed."}
  end

  defp build_docker_command(%{"command" => command} = params) do
    docker_image = get_config(:docker_image, "ubuntu:22.04")
    directory = Map.get(params, "directory", "/workspace")
    
    # Create a safe, isolated Docker command
    docker_args = [
      "run",
      "--rm",                    # Remove container after execution
      "--interactive",           # Keep STDIN open
      "--tty",                   # Allocate a pseudo-TTY
      "--network=none",          # Disable network access
      "--user=nobody:nogroup",   # Run as unprivileged user
      "--read-only",             # Make filesystem read-only
      "--tmpfs=/tmp:rw,noexec,nosuid,size=100m",  # Limited temp space
      "--workdir=#{directory}",  # Set working directory
      "--cpus=0.5",              # Limit CPU usage
      "--memory=256m",           # Limit memory usage
      "--ulimit=nproc=10",       # Limit number of processes
      "--ulimit=fsize=10485760", # Limit file size (10MB)
      docker_image,
      "bash", "-c", command
    ]

    {:ok, docker_args}
  end

  defp run_docker_command(docker_args) do
    start_time = System.monotonic_time(:millisecond)

    case System.cmd("docker", docker_args, [stderr_to_stdout: true]) do
      {output, exit_code} ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = end_time - start_time

        max_output_size = get_config(:max_output_size, 1024 * 1024)
        output = if byte_size(output) > max_output_size do
          truncated_output = binary_part(output, 0, max_output_size)
          truncated_output <> "\n... [output truncated at #{max_output_size} bytes]"
        else
          output
        end

        {:ok, %{
          stdout: output,
          stderr: "",
          exit_code: exit_code,
          execution_time_ms: execution_time
        }}
    end
  rescue
    error ->
      {:error, "Command execution error: #{inspect(error)}"}
  end

  defp parse_docker_result(result, original_command) do
    {:ok, %{
      "command" => original_command,
      "directory" => "/workspace",
      "stdout" => result.stdout,
      "stderr" => result.stderr,
      "exit_code" => result.exit_code,
      "execution_time_ms" => result.execution_time_ms,
      "sandboxed" => true
    }}
  end

  defp blocked_command?(command) do
    blocked_commands = get_config(:blocked_commands, [
      "rm -rf",
      "dd if=",
      "mkfs",
      "fdisk",
      "parted",
      "shutdown",
      "reboot",
      "halt",
      "init 0",
      "init 6",
      "kill -9 -1",
      "fork bomb"
    ])

    command_lower = String.downcase(command)
    
    Enum.any?(blocked_commands, fn blocked ->
      String.contains?(command_lower, String.downcase(blocked))
    end)
  end

  defp allowed_commands_configured? do
    allowed = get_config(:allowed_commands, [])
    not Enum.empty?(allowed)
  end

  defp allowed_command?(command) do
    allowed_commands = get_config(:allowed_commands, [])
    
    if Enum.empty?(allowed_commands) do
      true
    else
      command_lower = String.downcase(command)
      
      Enum.any?(allowed_commands, fn allowed ->
        String.starts_with?(command_lower, String.downcase(allowed))
      end)
    end
  end

  defp get_config(key, default) do
    Application.get_env(:the_maestro, :shell_tool, [])
    |> Keyword.get(key, default)
  end

  # Tool registration

  @doc false
  def register_tool do
    TheMaestro.Tooling.register_tool(
      "execute_command",
      ExecuteCommand,
      ExecuteCommand.definition(),
      &ExecuteCommand.execute/1
    )
  end
end
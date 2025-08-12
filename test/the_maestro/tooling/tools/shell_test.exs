defmodule TheMaestro.Tooling.Tools.ShellTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Tooling.Tools.Shell
  alias TheMaestro.Tooling.Tools.Shell.ExecuteCommand

  describe "ExecuteCommand.definition/0" do
    test "returns correct tool definition" do
      definition = ExecuteCommand.definition()

      assert definition["name"] == "execute_command"
      assert definition["description"] =~ "Executes a shell command"
      assert definition["parameters"]["type"] == "object"

      properties = definition["parameters"]["properties"]
      assert Map.has_key?(properties, "command")
      assert Map.has_key?(properties, "description")
      assert Map.has_key?(properties, "directory")

      required = definition["parameters"]["required"]
      assert "command" in required
    end
  end

  describe "ExecuteCommand.validate_arguments/1" do
    test "validates valid arguments" do
      assert ExecuteCommand.validate_arguments(%{"command" => "ls -la"}) == :ok
    end

    test "rejects empty command" do
      assert {:error, "Command cannot be empty"} =
               ExecuteCommand.validate_arguments(%{"command" => ""})

      assert {:error, "Command cannot be empty"} =
               ExecuteCommand.validate_arguments(%{"command" => "   "})
    end

    test "rejects invalid argument structure" do
      assert {:error, "Invalid arguments. Expected a map with 'command' key."} =
               ExecuteCommand.validate_arguments(%{})

      assert {:error, "Invalid arguments. Expected a map with 'command' key."} =
               ExecuteCommand.validate_arguments(%{"not_command" => "ls"})

      assert {:error, "Invalid arguments. Expected a map with 'command' key."} =
               ExecuteCommand.validate_arguments("invalid")
    end
  end

  describe "Shell.enabled?/0" do
    test "returns configuration value" do
      # Test with default configuration
      assert Shell.enabled?() == true
    end
  end

  describe "Shell.sandbox_enabled?/0" do
    test "returns configuration value" do
      # Test with default configuration  
      assert Shell.sandbox_enabled?() == true
    end
  end

  describe "Shell.validate_command/1" do
    test "accepts valid commands" do
      assert Shell.validate_command("ls -la") == :ok
      assert Shell.validate_command("echo hello") == :ok
      assert Shell.validate_command("pwd") == :ok
    end

    test "rejects empty commands" do
      assert {:error, "Command cannot be empty"} = Shell.validate_command("")
      assert {:error, "Command cannot be empty"} = Shell.validate_command("   ")
    end

    test "rejects blocked commands by default" do
      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("rm -rf /")

      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("dd if=/dev/zero of=/dev/sda")

      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("mkfs.ext4 /dev/sda1")

      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("shutdown now")
    end

    test "case insensitive blocking" do
      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("RM -RF /")

      assert {:error, "Command contains blocked operations"} =
               Shell.validate_command("Shutdown now")
    end
  end

  describe "ExecuteCommand.execute/1 with disabled tool" do
    setup do
      # Temporarily disable the shell tool
      original_config = Application.get_env(:the_maestro, :shell_tool, [])
      Application.put_env(:the_maestro, :shell_tool, enabled: false)

      on_exit(fn ->
        Application.put_env(:the_maestro, :shell_tool, original_config)
      end)
    end

    test "returns error when tool is disabled" do
      assert {:error, "Shell command execution is disabled in the current configuration"} =
               ExecuteCommand.execute(%{"command" => "echo hello"})
    end
  end

  describe "ExecuteCommand.execute/1 argument validation" do
    test "handles invalid arguments" do
      assert {:error, "Command is required"} = ExecuteCommand.execute(%{})

      assert {:error, "Invalid arguments. Expected a map with 'command' key."} =
               ExecuteCommand.execute(nil)

      assert {:error, "Invalid arguments. Expected a map with 'command' key."} =
               ExecuteCommand.execute("invalid")
    end
  end

  # Note: Integration tests that actually execute commands would require Docker
  # and would be better suited for integration test files rather than unit tests.
  # The actual command execution logic is tested through mocking or in integration tests.

  describe "shell tool configuration" do
    test "reads default configuration values correctly" do
      # Test that default config values are accessible
      config = Application.get_env(:the_maestro, :shell_tool, [])

      # These should match our config.exs defaults
      assert Keyword.get(config, :enabled, true) == true
      assert Keyword.get(config, :sandbox_enabled, true) == true
      assert Keyword.get(config, :docker_image, "ubuntu:22.04") == "ubuntu:22.04"
      assert Keyword.get(config, :timeout_seconds, 30) == 30
      assert Keyword.get(config, :max_output_size, 1024 * 1024) == 1024 * 1024
    end

    test "blocked commands list includes dangerous operations" do
      config = Application.get_env(:the_maestro, :shell_tool, [])
      blocked = Keyword.get(config, :blocked_commands, [])

      assert "rm -rf" in blocked
      assert "dd if=" in blocked
      assert "mkfs" in blocked
      assert "shutdown" in blocked
    end
  end
end

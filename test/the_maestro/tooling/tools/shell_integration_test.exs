defmodule TheMaestro.Tooling.Tools.ShellIntegrationTest do
  use ExUnit.Case

  alias TheMaestro.Tooling.Tools.Shell.ExecuteCommand

  @moduletag :integration

  describe "ExecuteCommand integration tests" do
    setup do
      # Ensure shell tool is enabled for integration tests
      original_config = Application.get_env(:the_maestro, :shell_tool, [])
      
      # Configure for testing with sandboxing disabled for simpler testing
      test_config = Keyword.merge(original_config, [
        enabled: true,
        sandbox_enabled: false,  # Disable Docker for integration tests
        timeout_seconds: 10,
        max_output_size: 1024
      ])
      
      Application.put_env(:the_maestro, :shell_tool, test_config)
      
      on_exit(fn ->
        Application.put_env(:the_maestro, :shell_tool, original_config)
      end)
    end

    test "executes simple commands successfully" do
      result = ExecuteCommand.execute(%{"command" => "echo hello world"})
      
      case result do
        {:ok, result_data} ->
          assert result_data["command"] == "echo hello world"
          assert result_data["stdout"] =~ "hello world"
          assert result_data["exit_code"] == 0
          assert result_data["sandboxed"] == false
          assert is_integer(result_data["execution_time_ms"])
        
        {:error, reason} ->
          flunk("Command execution failed: #{reason}")
      end
    end

    test "captures command output correctly" do
      {:ok, result} = ExecuteCommand.execute(%{"command" => "pwd"})
      
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) =~ "/the-maestro"
    end

    test "handles command failures" do
      {:ok, result} = ExecuteCommand.execute(%{"command" => "false"})
      
      assert result["command"] == "false"
      assert result["exit_code"] == 1
    end

    test "handles non-existent commands" do
      {:ok, result} = ExecuteCommand.execute(%{"command" => "nonexistentcommand123"})
      
      assert result["exit_code"] != 0
      assert result["stdout"] =~ "not found" or result["stdout"] =~ "command not found"
    end

    test "includes optional description" do
      params = %{
        "command" => "echo test",
        "description" => "Testing echo command"
      }
      
      {:ok, result} = ExecuteCommand.execute(params)
      assert result["exit_code"] == 0
    end

    test "respects timeout configuration" do
      # Temporarily set a very short timeout
      original_config = Application.get_env(:the_maestro, :shell_tool, [])
      short_timeout_config = Keyword.put(original_config, :timeout_seconds, 1)
      Application.put_env(:the_maestro, :shell_tool, short_timeout_config)
      
      # This command should timeout (sleep for 3 seconds with 1 second timeout)
      {:error, reason} = ExecuteCommand.execute(%{"command" => "sleep 3"})
      assert reason =~ "execution"
      
      # Restore original config
      Application.put_env(:the_maestro, :shell_tool, original_config)
    end

    test "rejects blocked commands" do
      {:error, reason} = ExecuteCommand.execute(%{"command" => "rm -rf /tmp/test"})
      assert reason == "Command contains blocked operations"
    end

    test "truncates large output" do
      # Temporarily set a small output size limit
      original_config = Application.get_env(:the_maestro, :shell_tool, [])
      small_output_config = Keyword.put(original_config, :max_output_size, 100)
      Application.put_env(:the_maestro, :shell_tool, small_output_config)
      
      # Generate output larger than 100 bytes
      {:ok, result} = ExecuteCommand.execute(%{
        "command" => "python3 -c \"print('A' * 200)\""
      })
      
      assert byte_size(result["stdout"]) <= 150  # Account for truncation message
      assert result["stdout"] =~ "output truncated"
      
      # Restore original config
      Application.put_env(:the_maestro, :shell_tool, original_config)
    end
  end

  describe "Docker sandbox integration tests" do
    @tag :docker
    test "executes commands in Docker when sandbox is enabled" do
      # Skip this test if Docker is not available
      case System.cmd("docker", ["version"], stderr_to_stdout: true) do
        {_output, 0} ->
          # Docker is available, run the test
          original_config = Application.get_env(:the_maestro, :shell_tool, [])
          
          docker_config = Keyword.merge(original_config, [
            enabled: true,
            sandbox_enabled: true,
            timeout_seconds: 30
          ])
          
          Application.put_env(:the_maestro, :shell_tool, docker_config)
          
          {:ok, result} = ExecuteCommand.execute(%{"command" => "echo hello from docker"})
          
          assert result["command"] == "echo hello from docker"
          assert result["stdout"] =~ "hello from docker"
          assert result["exit_code"] == 0
          assert result["sandboxed"] == true
          
          # Restore original config
          Application.put_env(:the_maestro, :shell_tool, original_config)
          
        {_output, _exit_code} ->
          # Docker not available, skip test
          IO.puts("Skipping Docker integration test - Docker not available")
          :ok
      end
    end
  end
end
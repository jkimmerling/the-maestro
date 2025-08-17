defmodule TheMaestro.MCP.Transport.StdioTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Transport.Stdio

  describe "start_link/1" do
    test "starts stdio transport with valid config" do
      config = %{
        command: "echo",
        args: ["hello"],
        cwd: "/tmp",
        env: %{"TEST" => "value"},
        timeout: 30_000
      }

      assert {:ok, pid} = Stdio.start_link(config)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "fails with invalid command" do
      config = %{
        command: "nonexistent_command_12345",
        args: [],
        timeout: 30_000
      }

      assert {:error, _reason} = Stdio.start_link(config)
    end
  end

  describe "send_message/2" do
    test "sends JSON message to process stdin" do
      config = %{
        command: "cat",  # cat will echo back what we send
        args: [],
        timeout: 5_000
      }

      {:ok, transport} = Stdio.start_link(config)

      message = %{
        jsonrpc: "2.0",
        id: "test-123",
        method: "initialize",
        params: %{}
      }

      assert :ok = Stdio.send_message(transport, message)

      GenServer.stop(transport)
    end

    test "handles send error when process is dead" do
      config = %{
        command: "echo",
        args: ["test"],
        timeout: 1_000
      }

      {:ok, transport} = Stdio.start_link(config)
      
      # Wait for echo to finish and exit
      Process.sleep(100)

      message = %{jsonrpc: "2.0", id: "test", method: "test"}

      # This should either succeed (if process still alive) or fail gracefully
      result = Stdio.send_message(transport, message)
      assert result in [:ok, {:error, :process_dead}]

      GenServer.stop(transport)
    end
  end

  describe "close/1" do
    test "closes transport and terminates process" do
      config = %{
        command: "cat",
        args: [],
        timeout: 30_000
      }

      {:ok, transport} = Stdio.start_link(config)
      
      assert :ok = Stdio.close(transport)
      
      # Transport process should be terminated
      Process.sleep(50)
      refute Process.alive?(transport)
    end
  end

  describe "process management" do
    test "monitors subprocess and handles termination" do
      config = %{
        command: "echo",
        args: ["test"],
        timeout: 1_000
      }

      {:ok, transport} = Stdio.start_link(config)
      
      # Echo will terminate quickly
      Process.sleep(200)
      
      # Transport should handle subprocess termination gracefully
      state = :sys.get_state(transport)
      assert state.process_state in [:terminated, :dead]

      GenServer.stop(transport)
    end
  end
end
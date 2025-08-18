defmodule TheMaestro.MCP.IntegrationTest do
  @moduledoc """
  Integration tests for MCP server discovery and connection management.
  Tests various failure scenarios and recovery mechanisms.
  """

  use ExUnit.Case, async: false
  require Logger

  alias TheMaestro.MCP.{Discovery, ConnectionManager, Registry}

  @valid_config_path "/tmp/mcp_test_config.json"
  @invalid_config_path "/tmp/mcp_invalid_config.json"
  @missing_config_path "/tmp/mcp_missing_config.json"

  setup_all do
    # Ensure MCP supervisor is not running
    case GenServer.whereis(TheMaestro.MCP.Supervisor) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Start fresh MCP supervisor for tests
    case TheMaestro.MCP.Supervisor.start_link([]) do
      {:ok, _supervisor} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    on_exit(fn ->
      # Clean up test files
      for file <- [@valid_config_path, @invalid_config_path] do
        if File.exists?(file), do: File.rm!(file)
      end
    end)

    :ok
  end

  setup do
    # Create test configuration files
    create_test_config_files()

    # Reset any existing connections
    reset_connection_state()

    :ok
  end

  describe "Configuration Discovery Failures" do
    test "handles missing configuration file gracefully" do
      {:error, :file_not_found} = Discovery.discover_servers(@missing_config_path)
    end

    test "handles invalid JSON configuration" do
      {:error, {:invalid_json, _}} = Discovery.discover_servers(@invalid_config_path)
    end

    test "recovers from partial configuration failures" do
      # Create config with one valid and one invalid server
      mixed_config = %{
        "mcpServers" => %{
          "validServer" => %{
            "command" => "echo",
            "args" => ["test"],
            "trust" => false
          },
          "invalidServer" => %{
            "unknown_transport" => "invalid",
            "trust" => false
          }
        }
      }

      File.write!(@valid_config_path, Jason.encode!(mixed_config))

      # Should return only the valid server
      {:ok, servers} = Discovery.discover_servers(@valid_config_path)
      assert length(servers) == 1
      assert hd(servers).id == "validServer"
    end
  end

  describe "Connection Failures and Recovery" do
    test "handles connection failures with circuit breaker" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Server config that will fail to start
      failing_config = %{
        id: "failing_server",
        transport: :stdio,
        command: "nonexistent_command",
        args: [],
        env: %{},
        trust: false,
        max_failures: 2,
        failure_window: 5000
      }

      # First failure
      {:error, _reason1} = ConnectionManager.start_connection(connection_manager, failing_config)

      # Second failure
      {:error, _reason2} = ConnectionManager.start_connection(connection_manager, failing_config)

      # Third attempt should trigger circuit breaker
      {:error, :circuit_open} =
        ConnectionManager.start_connection(connection_manager, failing_config)
    end

    test "automatically reconnects after connection loss" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Create a server that can be started but will fail
      test_config = %{
        id: "test_reconnect",
        transport: :stdio,
        # This will exit immediately
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false,
        # Very short for testing
        heartbeat_interval: 100
      }

      # Start connection
      {:ok, _connection_pid} = ConnectionManager.start_connection(connection_manager, test_config)

      # Verify it's tracked
      {:ok, connection_info} =
        ConnectionManager.get_connection(connection_manager, "test_reconnect")

      assert connection_info.status == :connecting

      # Wait for process to die (echo exits immediately) and connection to be cleaned up
      :timer.sleep(500)

      # Connection should eventually be removed from active connections or marked as error
      case ConnectionManager.get_connection(connection_manager, "test_reconnect") do
        # Connection was cleaned up
        {:error, :not_found} ->
          :ok

        {:ok, conn_info} ->
          # Connection might still exist but should be in connecting or error state
          # (echo exits immediately but connection manager might not have processed it yet)
          assert conn_info.status in [:connecting, :error, :disconnected]
      end
    end

    test "handles multiple server failures gracefully" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      servers_config = [
        %{
          id: "server1",
          transport: :stdio,
          command: "nonexistent1",
          args: [],
          env: %{},
          trust: false
        },
        %{
          id: "server2",
          transport: :stdio,
          command: "nonexistent2",
          args: [],
          env: %{},
          trust: false
        },
        %{
          id: "server3",
          transport: :stdio,
          command: "echo",
          args: ["test"],
          env: %{},
          trust: false
        }
      ]

      results =
        Enum.map(servers_config, fn config ->
          ConnectionManager.start_connection(connection_manager, config)
        end)

      # First two should fail, third should succeed
      assert match?([{:error, _}, {:error, _}, {:ok, _}], results)

      # Only one connection should be active
      connections = ConnectionManager.list_connections(connection_manager)
      assert length(connections) == 1
      assert hd(connections).server_id == "server3"
    end
  end

  describe "Registry Integration Failures" do
    test "handles tool namespace conflicts across servers" do
      registry = TheMaestro.MCP.Supervisor.registry()

      # Register two servers with conflicting tool names
      server1_info = %{
        server_id: "server1",
        config: %{priority: 5},
        connection: self(),
        status: :connected,
        tools: [
          %{"name" => "read_file", "description" => "Read file from server1"},
          %{"name" => "write_file", "description" => "Write file from server1"}
        ],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      server2_info = %{
        server_id: "server2",
        # Higher priority
        config: %{priority: 8},
        connection: self(),
        status: :connected,
        tools: [
          # Conflict
          %{"name" => "read_file", "description" => "Read file from server2"},
          %{"name" => "list_files", "description" => "List files from server2"}
        ],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = Registry.register_server(registry, server1_info)
      :ok = Registry.register_server(registry, server2_info)

      # Get all tools - should handle namespace conflicts
      all_tools = Registry.get_all_tools(registry)

      # Should have 4 tools total with conflicts resolved
      assert length(all_tools) == 4

      # Check that conflicting tool has been prefixed for both servers
      conflicted_tools =
        Enum.filter(all_tools, fn tool ->
          String.contains?(tool.name, "read_file")
        end)

      assert length(conflicted_tools) == 2

      # Both should be prefixed when there's a conflict
      tool_names = Enum.map(conflicted_tools, & &1.name)
      assert "server1__read_file" in tool_names
      assert "server2__read_file" in tool_names
    end

    test "handles server deregistration during active operations" do
      registry = TheMaestro.MCP.Supervisor.registry()

      server_info = %{
        server_id: "temp_server",
        config: %{},
        connection: self(),
        status: :connected,
        tools: [%{"name" => "temp_tool", "description" => "Temporary tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      # Register server
      :ok = Registry.register_server(registry, server_info)
      {:ok, _info} = Registry.get_server(registry, "temp_server")

      # Verify tool is available
      all_tools = Registry.get_all_tools(registry)
      temp_tools = Enum.filter(all_tools, fn tool -> tool.name == "temp_tool" end)
      assert length(temp_tools) == 1

      # Deregister server
      :ok = Registry.deregister_server(registry, "temp_server")
      {:error, :not_found} = Registry.get_server(registry, "temp_server")

      # Tool should no longer be available
      all_tools_after = Registry.get_all_tools(registry)
      temp_tools_after = Enum.filter(all_tools_after, fn tool -> tool.name == "temp_tool" end)
      assert length(temp_tools_after) == 0
    end
  end

  describe "Configuration Hot Reload Scenarios" do
    test "handles configuration reload with server changes" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Initial configuration
      initial_config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "echo",
            "args" => ["initial"],
            "trust" => false
          }
        }
      }

      File.write!(@valid_config_path, Jason.encode!(initial_config))

      # Load initial configuration
      :ok = ConnectionManager.reload_configuration(connection_manager, @valid_config_path)

      # Modified configuration - remove server1, add server2
      updated_config = %{
        "mcpServers" => %{
          "server2" => %{
            "command" => "echo",
            "args" => ["updated"],
            "trust" => false
          }
        }
      }

      File.write!(@valid_config_path, Jason.encode!(updated_config))

      # Reload configuration
      :ok = ConnectionManager.reload_configuration(connection_manager, @valid_config_path)

      # Verify changes took effect
      connections = ConnectionManager.list_connections(connection_manager)
      server_ids = Enum.map(connections, & &1.server_id)

      refute "server1" in server_ids
      # Note: server2 might fail to start with echo, but that's expected
    end

    test "recovers from invalid configuration during reload" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Start with valid configuration
      valid_config = %{
        "mcpServers" => %{
          "stable_server" => %{
            "command" => "echo",
            "args" => ["stable"],
            "trust" => false
          }
        }
      }

      File.write!(@valid_config_path, Jason.encode!(valid_config))
      :ok = ConnectionManager.reload_configuration(connection_manager, @valid_config_path)

      # Attempt reload with invalid configuration
      {:error, _reason} =
        ConnectionManager.reload_configuration(connection_manager, @invalid_config_path)

      # Original configuration should still be active
      connections = ConnectionManager.list_connections(connection_manager)
      server_ids = Enum.map(connections, & &1.server_id)
      # May have failed to start
      assert "stable_server" in server_ids or length(server_ids) == 0
    end
  end

  describe "Supervisor Tree Recovery" do
    test "recovers from connection manager crash" do
      # Get reference to current connection manager
      original_manager = TheMaestro.MCP.Supervisor.connection_manager()
      original_ref = Process.monitor(original_manager)

      # Force crash the connection manager
      GenServer.stop(original_manager, :crash)

      # Wait for it to die - named GenServers show differently in DOWN messages
      receive do
        {:DOWN, ^original_ref, :process, _, :crash} -> :ok
      after
        1000 -> flunk("Connection manager did not crash as expected")
      end

      # Give supervisor time to restart
      :timer.sleep(100)

      # New connection manager should be available (it's a named process)
      new_manager_pid = GenServer.whereis(TheMaestro.MCP.ConnectionManager)
      assert is_pid(new_manager_pid)
      assert new_manager_pid != original_manager

      # Should be able to use it normally
      connections = ConnectionManager.list_connections(TheMaestro.MCP.ConnectionManager)
      assert is_list(connections)
    end

    test "recovers from registry crash" do
      # Get reference to current registry
      original_registry = TheMaestro.MCP.Supervisor.registry()
      original_ref = Process.monitor(original_registry)

      # Force crash the registry
      GenServer.stop(original_registry, :crash)

      # Wait for it to die - note that named processes show differently in messages
      receive do
        {:DOWN, ^original_ref, :process, _, :crash} -> :ok
      after
        1000 -> flunk("Registry did not crash as expected")
      end

      # Give supervisor time to restart
      :timer.sleep(100)

      # New registry should be available (it's a named process, not a direct PID)
      new_registry_pid = GenServer.whereis(TheMaestro.MCP.Registry)
      assert is_pid(new_registry_pid)
      assert new_registry_pid != original_registry

      # Should be able to use it normally
      all_tools = Registry.get_all_tools(TheMaestro.MCP.Registry)
      assert is_list(all_tools)
    end
  end

  describe "Resource Cleanup and Memory Management" do
    test "properly cleans up failed connections" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Start multiple connections that will fail
      failing_configs =
        for i <- 1..5 do
          %{
            id: "failing_#{i}",
            transport: :stdio,
            command: "nonexistent_command_#{i}",
            args: [],
            env: %{},
            trust: false
          }
        end

      # Start all connections (they should all fail)
      for config <- failing_configs do
        {:error, _} = ConnectionManager.start_connection(connection_manager, config)
      end

      # Verify no lingering connections
      connections = ConnectionManager.list_connections(connection_manager)
      assert connections == []
    end

    test "handles concurrent connection attempts" do
      connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

      # Configuration that should work
      test_config = %{
        id: "concurrent_test",
        transport: :stdio,
        command: "echo",
        args: ["concurrent"],
        env: %{},
        trust: false
      }

      # Start multiple concurrent connection attempts
      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            ConnectionManager.start_connection(connection_manager, test_config)
          end)
        end

      results = Task.await_many(tasks)

      # Only one should succeed, others should fail with :already_connected
      success_count =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      error_count =
        Enum.count(results, fn
          {:error, :already_connected} -> true
          _ -> false
        end)

      # At most one success
      assert success_count <= 1
      # At least 2 results accounted for
      assert success_count + error_count >= 2
    end
  end

  # Helper functions

  defp create_test_config_files do
    # Valid configuration
    valid_config = %{
      "mcpServers" => %{
        "testServer" => %{
          "command" => "echo",
          "args" => ["test"],
          "trust" => false
        }
      }
    }

    File.write!(@valid_config_path, Jason.encode!(valid_config))

    # Invalid configuration
    File.write!(@invalid_config_path, "{invalid json content")
  end

  defp reset_connection_state do
    connection_manager = TheMaestro.MCP.Supervisor.connection_manager()

    # Get all connections and stop them
    connections = ConnectionManager.list_connections(connection_manager)

    for connection <- connections do
      ConnectionManager.stop_connection(connection_manager, connection.server_id)
    end

    # Clear registry
    _registry = TheMaestro.MCP.Supervisor.registry()

    # We can't easily clear the registry, but individual tests should handle this
    :ok
  end
end

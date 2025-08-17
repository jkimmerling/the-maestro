defmodule TheMaestro.MCP.ConnectionManagerTest do
  use ExUnit.Case, async: false

  alias TheMaestro.MCP.ConnectionManager
  alias TheMaestro.MCP.Connection

  setup do
    # Start the connection manager for each test
    {:ok, manager_pid} = ConnectionManager.start_link([])
    
    on_exit(fn ->
      if Process.alive?(manager_pid) do
        GenServer.stop(manager_pid)
      end
    end)
    
    %{manager: manager_pid}
  end

  describe "connection pool management" do
    test "starts and tracks server connections", %{manager: manager} do
      server_config = %{
        id: "testServer",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      assert {:ok, connection_pid} = ConnectionManager.start_connection(manager, server_config)
      assert is_pid(connection_pid)
      
      # Verify connection is tracked
      assert {:ok, tracked_connection} = ConnectionManager.get_connection(manager, "testServer")
      assert tracked_connection.server_id == "testServer"
      assert tracked_connection.connection_pid == connection_pid
    end

    test "manages connection lifecycle", %{manager: manager} do
      server_config = %{
        id: "lifecycleTest",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      # Start connection
      assert {:ok, connection_pid} = ConnectionManager.start_connection(manager, server_config)
      
      # Check initial state
      assert {:ok, connection_info} = ConnectionManager.get_connection(manager, "lifecycleTest")
      assert connection_info.status in [:connecting, :connected]
      
      # Stop connection
      assert :ok = ConnectionManager.stop_connection(manager, "lifecycleTest")
      
      # Verify connection is removed
      assert {:error, :not_found} = ConnectionManager.get_connection(manager, "lifecycleTest")
    end

    test "handles multiple concurrent connections", %{manager: manager} do
      configs = [
        %{id: "server1", transport: :stdio, command: "echo", args: ["1"]},
        %{id: "server2", transport: :stdio, command: "echo", args: ["2"]},
        %{id: "server3", transport: :stdio, command: "echo", args: ["3"]}
      ]

      # Start all connections
      connection_results = Enum.map(configs, fn config ->
        ConnectionManager.start_connection(manager, config)
      end)

      # Verify all started successfully
      assert Enum.all?(connection_results, fn result ->
        match?({:ok, _pid}, result)
      end)

      # Verify all are tracked
      connections = ConnectionManager.list_connections(manager)
      assert length(connections) == 3
      assert Enum.all?(["server1", "server2", "server3"], fn id ->
        Enum.any?(connections, fn conn -> conn.server_id == id end)
      end)
    end
  end

  describe "health monitoring" do
    test "tracks connection health status", %{manager: manager} do
      server_config = %{
        id: "healthTest",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      {:ok, _connection_pid} = ConnectionManager.start_connection(manager, server_config)
      
      # Get initial health status
      assert {:ok, health} = ConnectionManager.get_health_status(manager, "healthTest")
      assert health.server_id == "healthTest"
      assert is_integer(health.last_heartbeat)
      assert health.status in [:connecting, :connected, :error]
    end

    test "performs automatic health checks", %{manager: manager} do
      server_config = %{
        id: "healthCheckTest",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false,
        heartbeat_interval: 100  # 100ms for faster testing
      }

      {:ok, _connection_pid} = ConnectionManager.start_connection(manager, server_config)
      
      # Wait for a few heartbeats
      Process.sleep(300)
      
      # Verify heartbeat was updated
      assert {:ok, health} = ConnectionManager.get_health_status(manager, "healthCheckTest")
      initial_heartbeat = health.last_heartbeat
      
      Process.sleep(200)
      
      assert {:ok, updated_health} = ConnectionManager.get_health_status(manager, "healthCheckTest")
      assert updated_health.last_heartbeat > initial_heartbeat
    end

    test "detects and handles connection failures", %{manager: manager} do
      server_config = %{
        id: "failureTest",
        transport: :stdio,
        command: "/non/existent/command",  # This will fail
        args: [],
        env: %{},
        trust: false
      }

      # This should fail to start
      assert {:error, _reason} = ConnectionManager.start_connection(manager, server_config)
      
      # Verify no connection is tracked
      assert {:error, :not_found} = ConnectionManager.get_connection(manager, "failureTest")
    end
  end

  describe "tool discovery and registration" do
    test "discovers and registers tools from connected servers", %{manager: manager} do
      server_config = %{
        id: "toolTest",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      {:ok, _connection_pid} = ConnectionManager.start_connection(manager, server_config)
      
      # Simulate tool discovery (this would normally come from MCP protocol)
      tools = [
        %{name: "test_tool", description: "A test tool", inputSchema: %{}},
        %{name: "another_tool", description: "Another tool", inputSchema: %{}}
      ]
      
      assert :ok = ConnectionManager.register_tools(manager, "toolTest", tools)
      
      # Verify tools are registered
      assert {:ok, registered_tools} = ConnectionManager.get_server_tools(manager, "toolTest")
      assert length(registered_tools) == 2
      assert Enum.any?(registered_tools, fn tool -> tool.name == "test_tool" end)
      assert Enum.any?(registered_tools, fn tool -> tool.name == "another_tool" end)
    end

    test "handles tool namespace conflicts", %{manager: manager} do
      # Start two servers with conflicting tool names
      configs = [
        %{id: "server1", transport: :stdio, command: "echo", args: ["1"]},
        %{id: "server2", transport: :stdio, command: "echo", args: ["2"]}
      ]

      Enum.each(configs, fn config ->
        {:ok, _} = ConnectionManager.start_connection(manager, config)
      end)

      # Register same tool name on both servers
      conflicting_tool = %{name: "duplicate_tool", description: "A tool", inputSchema: %{}}
      
      :ok = ConnectionManager.register_tools(manager, "server1", [conflicting_tool])
      :ok = ConnectionManager.register_tools(manager, "server2", [conflicting_tool])
      
      # Verify namespace handling
      all_tools = ConnectionManager.get_all_tools(manager)
      
      # Should have tools with prefixed names to avoid conflicts
      tool_names = Enum.map(all_tools, & &1.name)
      assert "server1__duplicate_tool" in tool_names
      assert "server2__duplicate_tool" in tool_names
    end
  end

  describe "dynamic server management" do
    test "supports runtime server addition", %{manager: manager} do
      initial_count = length(ConnectionManager.list_connections(manager))
      
      server_config = %{
        id: "dynamicAdd",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      assert {:ok, _} = ConnectionManager.add_server(manager, server_config)
      
      new_count = length(ConnectionManager.list_connections(manager))
      assert new_count == initial_count + 1
      
      assert {:ok, _} = ConnectionManager.get_connection(manager, "dynamicAdd")
    end

    test "supports runtime server removal", %{manager: manager} do
      server_config = %{
        id: "dynamicRemove",
        transport: :stdio,
        command: "echo",
        args: ["test"],
        env: %{},
        trust: false
      }

      {:ok, _} = ConnectionManager.start_connection(manager, server_config)
      assert {:ok, _} = ConnectionManager.get_connection(manager, "dynamicRemove")
      
      assert :ok = ConnectionManager.remove_server(manager, "dynamicRemove")
      assert {:error, :not_found} = ConnectionManager.get_connection(manager, "dynamicRemove")
    end

    test "supports configuration reload", %{manager: manager} do
      # Create initial configuration
      config = %{
        "mcpServers" => %{
          "initialServer" => %{
            "command" => "echo",
            "args" => ["initial"]
          }
        }
      }
      
      config_path = create_temp_config(config)
      
      assert :ok = ConnectionManager.reload_configuration(manager, config_path)
      
      connections = ConnectionManager.list_connections(manager)
      assert length(connections) == 1
      assert Enum.any?(connections, fn conn -> conn.server_id == "initialServer" end)
      
      # Update configuration
      updated_config = %{
        "mcpServers" => %{
          "initialServer" => %{
            "command" => "echo",
            "args" => ["updated"]
          },
          "newServer" => %{
            "command" => "echo",
            "args" => ["new"]
          }
        }
      }
      
      File.write!(config_path, Jason.encode!(updated_config))
      
      assert :ok = ConnectionManager.reload_configuration(manager, config_path)
      
      updated_connections = ConnectionManager.list_connections(manager)
      assert length(updated_connections) == 2
      assert Enum.any?(updated_connections, fn conn -> conn.server_id == "newServer" end)
      
      # Cleanup
      File.rm!(config_path)
    end
  end

  describe "error handling and recovery" do
    test "implements circuit breaker pattern for failing servers", %{manager: manager} do
      server_config = %{
        id: "circuitTest",
        transport: :stdio,
        command: "/will/fail/command",
        args: [],
        env: %{},
        trust: false,
        max_failures: 3,
        failure_window: 1000
      }

      # Multiple failed attempts should trigger circuit breaker
      for _i <- 1..4 do
        {:error, _} = ConnectionManager.start_connection(manager, server_config)
      end
      
      # Circuit should be open now
      assert {:error, :circuit_open} = ConnectionManager.start_connection(manager, server_config)
    end

    test "handles graceful degradation when servers fail", %{manager: manager} do
      # Start multiple servers
      configs = [
        %{id: "stable", transport: :stdio, command: "echo", args: ["stable"]},
        %{id: "unstable", transport: :stdio, command: "echo", args: ["unstable"]}
      ]

      Enum.each(configs, fn config ->
        {:ok, _} = ConnectionManager.start_connection(manager, config)
      end)

      # Simulate one server failing
      :ok = ConnectionManager.stop_connection(manager, "unstable")
      
      # System should continue operating with remaining servers
      connections = ConnectionManager.list_connections(manager)
      assert length(connections) == 1
      assert {:ok, _} = ConnectionManager.get_connection(manager, "stable")
    end
  end

  # Helper function to create temporary config files
  defp create_temp_config(config) do
    file_path = "/tmp/test_config_#{:rand.uniform(10000)}.json"
    File.write!(file_path, Jason.encode!(config))
    file_path
  end
end
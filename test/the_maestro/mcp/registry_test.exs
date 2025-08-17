defmodule TheMaestro.MCP.RegistryTest do
  use ExUnit.Case, async: false

  alias TheMaestro.MCP.Registry, as: MCPRegistry

  setup do
    # Start the MCP registry for each test with unique name
    test_name = :"Registry_#{:rand.uniform(1_000_000)}"
    {:ok, registry_pid} = MCPRegistry.start_link(name: test_name)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    %{registry: registry_pid}
  end

  describe "server registration and tracking" do
    test "registers and tracks server connections", %{registry: registry} do
      server_info = %{
        server_id: "testServer",
        config: %{command: "echo", args: ["test"]},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      assert :ok = MCPRegistry.register_server(registry, server_info)

      assert {:ok, registered_info} = MCPRegistry.get_server(registry, "testServer")
      assert registered_info.server_id == "testServer"
      assert registered_info.status == :connected
    end

    test "updates server status", %{registry: registry} do
      server_info = %{
        server_id: "statusTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connecting,
        tools: [],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      assert :ok = MCPRegistry.update_server_status(registry, "statusTest", :connected)

      {:ok, updated_info} = MCPRegistry.get_server(registry, "statusTest")
      assert updated_info.status == :connected
    end

    test "handles server deregistration", %{registry: registry} do
      server_info = %{
        server_id: "deregisterTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)
      assert {:ok, _} = MCPRegistry.get_server(registry, "deregisterTest")

      assert :ok = MCPRegistry.deregister_server(registry, "deregisterTest")
      assert {:error, :not_found} = MCPRegistry.get_server(registry, "deregisterTest")
    end
  end

  describe "tool namespace management" do
    test "manages tool namespaces without conflicts", %{registry: registry} do
      # Register servers with tools
      server1_info = %{
        server_id: "server1",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "unique_tool"}, %{name: "common_tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      server2_info = %{
        server_id: "server2",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "another_tool"}, %{name: "common_tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server1_info)
      :ok = MCPRegistry.register_server(registry, server2_info)

      # Get all tools with namespace resolution
      all_tools = MCPRegistry.get_all_tools(registry)

      tool_names = Enum.map(all_tools, fn tool -> tool.name end)

      # Should have namespaced tools for conflicts
      assert "unique_tool" in tool_names
      assert "another_tool" in tool_names
      assert "server1__common_tool" in tool_names
      assert "server2__common_tool" in tool_names
      # Should be namespaced due to conflict
      refute "common_tool" in tool_names
    end

    test "handles tool priority resolution", %{registry: registry} do
      # Register server with higher priority
      high_priority_server = %{
        server_id: "highPriority",
        config: %{priority: 10},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "priority_tool", description: "High priority"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      low_priority_server = %{
        server_id: "lowPriority",
        config: %{priority: 1},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "priority_tool", description: "Low priority"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, low_priority_server)
      :ok = MCPRegistry.register_server(registry, high_priority_server)

      # Higher priority tool should take precedence
      {:ok, tool} = MCPRegistry.resolve_tool(registry, "priority_tool")
      assert tool.description == "High priority"
      assert tool.server_id == "highPriority"
    end

    test "provides clear tool attribution", %{registry: registry} do
      server_info = %{
        server_id: "attributionTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "attributed_tool", description: "Test tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      {:ok, tool} = MCPRegistry.resolve_tool(registry, "attributed_tool")
      assert tool.server_id == "attributionTest"
      assert tool.name == "attributed_tool"
    end
  end

  describe "load balancing and failover" do
    test "supports load balancing across multiple servers", %{registry: registry} do
      # Register multiple servers with same tool
      for i <- 1..3 do
        server_info = %{
          server_id: "loadbalance#{i}",
          config: %{},
          connection: spawn(fn -> :ok end),
          status: :connected,
          tools: [%{name: "balanced_tool"}],
          capabilities: %{},
          last_heartbeat: System.system_time(:millisecond)
        }

        :ok = MCPRegistry.register_server(registry, server_info)
      end

      # Get servers for load balancing
      servers = MCPRegistry.get_servers_for_tool(registry, "balanced_tool")
      assert length(servers) == 3

      # Verify all servers can handle the tool
      server_ids = Enum.map(servers, & &1.server_id)
      assert "loadbalance1" in server_ids
      assert "loadbalance2" in server_ids
      assert "loadbalance3" in server_ids
    end

    test "handles failover when servers become unavailable", %{registry: registry} do
      # Register primary and backup servers
      primary_server = %{
        server_id: "primary",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "failover_tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      backup_server = %{
        server_id: "backup",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "failover_tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, primary_server)
      :ok = MCPRegistry.register_server(registry, backup_server)

      # Simulate primary failure
      :ok = MCPRegistry.update_server_status(registry, "primary", :error)

      # Should failover to backup server
      available_servers = MCPRegistry.get_available_servers_for_tool(registry, "failover_tool")
      assert length(available_servers) == 1
      assert hd(available_servers).server_id == "backup"
    end
  end

  describe "metrics and monitoring" do
    test "tracks connection uptime and statistics", %{registry: registry} do
      start_time = System.system_time(:millisecond)

      server_info = %{
        server_id: "metricsTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [],
        capabilities: %{},
        last_heartbeat: start_time
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      # Wait a bit and update heartbeat
      Process.sleep(100)
      new_heartbeat = System.system_time(:millisecond)
      :ok = MCPRegistry.update_heartbeat(registry, "metricsTest", new_heartbeat)

      metrics = MCPRegistry.get_server_metrics(registry, "metricsTest")
      assert metrics.uptime > 0
      assert metrics.last_heartbeat == new_heartbeat
      assert metrics.status == :connected
    end

    test "collects error rates and performance data", %{registry: registry} do
      server_info = %{
        server_id: "performanceTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      # Record some operations
      :ok = MCPRegistry.record_operation(registry, "performanceTest", :success, 100)
      :ok = MCPRegistry.record_operation(registry, "performanceTest", :success, 150)
      :ok = MCPRegistry.record_operation(registry, "performanceTest", :error, 50)

      metrics = MCPRegistry.get_server_metrics(registry, "performanceTest")
      assert metrics.total_operations == 3
      assert metrics.error_rate > 0
      assert metrics.avg_latency > 0
    end
  end

  describe "event broadcasting" do
    test "broadcasts server status changes", %{registry: registry} do
      # Subscribe to registry events
      :ok = MCPRegistry.subscribe_to_events(registry)

      server_info = %{
        server_id: "eventTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connecting,
        tools: [],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      # Should receive registration event
      assert_receive {:mcp_registry_event, {:server_registered, "eventTest"}}, 1000

      # Update status
      :ok = MCPRegistry.update_server_status(registry, "eventTest", :connected)

      # Should receive status change event
      assert_receive {:mcp_registry_event, {:server_status_changed, "eventTest", :connected}},
                     1000
    end

    test "broadcasts tool availability changes", %{registry: registry} do
      :ok = MCPRegistry.subscribe_to_events(registry)

      server_info = %{
        server_id: "toolEventTest",
        config: %{},
        connection: spawn(fn -> :ok end),
        status: :connected,
        tools: [%{name: "new_tool"}],
        capabilities: %{},
        last_heartbeat: System.system_time(:millisecond)
      }

      :ok = MCPRegistry.register_server(registry, server_info)

      # Should receive tool availability event
      assert_receive {:mcp_registry_event, {:tools_updated, "toolEventTest", _tools}}, 1000
    end
  end
end

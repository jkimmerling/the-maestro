defmodule TheMaestro.MCP.Tools.RegistryTest do
  use ExUnit.Case, async: true
  doctest TheMaestro.MCP.Tools.Registry

  alias TheMaestro.MCP.Tools.Registry

  # Mock MCP tool definitions
  @mock_read_file_tool %{
    "name" => "read_file",
    "description" => "Read contents of a file",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path to read"}
      },
      "required" => ["path"]
    }
  }

  @mock_write_file_tool %{
    "name" => "write_file",
    "description" => "Write content to a file",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path to write"},
        "content" => %{"type" => "string", "description" => "Content to write"}
      },
      "required" => ["path", "content"]
    }
  }

  @mock_conflicting_tool %{
    "name" => "read_file",
    "description" => "Another read file tool",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{
        "file" => %{"type" => "string", "description" => "File to read"}
      },
      "required" => ["file"]
    }
  }

  setup do
    # Start a fresh registry for each test
    {:ok, registry} = Registry.start_link(name: :"test_registry_#{:rand.uniform(10000)}")
    {:ok, registry: registry}
  end

  describe "start_link/1" do
    test "starts the registry GenServer" do
      assert {:ok, pid} = Registry.start_link(name: :test_registry)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts custom name" do
      assert {:ok, pid} = Registry.start_link(name: :custom_registry)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "register_tools/3" do
    test "registers tools from a server", %{registry: registry} do
      tools = [@mock_read_file_tool, @mock_write_file_tool]
      assert :ok = Registry.register_tools(registry, "filesystem_server", tools)

      {:ok, server_tools} = Registry.get_server_tools(registry, "filesystem_server")
      assert length(server_tools) == 2
      assert Enum.any?(server_tools, &(&1.name == "read_file"))
      assert Enum.any?(server_tools, &(&1.name == "write_file"))
    end

    test "validates tool schemas", %{registry: registry} do
      invalid_tool = %{"name" => "invalid", "inputSchema" => "not_a_map"}

      assert {:error, :invalid_schema} =
               Registry.register_tools(registry, "test_server", [invalid_tool])
    end

    test "handles empty tool list", %{registry: registry} do
      assert :ok = Registry.register_tools(registry, "empty_server", [])

      {:ok, tools} = Registry.get_server_tools(registry, "empty_server")
      assert tools == []
    end

    test "overwrites previous tools for same server", %{registry: registry} do
      # Register initial tools
      tools1 = [@mock_read_file_tool]
      assert :ok = Registry.register_tools(registry, "test_server", tools1)

      # Register new tools
      tools2 = [@mock_write_file_tool]
      assert :ok = Registry.register_tools(registry, "test_server", tools2)

      {:ok, server_tools} = Registry.get_server_tools(registry, "test_server")
      assert length(server_tools) == 1
      assert List.first(server_tools).name == "write_file"
    end
  end

  describe "get_server_tools/2" do
    test "returns tools for existing server", %{registry: registry} do
      tools = [@mock_read_file_tool]
      Registry.register_tools(registry, "test_server", tools)

      assert {:ok, server_tools} = Registry.get_server_tools(registry, "test_server")
      assert length(server_tools) == 1
      assert List.first(server_tools).name == "read_file"
    end

    test "returns error for non-existent server", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_server_tools(registry, "nonexistent")
    end
  end

  describe "get_all_tools/1" do
    test "returns all tools from all servers", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])
      Registry.register_tools(registry, "server2", [@mock_write_file_tool])

      all_tools = Registry.get_all_tools(registry)
      assert length(all_tools) == 2

      tool_names = Enum.map(all_tools, & &1.name)
      assert "read_file" in tool_names
      assert "write_file" in tool_names
    end

    test "handles name conflicts with prefixing", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])
      Registry.register_tools(registry, "server2", [@mock_conflicting_tool])

      all_tools = Registry.get_all_tools(registry)
      assert length(all_tools) == 2

      tool_names = Enum.map(all_tools, & &1.name)
      assert "server1__read_file" in tool_names
      assert "server2__read_file" in tool_names
    end

    test "returns empty list when no tools registered", %{registry: registry} do
      assert Registry.get_all_tools(registry) == []
    end
  end

  describe "find_tool/2" do
    test "finds tool by name", %{registry: registry} do
      Registry.register_tools(registry, "test_server", [@mock_read_file_tool])

      assert {:ok, tool_meta} = Registry.find_tool(registry, "read_file")
      assert tool_meta.tool.name == "read_file"
      assert tool_meta.server_id == "test_server"
    end

    test "finds tool by prefixed name", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])
      Registry.register_tools(registry, "server2", [@mock_conflicting_tool])

      assert {:ok, tool_meta} = Registry.find_tool(registry, "server1__read_file")
      assert tool_meta.tool.name == "server1__read_file"
      assert tool_meta.server_id == "server1"
    end

    test "returns error for non-existent tool", %{registry: registry} do
      assert {:error, :not_found} = Registry.find_tool(registry, "nonexistent")
    end
  end

  describe "unregister_server/2" do
    test "removes all tools for a server", %{registry: registry} do
      Registry.register_tools(registry, "test_server", [@mock_read_file_tool])
      Registry.register_tools(registry, "other_server", [@mock_write_file_tool])

      assert :ok = Registry.unregister_server(registry, "test_server")

      assert {:error, :not_found} = Registry.get_server_tools(registry, "test_server")
      assert {:ok, _} = Registry.get_server_tools(registry, "other_server")
    end

    test "handles non-existent server gracefully", %{registry: registry} do
      assert :ok = Registry.unregister_server(registry, "nonexistent")
    end
  end

  describe "list_servers/1" do
    test "returns list of registered server IDs", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])
      Registry.register_tools(registry, "server2", [@mock_write_file_tool])

      servers = Registry.list_servers(registry)
      assert length(servers) == 2
      assert "server1" in servers
      assert "server2" in servers
    end

    test "returns empty list when no servers registered", %{registry: registry} do
      assert Registry.list_servers(registry) == []
    end
  end

  describe "tool_count/1" do
    test "returns total number of tools", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])

      Registry.register_tools(registry, "server2", [@mock_write_file_tool, @mock_conflicting_tool])

      assert Registry.tool_count(registry) == 3
    end

    test "returns 0 when no tools registered", %{registry: registry} do
      assert Registry.tool_count(registry) == 0
    end
  end

  describe "get_tool_metadata/2" do
    test "returns tool metadata", %{registry: registry} do
      Registry.register_tools(registry, "test_server", [@mock_read_file_tool])

      assert {:ok, metadata} = Registry.get_tool_metadata(registry, "read_file")
      assert metadata.tool_name == "read_file"
      assert metadata.server_id == "test_server"
      assert metadata.original_name == "read_file"
      assert is_nil(metadata.prefixed_name)
    end

    test "returns metadata for prefixed tools", %{registry: registry} do
      Registry.register_tools(registry, "server1", [@mock_read_file_tool])
      Registry.register_tools(registry, "server2", [@mock_conflicting_tool])

      assert {:ok, metadata} = Registry.get_tool_metadata(registry, "server1__read_file")
      assert metadata.tool_name == "server1__read_file"
      assert metadata.server_id == "server1"
      assert metadata.original_name == "read_file"
      assert metadata.prefixed_name == "server1__read_file"
    end
  end
end

defmodule TheMaestro.MCP.ConnectionTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Connection

  describe "new/2" do
    test "creates connection with transport and state" do
      transport_pid = spawn(fn -> :ok end)
      
      connection = Connection.new(transport_pid, :connecting)

      assert connection.transport == transport_pid
      assert connection.state == :connecting
      assert connection.server_info == nil
      assert connection.capabilities == %{}
      assert connection.tools == []
    end
  end

  describe "update_state/2" do
    test "updates connection state" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connecting)

      updated = Connection.update_state(connection, :connected)

      assert updated.state == :connected
      assert updated.transport == transport_pid
    end
  end

  describe "set_server_info/2" do
    test "sets server information" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connecting)
      
      server_info = %{
        name: "test_server",
        version: "1.0.0",
        protocol_version: "2024-11-05"
      }

      updated = Connection.set_server_info(connection, server_info)

      assert updated.server_info == server_info
    end
  end

  describe "set_capabilities/2" do
    test "sets server capabilities" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connecting)
      
      capabilities = %{
        tools: %{listChanged: true},
        resources: %{subscribe: true}
      }

      updated = Connection.set_capabilities(connection, capabilities)

      assert updated.capabilities == capabilities
    end
  end

  describe "add_tool/2" do
    test "adds tool to connection" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connected)
      
      tool = %{
        name: "test_tool",
        description: "A test tool",
        inputSchema: %{
          type: "object",
          properties: %{
            param1: %{type: "string"}
          }
        }
      }

      updated = Connection.add_tool(connection, tool)

      assert length(updated.tools) == 1
      assert hd(updated.tools) == tool
    end

    test "prevents duplicate tools" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connected)
      
      tool = %{name: "test_tool", description: "A test tool"}

      updated = connection
                |> Connection.add_tool(tool)
                |> Connection.add_tool(tool)

      assert length(updated.tools) == 1
    end
  end

  describe "remove_tool/2" do
    test "removes tool from connection" do
      transport_pid = spawn(fn -> :ok end)
      tool = %{name: "test_tool", description: "A test tool"}
      
      connection = Connection.new(transport_pid, :connected)
                  |> Connection.add_tool(tool)

      updated = Connection.remove_tool(connection, "test_tool")

      assert updated.tools == []
    end

    test "handles removing non-existent tool" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connected)

      updated = Connection.remove_tool(connection, "nonexistent")

      assert updated.tools == []
    end
  end

  describe "get_tool/2" do
    test "finds tool by name" do
      transport_pid = spawn(fn -> :ok end)
      tool = %{name: "test_tool", description: "A test tool"}
      
      connection = Connection.new(transport_pid, :connected)
                  |> Connection.add_tool(tool)

      assert {:ok, found_tool} = Connection.get_tool(connection, "test_tool")
      assert found_tool == tool
    end

    test "returns error for non-existent tool" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connected)

      assert {:error, :not_found} = Connection.get_tool(connection, "nonexistent")
    end
  end

  describe "connected?/1" do
    test "returns true for connected state" do
      transport_pid = spawn(fn -> :ok end)
      connection = Connection.new(transport_pid, :connected)

      assert Connection.connected?(connection)
    end

    test "returns false for other states" do
      transport_pid = spawn(fn -> :ok end)
      
      for state <- [:disconnected, :connecting, :error] do
        connection = Connection.new(transport_pid, state)
        refute Connection.connected?(connection)
      end
    end
  end
end
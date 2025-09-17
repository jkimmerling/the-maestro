defmodule TheMaestro.MCPTest do
  use TheMaestro.DataCase

  import TheMaestro.MCPFixtures
  import TheMaestro.ConversationsFixtures

  alias TheMaestro.MCP
  alias TheMaestro.MCP.{Servers, SessionServer}

  describe "list_servers/1" do
    test "excludes disabled servers by default and sorts case-insensitively" do
      {:ok, enabled_a} =
        MCP.create_server(%{
          name: "alpha",
          display_name: "Alpha",
          transport: "stdio",
          command: "bin/run",
          is_enabled: true
        })

      {:ok, enabled_b} =
        MCP.create_server(%{
          name: "bravo",
          display_name: "bravo",
          transport: "stream-http",
          url: "https://example.com",
          is_enabled: true
        })

      {:ok, disabled} =
        MCP.create_server(%{
          name: "charlie",
          display_name: "Charlie",
          is_enabled: false,
          transport: "stdio",
          command: "run"
        })

      assert MCP.list_servers() |> Enum.map(& &1.id) == [enabled_a.id, enabled_b.id]

      assert MCP.list_servers(include_disabled?: true) |> Enum.map(& &1.id) ==
               [enabled_a.id, enabled_b.id, disabled.id]
    end
  end

  describe "list_servers_with_stats/0" do
    test "returns aggregated session counts" do
      server = server_fixture()
      session = session_fixture()

      {:ok, _updated} = MCP.replace_session_servers(session, [server.id])

      [with_stats] = MCP.list_servers_with_stats()
      assert with_stats.session_count == 1
    end
  end

  describe "get_server!/2" do
    test "supports preloading join bindings" do
      server = server_fixture()
      session = session_fixture()
      {:ok, reloaded_session} = MCP.replace_session_servers(session, [server.id])
      bindings = reloaded_session.session_mcp_servers

      reloaded = MCP.get_server!(server.id, preload: [:session_servers])
      assert length(reloaded.session_servers) == 1
      assert hd(bindings).mcp_server_id == hd(reloaded.session_servers).mcp_server_id
    end
  end

  describe "create/update/delete" do
    test "normalizes name, transport, and args" do
      {:ok, server} =
        MCP.create_server(%{
          name: "My Server",
          display_name: "My Server",
          transport: "http",
          url: "https://example.com/api",
          args: ["", " --foo "]
        })

      assert server.name == "my-server"
      assert server.transport == "stream-http"
      assert server.args == ["--foo"]

      {:ok, updated} = MCP.update_server(server, %{transport: "stdio", command: " ./run "})
      assert updated.transport == "stdio"
      assert updated.command == "./run"
    end

    test "delete_server/1 removes the row" do
      server = server_fixture()
      assert {:ok, %Servers{}} = MCP.delete_server(server)
      assert_raise Ecto.NoResultsError, fn -> MCP.get_server!(server.id) end
    end
  end

  describe "ensure_servers_exist/1" do
    test "bulk upserts new servers" do
      attrs = [
        %{
          name: "bulk-one",
          display_name: "Bulk One",
          transport: "stdio",
          command: "bin/run"
        },
        %{
          name: "bulk-two",
          display_name: "Bulk Two",
          transport: "stream-http",
          url: "https://run"
        }
      ]

      assert {:ok, [one, two]} = MCP.ensure_servers_exist(attrs)
      assert Enum.map([one, two], & &1.name) == ["bulk-one", "bulk-two"]

      updated_attrs =
        attrs
        |> List.update_at(0, &Map.put(&1, :display_name, "Bulk One v2"))

      assert {:ok, [updated_one, updated_two]} = MCP.ensure_servers_exist(updated_attrs)
      assert updated_one.display_name == "Bulk One v2"
      assert updated_two.name == "bulk-two"
    end

    test "returns changeset error when invalid" do
      assert {:error, changeset} = MCP.ensure_servers_exist([%{name: nil}])
      refute changeset.valid?
    end
  end

  describe "replace_session_servers/2" do
    test "syncs join table and returns session" do
      first = server_fixture()
      second = server_fixture(%{name: "another"})
      session = session_fixture()

      {:ok, session} = MCP.replace_session_servers(session, [first.id])
      assert Enum.map(session.mcp_servers, & &1.id) == [first.id]

      {:ok, session} = MCP.replace_session_servers(session, [first.id, second.id])

      assert Enum.map(session.mcp_servers, & &1.id) |> Enum.sort() ==
               Enum.sort([first.id, second.id])
    end

    test "rejects unknown ids" do
      session = session_fixture()

      assert {:error, :unknown_server} =
               MCP.replace_session_servers(session, [Ecto.UUID.generate()])
    end
  end

  describe "session_connector_map/1" do
    test "returns map keyed by alias or name" do
      server = server_fixture(%{name: "alias-target", display_name: "Alias Target"})
      session = session_fixture()

      {:ok, _session} = MCP.replace_session_servers(session, [server.id])
      connector_map = MCP.session_connector_map(session)

      assert connector_map["alias-target"]["display_name"] == "Alias Target"
    end
  end

  describe "list_session_servers/1" do
    test "orders by inserted_at" do
      first = server_fixture(%{name: "order-a"})
      second = server_fixture(%{name: "order-b"})
      session = session_fixture()

      {:ok, _session} = MCP.replace_session_servers(session, [first.id])
      Process.sleep(1100)
      {:ok, _session} = MCP.replace_session_servers(session, [first.id, second.id])

      bindings = MCP.list_session_servers(session.id)
      assert Enum.map(bindings, & &1.mcp_server.name) == ["order-a", "order-b"]
    end
  end

  describe "SessionServer schema" do
    test "defaults alias to nil and metadata to empty map" do
      server = server_fixture()
      session = session_fixture()

      {:ok, _session} = MCP.replace_session_servers(session, [server.id])
      [binding] = Repo.all(SessionServer)

      assert binding.alias == nil
      assert binding.metadata == %{}
    end
  end
end

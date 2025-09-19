defmodule TheMaestroWeb.MCPToolsPickerInModalsTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  import TheMaestro.MCPFixtures

  alias TheMaestro.MCP.ToolsCache

  test "create modal shows MCP tools beside server picker from cache", %{conn: conn} do
    _session = session_fixture()
    server = server_fixture(%{metadata: %{"tool_cache_ttl_minutes" => 60}})

    # Prepopulate cache for the server with one tool
    ToolsCache.put(
      server.id,
      [%{"name" => "context7:get-library-docs", "title" => "Fetch docs"}],
      60 * 60_000
    )

    {:ok, view, _} = live(conn, ~p"/dashboard")
    view |> element("button[phx-click='open_session_modal']") |> render_click()
    assert has_element?(view, "#session-modal")

    # Select server in multiselect
    html1 =
      render_change(view, "session_validate", %{
        "_target" => ["session", "mcp_server_ids"],
        "session" => %{"mcp_server_ids" => [server.id]}
      })

    assert html1 =~ "tool-group-openai-mcp-mcp"
  end

  test "edit modal shows MCP tools beside server picker from cache", %{conn: conn} do
    s = session_fixture()
    server = server_fixture(%{metadata: %{"tool_cache_ttl_minutes" => 60}})

    ToolsCache.put(server.id, [%{"name" => "run_task", "title" => "Run task"}], 60 * 60_000)

    {:ok, view, _} = live(conn, ~p"/sessions/#{s.id}/chat")
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    html1 =
      render_change(view, "validate_config", %{
        "mcp_server_ids" => [server.id]
      })

    assert html1 =~ "tool-group-openai-mcp-mcp"
  end
end

defmodule TheMaestroWeb.SessionMCPServerToggleTest do
  use TheMaestroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  alias TheMaestro.{Conversations, MCP}

  setup do
    s = session_fixture(%{working_dir: "."})
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)

    # Create a fake MCP server and pre-warm its tools cache
    {:ok, server} =
      MCP.create_server(%{
        name: "ctx7",
        display_name: "Context7",
        transport: "stdio",
        command: "echo",
        args: [],
        is_enabled: true
      })

    tools = [
      %{"name" => "resolve-library-id", "description" => "Resolve", "inputSchema" => %{}},
      %{"name" => "get-library-docs", "description" => "Docs", "inputSchema" => %{}}
    ]

    # Warm the cache so list_for_provider_with_servers will surface items without discover
    :ok = TheMaestro.MCP.ToolsCache.put(server.id, tools, 60_000)

    %{session: s, server: server}
  end

  test "toggling server checkbox adds and removes MCP tools", %{conn: conn, session: s, server: server} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")

    # Open config
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    # Initially, no MCP tools
    html0 = render(view)
    assert html0 =~ "MCP TOOLS"

    # Toggle server on
    view |> element("#mcp-server-#{server.id} input[type=checkbox]") |> render_click()

    # After toggle, tools should appear (sanitized names include hyphens/underscores)
    assert has_element?(view, "#tool-openai-resolve-library-id-mcp")
    assert has_element?(view, "#tool-openai-get-library-docs-mcp")

    # Toggle server off
    view |> element("#mcp-server-#{server.id} input[type=checkbox]") |> render_click()
    html_after = render(view)
    refute html_after =~ ~r/id=\"tool-openai-resolve-library-id-mcp\"/
    refute html_after =~ ~r/id=\"tool-openai-get-library-docs-mcp\"/
  end
end

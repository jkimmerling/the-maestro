defmodule TheMaestroWeb.SessionChatLiveMCPToolsRenderTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  alias TheMaestro.Conversations

  setup do
    s = session_fixture()
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "config modal renders without error when registry-only tools exist (no servers)", %{
    conn: conn,
    session: s
  } do
    # Seed session.tools.mcp_registry.tools with a simple tool entry
    tool = %{
      "name" => "resolve-library-id",
      "description" => "Resolve a library id",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }

    {:ok, _} =
      Conversations.update_session(s, %{
        tools: %{"mcp_registry" => %{"tools" => [tool]}}
      })

    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")

    # Open config
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    # Modal renders and MCP Servers section is present; no separate MCP tools list
    html = render(view)
    assert html =~ ">MCPs<"
    assert html =~ ~r/id=\"mcp-server-checkboxes\"/
    assert html =~ "No MCP servers configured"
  end
end

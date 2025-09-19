defmodule TheMaestroWeb.SessionToolPickerScopingTest do
  use TheMaestroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  alias TheMaestro.{Conversations, MCP}

  setup do
    s = session_fixture(%{working_dir: "."})
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)

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

    :ok = TheMaestro.MCP.ToolsCache.put(server.id, tools, 60_000)

    %{session: s, server: server}
  end

  test "All/None buttons only affect the visible group", %{conn: conn, session: s, server: server} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{s.id}/chat")
    view |> element("button", "Config") |> render_click()

    # Turn on one MCP server so the right column has tools
    view |> element("#mcp-server-#{server.id} input[type=checkbox]") |> render_click()

    # Sanity: MCP tool checkboxes are present and checked
    assert has_element?(view, "#tool-openai-resolve-library-id-mcp input[checked]")
    assert has_element?(view, "#tool-openai-get-library-docs-mcp input[checked]")

    # Click None in left (builtin) picker; should not uncheck MCP tools
    view |> element("#tool-picker-openai button[phx-click='tool_picker:select_none']") |> render_click()
    assert has_element?(view, "#tool-openai-resolve-library-id-mcp input[checked]")
    assert has_element?(view, "#tool-openai-get-library-docs-mcp input[checked]")

    # Click All in left picker (no-op for MCP)
    view |> element("#tool-picker-openai button[phx-click='tool_picker:select_all']") |> render_click()
    assert has_element?(view, "#tool-openai-resolve-library-id-mcp input[checked]")
    assert has_element?(view, "#tool-openai-get-library-docs-mcp input[checked]")

    # Now click None in right (MCP) picker; should not uncheck builtins
    view |> element("#tool-picker-openai-mcp button[phx-click='tool_picker:select_none']") |> render_click()

    # Builtin tool checkboxes should remain checked (shell/apply_patch)
    assert has_element?(view, "#tool-openai-shell input[checked]")
    assert has_element?(view, "#tool-openai-apply_patch input[checked]")
  end
end

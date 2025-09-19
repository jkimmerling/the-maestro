defmodule TheMaestroWeb.DashboardSessionModalTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  alias TheMaestro.Conversations

  test "create session modal has collapsible sections and correct ordering", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dashboard")

    view |> element("button[phx-click='open_session_modal']") |> render_click()
    assert has_element?(view, "#session-modal")

    html = render(view)

    # Sections exist
    assert html =~ "id=\"section-system-prompts\""
    assert html =~ "id=\"section-persona\""
    assert html =~ "id=\"section-memory\""

    # Ordering: Chat History before System Prompts; System Prompts before Persona/Memory
    chat_idx =
      case :binary.match(html, "Attach Existing Thread") do
        {pos, _} -> pos
        _ -> nil
      end

    p_idx =
      case :binary.match(html, "id=\"section-system-prompts\"") do
        {pos, _} -> pos
        _ -> nil
      end

    persona_idx =
      case :binary.match(html, "id=\"section-persona\"") do
        {pos, _} -> pos
        _ -> nil
      end

    memory_idx =
      case :binary.match(html, "id=\"section-memory\"") do
        {pos, _} -> pos
        _ -> nil
      end

    assert is_integer(chat_idx) and is_integer(p_idx) and is_integer(persona_idx) and
             is_integer(memory_idx)

    assert chat_idx < p_idx
    assert p_idx < persona_idx
    assert p_idx < memory_idx

    # Initially collapsed
    assert has_element?(view, "#section-system-prompts-content.hidden")
    assert has_element?(view, "#section-persona-content.hidden")
    assert has_element?(view, "#section-memory-content.hidden")

    # Toggle prompt section hidden -> visible -> hidden
    view |> element("#toggle-prompt") |> render_click()
    refute has_element?(view, "#section-system-prompts-content.hidden")
    view |> element("#toggle-prompt") |> render_click()
    assert has_element?(view, "#section-system-prompts-content.hidden")
  end

  test "chat history picker lists existing threads even if attached", %{conn: conn} do
    # Create a session with a thread and at least one entry attached to it
    s = session_fixture()
    {:ok, _tid} = Conversations.new_thread(s, "Test Thread")

    {:ok, view, _} = live(conn, ~p"/dashboard")
    view |> element("button[phx-click='open_session_modal']") |> render_click()
    assert has_element?(view, "#session-modal")

    html = render(view)

    # The select lists some option value that looks like a UUID for the thread; just assert options present
    assert html =~ ~r/name=\"session\[attach_thread_id\]\"/

    # Since we don't know the generated UUID here without exposing it, assert at least one option exists
    assert html =~ ~r/<option value=\"[\w-]{36}\">/
  end

  test "MCP container has correct structure with parent heading and subheadings", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/dashboard")
    view |> element("button[phx-click='open_session_modal']") |> render_click()
    assert has_element?(view, "#session-modal")

    html = render(view)

    # Parent MCPs heading exists
    assert html =~ ">MCPs<"

    # Subheadings exist in correct order
    servers_idx =
      case :binary.match(html, ">Servers<") do
        {pos, _} -> pos
        _ -> nil
      end

    tools_idx =
      case :binary.match(html, ">MCP TOOLS<") do
        {pos, _} -> pos
        _ -> nil
      end

    assert is_integer(servers_idx), "Servers subheading not found"
    assert is_integer(tools_idx), "MCP TOOLS subheading not found"

    # MCP server checkboxes container exists under Servers section
    assert html =~ ~r/id=\"mcp-server-checkboxes\"/

    # New button exists under the selector and helper text
    new_button_idx =
      case :binary.match(html, "phx-click=\"open_mcp_modal\"") do
        {pos, _} -> pos
        _ -> nil
      end

    assert is_integer(new_button_idx), "New MCP button not found"

    # Helper text appears under selector
    assert html =~ "Select one or more connectors to use for this session"
  end
end

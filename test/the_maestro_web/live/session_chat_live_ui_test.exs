defmodule TheMaestroWeb.SessionChatLiveUITest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias TheMaestro.Conversations
  import TheMaestro.ConversationsFixtures

  setup do
    s = session_fixture()
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "shows config modal and validates provider filter", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")

    assert has_element?(view, "button", "Config")
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    # Switch provider; ensures auth select re-renders (options presence)
    render_change(view, "validate_config", %{provider: "openai"})
    assert has_element?(view, "select[name=auth_id]")

    # Prompt picker defaults collapsed; expand and assert
    view |> element("#toggle-prompt") |> render_click()
    assert has_element?(view, "#session-config-prompt-picker")
  end

  test "new and clear chat buttons exist", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{s.id}/chat")
    assert has_element?(view, "button", "Start New Chat")
    assert has_element?(view, "button", "Clear Chat")

    # Start new chat should update summary area eventually (no crash)
    html = render_click(element(view, "button", "Start New Chat"))
    assert html =~ "Started new chat thread"
  end
end

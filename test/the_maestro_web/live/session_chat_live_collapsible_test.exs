defmodule TheMaestroWeb.SessionChatLiveCollapsibleTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures
  alias TheMaestro.Conversations

  setup do
    s = session_fixture()
    {:ok, {s, _}} = Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "collapsible sections survive provider switch", %{conn: conn, session: s} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{s.id}/chat")

    # Open config
    view |> element("button", "Config") |> render_click()
    assert has_element?(view, "#session-config-modal")

    # Expand prompts, assert visible
    view |> element("#toggle-prompt") |> render_click()
    assert has_element?(view, "#section-system-prompts-content")

    # Switch provider to anthropic, prompt content should still be togglable
    render_change(view, "validate_config", %{provider: "anthropic"})

    # Toggle again: collapse, then expand
    view |> element("#toggle-prompt") |> render_click()
    html3 = render(view)
    assert html3 =~ ~r/id=\"section-system-prompts-content\"[^>]*class=\"[^"]*hidden/
    view |> element("#toggle-prompt") |> render_click()
    html4 = render(view)
    refute html4 =~ ~r/id=\"section-system-prompts-content\"[^>]*class=\"[^"]*hidden/
  end
end

defmodule TheMaestroWeb.ChatEntryLiveIndexTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  alias TheMaestro.Conversations
  import TheMaestro.ConversationsFixtures

  describe "detached entries" do
    test "attaches orphan entry to session from index", %{conn: conn} do
      session = session_fixture(%{working_dir: "."})

      {:ok, entry} =
        Conversations.create_chat_entry(%{
          session_id: nil,
          turn_index: 0,
          actor: "system",
          combined_chat: %{"messages" => []}
        })

      {:ok, view, _html} = live(conn, ~p"/chat_history")

      assert render_submit(element(view, "#chat-history-orphans form[phx-submit=attach]"), %{
               "session_id" => session.id
             }) =~ "Attached to session"

      assert Conversations.get_chat_entry!(entry.id).session_id == session.id
    end

    test "requires a session selection before attaching", %{conn: conn} do
      _session = session_fixture(%{working_dir: "."})

      {:ok, _entry} =
        Conversations.create_chat_entry(%{
          session_id: nil,
          turn_index: 0,
          actor: "system",
          combined_chat: %{"messages" => []}
        })

      {:ok, view, _html} = live(conn, ~p"/chat_history")

      assert render_submit(element(view, "#chat-history-orphans form[phx-submit=attach]"), %{}) =~
               "Select a session before attaching"
    end

    test "shows empty state when there are no detached entries", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/chat_history")
      assert html =~ "No detached chat entries found"
    end
  end

  test "lists sessions with chat history summaries", %{conn: conn} do
    session = session_fixture(%{name: "Kernel Panic"})

    {:ok, _} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: 0,
        actor: "user",
        combined_chat: %{"messages" => []}
      })

    {:ok, _} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: 1,
        actor: "assistant",
        combined_chat: %{"messages" => []}
      })

    {:ok, view, _html} = live(conn, ~p"/chat_history")

    assert has_element?(view, "#chat-history-sessions td", "Kernel Panic")
    assert has_element?(view, "#chat-history-sessions span.badge", "2")
  end
end

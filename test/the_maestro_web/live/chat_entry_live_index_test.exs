defmodule TheMaestroWeb.ChatEntryLiveIndexTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  alias TheMaestro.Conversations
  import TheMaestro.ConversationsFixtures

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

    assert render_submit(element(view, "#chat_history form[phx-submit=attach]"), %{id: entry.id, session_id: session.id}) =~ "Attached to session"
    assert Conversations.get_chat_entry!(entry.id).session_id == session.id
  end
end

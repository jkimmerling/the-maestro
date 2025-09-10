defmodule TheMaestro.Conversations.DeleteSessionPreserveChatTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.Conversations
  import TheMaestro.ConversationsFixtures

  test "delete_session_only preserves chat entries and nilifies session_id" do
    session = session_fixture(%{working_dir: ".", model_id: "gpt-5"})

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: 0,
        actor: "system",
        combined_chat: %{"messages" => []}
      })

    :ok = Conversations.delete_session_only(session) |> then(fn _ -> :ok end)

    # Entry still exists and session_id is nil
    got = Conversations.get_chat_entry!(entry.id)
    assert got.session_id == nil
  end
end

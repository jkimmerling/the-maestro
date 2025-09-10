defmodule TheMaestro.Conversations.AttachThreadTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.Conversations
  import TheMaestro.ConversationsFixtures

  test "attach_thread_to_session updates all entries in thread" do
    session = session_fixture(%{working_dir: "."})

    tid = Ecto.UUID.generate()

    {:ok, a} =
      Conversations.create_chat_entry(%{
        session_id: nil,
        turn_index: 0,
        actor: "system",
        thread_id: tid,
        combined_chat: %{"messages" => []}
      })

    {:ok, b} =
      Conversations.create_chat_entry(%{
        session_id: nil,
        turn_index: 1,
        actor: "assistant",
        thread_id: tid,
        combined_chat: %{"messages" => []}
      })

    {:ok, _count} = Conversations.attach_thread_to_session(tid, session.id)

    assert Conversations.get_chat_entry!(a.id).session_id == session.id
    assert Conversations.get_chat_entry!(b.id).session_id == session.id
  end
end

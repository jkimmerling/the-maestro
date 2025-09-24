defmodule TheMaestroWeb.ApiThreadsControllerTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "POST /api/threads/:thread_id/clear deletes entries", %{conn: conn} do
    s = session_fixture()
    {:ok, tid} = TheMaestro.Conversations.new_thread(s)

    {:ok, _} =
      TheMaestro.Conversations.create_chat_entry(%{
        session_id: s.id,
        thread_id: tid,
        turn_index: TheMaestro.Conversations.next_turn_index(s.id),
        actor: "user",
        provider: nil,
        request_headers: %{},
        response_headers: %{},
        combined_chat: %{"messages" => [%{"role" => "user", "content" => [%{"type" => "text", "text" => "hi"}]}]},
        edit_version: 0
      })

    # Sanity: next turn index for thread is now >= 1
    assert TheMaestro.Conversations.next_turn_index_for_thread(tid) >= 1

    _resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/threads/#{tid}/clear")
      |> json_response(200)

    # After clear, next index resets to 0
    assert TheMaestro.Conversations.next_turn_index_for_thread(tid) == 0
  end
end

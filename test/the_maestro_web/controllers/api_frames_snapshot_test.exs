defmodule TheMaestroWeb.ApiFramesSnapshotTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "GET /api/threads/:thread_id/snapshot returns messages", %{conn: conn} do
    s = session_fixture()
    {:ok, tid} = TheMaestro.Chat.new_thread(s.id, "Alpha")

    {:ok, _} =
      TheMaestro.Conversations.create_chat_entry(%{
        session_id: s.id,
        thread_id: tid,
        turn_index: TheMaestro.Conversations.next_turn_index(s.id),
        actor: "user",
        provider: nil,
        request_headers: %{},
        response_headers: %{},
        combined_chat: %{
          "messages" => [%{"role" => "user", "content" => [%{"type" => "text", "text" => "hi"}]}]
        },
        edit_version: 0
      })

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/threads/#{tid}/snapshot")
      |> json_response(200)

    assert is_list(resp["messages"]) and length(resp["messages"]) >= 1
    assert Enum.any?(resp["messages"], &(&1["role"] in ["user", "assistant", "system"]))
  end
end

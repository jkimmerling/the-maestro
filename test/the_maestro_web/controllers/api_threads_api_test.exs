defmodule TheMaestroWeb.ApiThreadsApiTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "GET /api/sessions/:session_id/threads lists session threads", %{conn: conn} do
    s = session_fixture()
    {:ok, tid} = TheMaestro.Chat.new_thread(s.id, "Alpha")

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/sessions/#{s.id}/threads")
      |> json_response(200)

    assert is_list(resp["threads"]) and Enum.any?(resp["threads"], &(&1["id"] == tid))
  end

  test "POST /api/sessions/:session_id/threads creates thread with optional label", %{conn: conn} do
    s = session_fixture()

    created =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/sessions/#{s.id}/threads", %{label: "Beta"})
      |> json_response(200)

    assert is_binary(created["id"]) and created["label"] == "Beta"

    threads =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/sessions/#{s.id}/threads")
      |> json_response(200)

    assert Enum.any?(threads["threads"], &(&1["id"] == created["id"]))
  end

  test "PATCH /api/threads/:thread_id renames thread label", %{conn: conn} do
    s = session_fixture()
    {:ok, tid} = TheMaestro.Chat.new_thread(s.id, "Old")

    _resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> patch(~p"/api/threads/#{tid}", %{label: "NewLabel"})
      |> json_response(200)

    label = TheMaestro.Conversations.thread_label(tid)
    assert label == "NewLabel"
  end
end

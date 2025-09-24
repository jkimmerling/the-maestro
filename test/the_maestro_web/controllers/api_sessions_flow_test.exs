defmodule TheMaestroWeb.ApiSessionsFlowTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "POST /api/sessions creates session with tool_runtime remote by default", %{conn: conn} do
    # Create a saved authentication
    {:ok, sa} =
      TheMaestro.Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "api-session-" <> Integer.to_string(System.unique_integer([:positive])),
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/sessions", %{auth_id: sa.id, model: "gpt-4o", working_dir: nil})
      |> json_response(200)

    assert is_binary(resp["session_id"]) and byte_size(resp["session_id"]) > 0

    s = TheMaestro.Conversations.get_session!(resp["session_id"])
    assert s.tool_runtime in ["remote", "local"]
  end

  test "POST /api/sessions/:id/turns returns stream/thread ids", %{conn: conn} do
    s = session_fixture()
    {:ok, {_s, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/sessions/#{s.id}/turns", %{message: "hello from api"})
      |> json_response(202)

    assert is_binary(resp["stream_id"]) and is_binary(resp["thread_id"]) and
             resp["thread_id"] != ""

    # Latest frames should be retrievable for the thread
    frames =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/threads/#{resp["thread_id"]}/turns/latest/frames")
      |> json_response(200)

    assert is_map(frames) and Map.has_key?(frames, "frames")
  end
end

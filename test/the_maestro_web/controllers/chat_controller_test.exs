defmodule TheMaestroWeb.ChatControllerTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  test "POST /api/sessions/:id/turn returns 202 with stream keys", %{conn: conn} do
    s = session_fixture()
    {:ok, {_s, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)

    resp =
      conn
      |> post(~p"/api/sessions/#{s.id}/turn", %{message: "hello"})
      |> json_response(202)

    assert is_binary(resp["stream_id"]) and byte_size(resp["stream_id"]) > 0
    assert resp["provider"] in ["openai", "anthropic", "gemini"]
    assert is_binary(resp["model"]) and resp["model"] != ""
    assert is_binary(resp["thread_id"]) and resp["thread_id"] != ""
  end
end

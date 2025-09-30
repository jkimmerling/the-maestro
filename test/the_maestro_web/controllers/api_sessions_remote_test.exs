defmodule TheMaestroWeb.ApiSessionsRemoteTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "GET /api/sessions?tool_runtime=remote lists only remote sessions", %{conn: conn} do
    s_local = session_fixture(%{tool_runtime: "local"})
    s_remote = session_fixture(%{tool_runtime: "remote"})

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/sessions?tool_runtime=remote")
      |> json_response(200)

    assert is_list(resp["sessions"]) and length(resp["sessions"]) >= 1

    ids = Enum.map(resp["sessions"], & &1["id"]) |> MapSet.new()
    assert MapSet.member?(ids, to_string(s_remote.id))
    refute MapSet.member?(ids, to_string(s_local.id))

    # Ensure we returned expected fields
    assert Enum.all?(resp["sessions"], fn s ->
             Map.has_key?(s, "id") and Map.has_key?(s, "name") and Map.has_key?(s, "working_dir")
           end)
  end

  test "GET /api/sessions without tool_runtime returns 400", %{conn: conn} do
    _ = session_fixture(%{tool_runtime: "remote"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/sessions")

    assert conn.status == 400
  end
end

defmodule TheMaestroWeb.ApiPromptsMcpEndpointsTest do
  use TheMaestroWeb.ConnCase, async: true
  import TheMaestro.ConversationsFixtures

  @token "0000000000000000"

  test "GET /api/prompts/library returns provider-keyed lists", %{conn: conn} do
    _ = session_fixture()

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/prompts/library")
      |> json_response(200)

    assert is_map(resp["library"]) and Map.has_key?(resp["library"], "openai")
  end

  test "GET /api/mcp/servers/options returns label+id list", %{conn: conn} do
    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/mcp/servers/options")
      |> json_response(200)

    assert is_list(resp["servers"]) or resp["servers"] == []
  end
end

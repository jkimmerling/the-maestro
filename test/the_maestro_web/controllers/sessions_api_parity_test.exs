defmodule TheMaestroWeb.ApiSessionsParityTest do
  use TheMaestroWeb.ConnCase, async: true

  import TheMaestro.ConversationsFixtures
  import TheMaestro.MCPFixtures

  @token "0000000000000000"

  test "GET /api/sessions/:id returns provider, auth meta, and full config", %{conn: conn} do
    s = session_fixture(%{tool_runtime: "remote", model_id: "gpt-4o", persona: %{"a" => 1}})
    {:ok, {_s, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> get(~p"/api/sessions/#{s.id}")
      |> json_response(200)

    assert resp["id"] == to_string(s.id)
    assert resp["provider"] in ["openai", "anthropic", "gemini"]
    assert is_map(resp["auth"]) and Map.has_key?(resp["auth"], "type")
    assert resp["persona"] == %{"a" => 1}
    assert is_map(resp["memory"])
    assert is_map(resp["tools"])
    assert is_list(resp["mcp_server_ids"])
  end

  test "PATCH /api/sessions/:id with apply=now restarts stream and returns ids", %{conn: conn} do
    s = session_fixture(%{tool_runtime: "remote", model_id: "gpt-4o"})
    {:ok, {_s, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> patch(~p"/api/sessions/#{s.id}", %{model_id: "gpt-4o", apply: "now"})
      |> json_response(200)

    assert resp["apply"] == "now"
    assert is_binary(resp["stream_id"]) and String.length(resp["stream_id"]) > 0
    # thread_id may be nil prior to first persisted thread; stream attachment uses stream_id
  end

  test "POST /api/sessions accepts extended payload keys and persists", %{conn: conn} do
    {:ok, sa} =
      TheMaestro.Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "api-session-" <> Integer.to_string(System.unique_integer([:positive])),
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    server = server_fixture()

    payload = %{
      auth_id: sa.id,
      model_id: "gpt-4o",
      working_dir: nil,
      tool_runtime: "remote",
      persona: %{"role" => "coder"},
      memory: %{"project" => "x"},
      tools: %{"allowed" => %{"openai" => ["shell"]}},
      mcp_server_ids: [server.id],
      system_prompt_ids_by_provider: %{"openai" => []}
    }

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/sessions", payload)
      |> json_response(200)

    s = TheMaestro.Conversations.get_session!(resp["session_id"]) |> TheMaestro.Repo.preload(:mcp_servers)
    assert s.model_id == "gpt-4o"
    assert s.tool_runtime == "remote"
    assert s.persona == %{"role" => "coder"}
    assert s.memory == %{"project" => "x"}
    assert s.tools == %{"allowed" => %{"openai" => ["shell"]}}
    assert Enum.any?(s.mcp_servers, &(&1.id == server.id))
  end
end

defmodule TheMaestroWeb.Integration.GeminiReplaceServerE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  import Ecto.Query
  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.AgentLoop

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "gemini",
        auth_type: :oauth,
        name: "gemini-server-e2e",
        credentials: %{"access_token" => "test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Gemini Server E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session, saved_auth: saved_auth}}
  end

  test "server-side replace logs ToolChangeLog and builds Cloud Code parts", %{session: session, saved_auth: sa} do
    base = File.cwd!()
    rel = "tmp/e2e_gemini_replace_server.txt"
    abs = Path.join(base, rel)
    File.rm_rf!(Path.dirname(abs))
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, "a\na\n")

    args_map = %{"file_path" => rel, "old_string" => "a", "new_string" => "b", "expected_replacements" => 2}
    calls = [%{"id" => "call_1", "name" => "replace", "arguments" => Jason.encode!(args_map)}]

    t0_ms = System.monotonic_time(:millisecond)
    _contents = AgentLoop.build_gemini_tool_followup_public([], calls, session_name: sa.name)

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "assistant",
        provider: "gemini",
        request_headers: %{},
        response_headers: %{},
        combined_chat: %{"messages" => []},
        edit_version: 0
      })

    {_count, nil} = Conversations.link_logs_to_chat_entry!(session.id, t0_ms, entry.id)

    logs =
      TheMaestro.Repo.all(
        from l in TheMaestro.Conversations.ToolChangeLog, where: l.session_id == ^session.id
      )

    assert Enum.any?(logs, &(&1.tool_name == "edit" and String.ends_with?(&1.file_path, rel)))
    assert Enum.all?(logs, &(&1.chat_entry_id == entry.id))

    assert String.trim_trailing(File.read!(abs), "\n") == "b\nb"
  end
end

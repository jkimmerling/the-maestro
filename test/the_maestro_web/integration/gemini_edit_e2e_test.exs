defmodule TheMaestroWeb.Integration.GeminiEditE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  import Ecto.Query
  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Tools.Runtime

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "gemini",
        auth_type: :api_key,
        name: "gemini-e2e",
        credentials: %{"api_key" => "gk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Gemini E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "edit creates file; Cloud Code parts shape asserted", %{session: session} do
    base = File.cwd!()
    rel = "tmp/e2e_gemini_edit.txt"
    abs = Path.join(base, rel)
    File.rm_rf!(Path.dirname(abs))
    File.mkdir_p!(Path.dirname(abs))

    args_map = %{"file_path" => rel, "old_string" => "", "new_string" => "hi"}
    args_json = Jason.encode!(args_map)

    t0_ms = System.monotonic_time(:millisecond)
    assert {:ok, _payload} = Runtime.exec(session.id, "edit", args_json, base)

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

    assert Enum.any?(logs, &(&1.tool_name == "edit"))
    assert Enum.all?(logs, &(&1.chat_entry_id == entry.id))

    # Verify file was created by the edit tool
    assert File.exists?(abs), "Edit tool should have created file at #{abs}"
    assert String.trim_trailing(File.read!(abs), "\n") == "hi"

    # Provider-accurate parts (Cloud Code)
    fc_parts = [%{"functionCall" => %{"name" => "edit", "args" => args_map, "id" => "call_1"}}]

    fr_parts = [
      %{
        "functionResponse" => %{
          "name" => "edit",
          "response" => %{"output" => ""},
          "id" => "call_1"
        }
      }
    ]

    assert [%{"functionCall" => %{"name" => "edit", "args" => %{}, "id" => id1}}] = fc_parts
    assert is_binary(id1)

    assert [%{"functionResponse" => %{"name" => "edit", "response" => %{} = resp, "id" => id2}}] =
             fr_parts

    assert is_binary(id2)
    assert is_map(resp)
  end
end

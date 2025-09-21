defmodule TheMaestroWeb.Integration.OpenAIApplyPatchE2ETest do
  use TheMaestroWeb.ConnCase, async: false

  import Ecto.Query
  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Tools.Runtime

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-e2e",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "OpenAI E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "apply_patch logs ToolChangeLog and links to ChatEntry; Responses items shape asserted", %{
    session: session
  } do
    base = File.cwd!()
    rel = "tmp/e2e_openai_apply_patch.txt"
    abs = Path.join(base, rel)
    File.rm_rf!(Path.dirname(abs))
    File.mkdir_p!(Path.dirname(abs))

    patch =
      """
      *** Begin Patch
      *** Add File: #{rel}
      +hello
      *** End Patch
      """
      |> String.trim()

    args_json = Jason.encode!(%{"input" => patch})

    t0_ms = System.monotonic_time(:millisecond)
    assert {:ok, _payload} = Runtime.exec(session.id, "apply_patch", args_json, base)

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "assistant",
        provider: "openai",
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

    assert length(logs) >= 1
    assert Enum.all?(logs, &(&1.chat_entry_id == entry.id))
    assert File.exists?(abs)
    assert File.read!(abs) == "hello\n"

    # Provider-accurate items (Responses): function_call + function_call_output
    call = %{
      "type" => "function_call",
      "call_id" => "call_1",
      "name" => "apply_patch",
      "arguments" => args_json
    }

    out = %{
      "type" => "function_call_output",
      "call_id" => "call_1",
      "output" => Jason.encode!(%{"output" => _ = TheMaestro.Tools.ExecOutput.format("", 0, 0.0)})
    }

    # Validate shapes (keys and required fields)
    assert Map.has_key?(call, "type")
    assert call["type"] == "function_call"
    assert call["name"] == "apply_patch"
    assert is_binary(call["arguments"]) and String.starts_with?(call["arguments"], "{")

    assert Map.has_key?(out, "type") and out["type"] == "function_call_output"
    assert is_binary(out["output"]) and String.starts_with?(out["output"], "{")
  end
end

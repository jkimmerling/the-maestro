defmodule TheMaestroWeb.Integration.AnthropicEditE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  import Ecto.Query
  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Followups.Anthropic, as: AnthFollowups
  alias TheMaestro.Tools.Runtime

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "anthropic",
        auth_type: :api_key,
        name: "anthropic-e2e",
        credentials: %{"api_key" => "ak-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Anthropic E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "edit non-unique without replace_all returns Claude-copy error; tool_use/tool_result shapes asserted",
       %{session: session} do
    base = File.cwd!()
    rel = "tmp/e2e_anthropic_edit.txt"
    abs = Path.join(base, rel)
    File.rm_rf!(Path.dirname(abs))
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, "a\na\n")

    # Non-unique old_string without replace_all
    args_map = %{"file_path" => rel, "old_string" => "a", "new_string" => "b"}
    args_json = Jason.encode!(args_map)
    assert {:error, msg} = Runtime.exec(session.id, "edit", args_json, base)
    assert msg =~ "non-unique match without replace_all"

    # Success path with replace_all true
    ok_args = Jason.encode!(Map.put(args_map, "replace_all", true))
    t0_ms = System.monotonic_time(:millisecond)
    assert {:ok, _} = Runtime.exec(session.id, "edit", ok_args, base)

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "assistant",
        provider: "anthropic",
        request_headers: %{},
        response_headers: %{},
        combined_chat: %{
          "messages" => [
            %{"role" => "user", "content" => [%{"type" => "text", "text" => "Please edit"}]}
          ]
        },
        edit_version: 0
      })

    {_count, nil} = Conversations.link_logs_to_chat_entry!(session.id, t0_ms, entry.id)

    logs =
      TheMaestro.Repo.all(
        from l in TheMaestro.Conversations.ToolChangeLog, where: l.session_id == ^session.id
      )

    assert Enum.any?(logs, &(&1.tool_name == "edit"))
    assert Enum.all?(logs, &(&1.chat_entry_id == entry.id))

    # Build provider-accurate follow-up messages using builder
    calls = [%{"id" => "call_1", "name" => "edit", "arguments" => ok_args}]
    {messages, _outs} = AnthFollowups.build(entry.combined_chat["messages"], calls, "")

    assert [
             %{"role" => "assistant", "content" => blocks},
             %{"role" => "user", "content" => results}
           ] = Enum.slice(messages, -2, 2)

    assert Enum.any?(blocks, &(&1["type"] == "tool_use" and &1["name"] == "edit"))
    assert Enum.all?(results, &(&1["type"] == "tool_result"))
  end
end

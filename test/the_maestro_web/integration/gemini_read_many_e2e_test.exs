defmodule TheMaestroWeb.Integration.GeminiReadManyE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.AgentLoop
  alias TheMaestro.Auth
  alias TheMaestro.Conversations

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "gemini",
        auth_type: :api_key,
        name: "gemini-readmany-e2e",
        credentials: %{"api_key" => "gk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Gemini ReadMany E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "functionResponse exists and returns concatenated content", %{session: _session} do
    base = File.cwd!()
    dir = Path.join(base, "tmp/gemini_read_many")
    p1 = Path.join(dir, "rm_1.txt")
    p2 = Path.join(dir, "rm_2.txt")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    File.write!(p1, "A")
    File.write!(p2, "B")

    calls = [
      %{
        "id" => "call_1",
        "name" => "read_many_files",
        "arguments" =>
          Jason.encode!(%{"files" => [Path.relative_to(p1, base), Path.relative_to(p2, base)]})
      }
    ]

    contents = AgentLoop.build_gemini_tool_followup_public([], calls)

    assert [
             %{"role" => "assistant", "parts" => fc_parts},
             %{"role" => "tool", "parts" => fr_parts}
           ] = contents

    assert [%{"functionCall" => %{"name" => "read_many_files", "id" => "call_1"}}] = fc_parts

    assert [
             %{
               "functionResponse" => %{
                 "name" => "read_many_files",
                 "id" => "call_1",
                 "response" => resp
               }
             }
           ] = fr_parts

    assert is_map(resp)
  end
end

defmodule TheMaestroWeb.Integration.GeminiWebFetchE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.AgentLoop

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "gemini",
        auth_type: :api_key,
        name: "gemini-webfetch-e2e",
        credentials: %{"api_key" => "gk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Gemini WebFetch E2E",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "functionResponse shape for web_fetch", %{session: _session} do
    # Use a harmless URL; WebFetch outputs JSON string. We only assert shape from follow-up builder.
    calls = [
      %{
        "id" => "call_1",
        "name" => "web_fetch",
        "arguments" => Jason.encode!(%{"url" => "https://example.com"})
      }
    ]

    contents = AgentLoop.build_gemini_tool_followup_public([], calls)

    assert [%{"role" => "assistant", "parts" => _fc}, %{"role" => "tool", "parts" => fr_parts}] = contents
    assert [%{"functionResponse" => %{"name" => "web_fetch", "id" => "call_1", "response" => resp}}] = fr_parts
    assert is_map(resp)
  end
end


defmodule TheMaestro.Providers.Anthropic.TodoWritePersistenceTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Followups.Anthropic
  alias TheMaestro.Todos

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "anthropic",
        auth_type: :api_key,
        name: "anthropic-todo-test",
        credentials: %{"api_key" => "ak-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Todo Tool Test",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, %{session: session}}
  end

  test "todo_write persists to Redis via Followups.Anthropic", %{session: session} do
    calls = [
      %{
        "id" => "call_1",
        "name" => "todo_write",
        "arguments" =>
          Jason.encode!(%{
            "todos" => [
              %{content: "Implement X", activeForm: "dev", status: "pending"}
            ]
          })
      }
    ]

    {_, _} = Anthropic.build([], calls, "", base_cwd: File.cwd!(), session_id: session.id)

    items = Todos.list(session.id)
    assert Enum.any?(items, fn it -> (it["content"] || it[:content]) == "Implement X" end)
  end
end

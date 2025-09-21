defmodule TheMaestro.Conversations.CleanupRedisOnDeleteTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.{Auth, Conversations, Plans, Todos, Images}

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "cleanup-redis-test",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Cleanup Test",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    # Seed Redis entries
    :ok = Plans.put(session.id, nil, [%{step: "a", status: "pending"}])
    :ok = Todos.put(session.id, nil, [%{content: "t", activeForm: "dev", status: "pending"}])
    :ok = Images.append(session.id, nil, %{path: "/tmp/x.png", ts: 0})

    {:ok, %{session: session}}
  end

  test "delete_session clears plans/todos/images keys", %{session: session} do
    {:ok, _} = Conversations.delete_session(session)

    assert Plans.list(session.id) == []
    assert Todos.list(session.id) == []
    assert Images.list(session.id) == []
  end
end


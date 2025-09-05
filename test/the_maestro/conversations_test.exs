defmodule TheMaestro.ConversationsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Conversations

  describe "sessions" do
    alias TheMaestro.Conversations.Session

    import TheMaestro.ConversationsFixtures

    @invalid_attrs %{name: nil, last_used_at: nil}

    test "list_sessions/0 includes newly created session" do
      session = session_fixture()
      assert Enum.any?(Conversations.list_sessions(), &(&1.id == session.id))
    end

    test "get_session!/1 returns the session with given id" do
      session = session_fixture()
      assert Conversations.get_session!(session.id) == session
    end

    test "create_session/1 with valid data creates a session" do
      # Provide a valid agent_id
      short = String.slice(Ecto.UUID.generate(), 0, 6)

      {:ok, sa} =
        %TheMaestro.SavedAuthentication{}
        |> TheMaestro.SavedAuthentication.changeset(%{
          provider: :openai,
          auth_type: :api_key,
          name: "test_openai_api_key_ctx_sessions-" <> short,
          credentials: %{"api_key" => "sk-test"}
        })
        |> TheMaestro.Repo.insert()

      {:ok, agent} =
        %TheMaestro.Agents.Agent{}
        |> TheMaestro.Agents.Agent.changeset(%{
          name: "agent_for_session_test-" <> short,
          auth_id: sa.id,
          tools: %{},
          mcps: %{},
          memory: %{"k" => "v"}
        })
        |> TheMaestro.Repo.insert()

      valid_attrs = %{
        name: "some name",
        last_used_at: ~U[2025-09-01 15:30:00Z],
        agent_id: agent.id
      }

      assert {:ok, %Session{} = session} = Conversations.create_session(valid_attrs)
      assert session.name == "some name"
      assert session.last_used_at == ~U[2025-09-01 15:30:00Z]
    end

    test "create_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Conversations.create_session(@invalid_attrs)
    end

    test "update_session/2 with valid data updates the session" do
      session = session_fixture()
      update_attrs = %{name: "some updated name", last_used_at: ~U[2025-09-02 15:30:00Z]}

      assert {:ok, %Session{} = session} = Conversations.update_session(session, update_attrs)
      assert session.name == "some updated name"
      assert session.last_used_at == ~U[2025-09-02 15:30:00Z]
    end

    test "update_session/2 with invalid data keeps required fields and succeeds" do
      session = session_fixture()
      assert {:ok, %Session{} = updated} = Conversations.update_session(session, @invalid_attrs)
      assert updated.id == session.id
    end

    test "delete_session/1 deletes the session" do
      session = session_fixture()
      assert {:ok, %Session{}} = Conversations.delete_session(session)
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_session!(session.id) end
    end

    test "change_session/1 returns a session changeset" do
      session = session_fixture()
      assert %Ecto.Changeset{} = Conversations.change_session(session)
    end
  end
end

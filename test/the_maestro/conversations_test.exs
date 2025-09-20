defmodule TheMaestro.ConversationsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Conversations
  alias TheMaestro.{Repo, SystemPrompts}
  alias TheMaestro.SuppliedContext.SuppliedContextItem

  import Ecto.Query

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

      valid_attrs = %{
        name: "some name",
        last_used_at: ~U[2025-09-01 15:30:00Z],
        auth_id: sa.id
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

    test "create_session/1 attaches default system prompts" do
      session = session_fixture()

      assert {:ok, %{source: :session, prompts: prompts}} =
               SystemPrompts.resolve_for_session(session.id, :openai)

      assert length(prompts) > 0
      assert Enum.all?(prompts, fn %{prompt: prompt} -> prompt.provider in [:openai, :shared] end)
    end

    test "update_session/2 accepts explicit system prompt selections" do
      session = session_fixture()

      default_prompt =
        Repo.one!(
          from i in SuppliedContextItem,
            where: i.type == :system_prompt and i.provider == :openai and i.is_default == true,
            limit: 1
        )

      {:ok, new_version} =
        SystemPrompts.create_version(default_prompt, %{
          text: "updated prompt",
          version: default_prompt.version + 1,
          is_default: false
        })

      {:ok, _session} =
        Conversations.update_session(session, %{
          "system_prompts" => %{"openai" => [%{"id" => new_version.id}]}
        })

      assert {:ok, %{prompts: [%{prompt: prompt}]}} =
               SystemPrompts.resolve_for_session(session.id, :openai)

      assert prompt.id == new_version.id
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

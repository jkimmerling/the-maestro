defmodule TheMaestro.ConversationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Conversations` context.
  """

  @doc """
  Generate a session.
  """
  def session_fixture(attrs \\ %{}) do
    # Ensure an Agent exists to satisfy FK
    {:ok, sa} =
      %TheMaestro.SavedAuthentication{}
      |> TheMaestro.SavedAuthentication.changeset(%{
        provider: :openai,
        auth_type: :api_key,
        name:
          "test_openai_api_key_session_fixture-" <>
            Integer.to_string(System.unique_integer([:positive])),
        credentials: %{"api_key" => "sk-test"}
      })
      |> TheMaestro.Repo.insert()

    short = String.slice(Ecto.UUID.generate(), 0, 6)

    {:ok, agent} =
      %TheMaestro.Agents.Agent{}
      |> TheMaestro.Agents.Agent.changeset(%{
        name: "agent_for_session-" <> short,
        auth_id: sa.id,
        tools: %{},
        mcps: %{},
        memory: %{}
      })
      |> TheMaestro.Repo.insert()

    base = %{
      last_used_at: ~U[2025-09-01 15:30:00Z],
      name: "some name",
      agent_id: agent.id
    }

    {:ok, session} =
      attrs
      |> Enum.into(base)
      |> TheMaestro.Conversations.create_session()

    session
  end
end

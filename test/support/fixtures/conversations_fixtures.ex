defmodule TheMaestro.ConversationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Conversations` context.
  """

  @doc """
  Generate a session.
  """
  def session_fixture(attrs \\ %{}) do
    # Ensure a Saved Auth exists
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

    base = %{
      last_used_at: ~U[2025-09-01 15:30:00Z],
      name: "some name",
      auth_id: sa.id
    }

    {:ok, session} =
      attrs
      |> Enum.into(base)
      |> TheMaestro.Conversations.create_session()

    session
  end
end

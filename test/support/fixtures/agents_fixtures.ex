defmodule TheMaestro.AgentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Agents` context.
  """

  @doc """
  Generate a agent.
  """
  def agent_fixture(attrs \\ %{}) do
    # Ensure there is a SavedAuthentication to satisfy FK
    {:ok, sa} =
      %TheMaestro.SavedAuthentication{}
      |> TheMaestro.SavedAuthentication.changeset(%{
        provider: :openai,
        auth_type: :api_key,
        name: "test_openai_api_key",
        credentials: %{"api_key" => "sk-test"}
      })
      |> TheMaestro.Repo.insert()

    base_attrs = %{
      mcps: %{},
      memory: %{},
      name: "some_name",
      tools: %{},
      auth_id: sa.id
    }

    {:ok, agent} =
      attrs
      |> Enum.into(base_attrs)
      |> TheMaestro.Agents.create_agent()

    agent
  end
end

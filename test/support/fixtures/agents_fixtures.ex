defmodule TheMaestro.AgentsFixtures do
  @compile {:no_warn_undefined, TheMaestro.Agents}
  @compile {:no_warn_undefined, TheMaestro.Agents.Agent}
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Agents` context.
  """

  @doc """
  Generate a agent.
  """
  def agent_fixture(attrs \\ %{}) do
    # Ensure there is a SavedAuthentication to satisfy FK
    short = String.slice(Ecto.UUID.generate(), 0, 8)

    {:ok, sa} =
      %TheMaestro.SavedAuthentication{}
      |> TheMaestro.SavedAuthentication.changeset(%{
        provider: :openai,
        auth_type: :api_key,
        name: "tok-" <> short,
        credentials: %{"api_key" => "sk-test"}
      })
      |> TheMaestro.Repo.insert()

    base_attrs = %{
      mcps: %{},
      memory: %{},
      name: "some_name-" <> short,
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

defmodule TheMaestro.AgentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Agents` context.
  """

  @doc """
  Generate a agent.
  """
  def agent_fixture(attrs \\ %{}) do
    {:ok, agent} =
      attrs
      |> Enum.into(%{
        mcps: %{},
        memory: %{},
        name: "some name",
        tools: %{}
      })
      |> TheMaestro.Agents.create_agent()

    agent
  end
end

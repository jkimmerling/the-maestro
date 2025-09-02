defmodule TheMaestro.AgentsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Agents

  describe "agents" do
    alias TheMaestro.Agents.Agent

    import TheMaestro.AgentsFixtures

    @invalid_attrs %{memory: nil, name: nil, tools: nil, mcps: nil}

    test "list_agents/0 returns all agents" do
      agent = agent_fixture()
      assert Agents.list_agents() == [agent]
    end

    test "get_agent!/1 returns the agent with given id" do
      agent = agent_fixture()
      assert Agents.get_agent!(agent.id) == agent
    end

    test "create_agent/1 with valid data creates a agent" do
      valid_attrs = %{memory: %{}, name: "some name", tools: %{}, mcps: %{}}

      assert {:ok, %Agent{} = agent} = Agents.create_agent(valid_attrs)
      assert agent.memory == %{}
      assert agent.name == "some name"
      assert agent.tools == %{}
      assert agent.mcps == %{}
    end

    test "create_agent/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Agents.create_agent(@invalid_attrs)
    end

    test "update_agent/2 with valid data updates the agent" do
      agent = agent_fixture()
      update_attrs = %{memory: %{}, name: "some updated name", tools: %{}, mcps: %{}}

      assert {:ok, %Agent{} = agent} = Agents.update_agent(agent, update_attrs)
      assert agent.memory == %{}
      assert agent.name == "some updated name"
      assert agent.tools == %{}
      assert agent.mcps == %{}
    end

    test "update_agent/2 with invalid data returns error changeset" do
      agent = agent_fixture()
      assert {:error, %Ecto.Changeset{}} = Agents.update_agent(agent, @invalid_attrs)
      assert agent == Agents.get_agent!(agent.id)
    end

    test "delete_agent/1 deletes the agent" do
      agent = agent_fixture()
      assert {:ok, %Agent{}} = Agents.delete_agent(agent)
      assert_raise Ecto.NoResultsError, fn -> Agents.get_agent!(agent.id) end
    end

    test "change_agent/1 returns a agent changeset" do
      agent = agent_fixture()
      assert %Ecto.Changeset{} = Agents.change_agent(agent)
    end
  end
end

defmodule TheMaestro.AgentsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Agents

  describe "agents" do
    alias TheMaestro.Agents.Agent

    import TheMaestro.AgentsFixtures

    @invalid_attrs %{memory: nil, name: nil, tools: nil, mcps: nil}

    test "list_agents/0 includes newly created agent" do
      agent = agent_fixture()
      ids = Enum.map(Agents.list_agents(), & &1.id)
      assert agent.id in ids
    end

    test "get_agent!/1 returns the agent with given id" do
      agent = agent_fixture()
      assert Agents.get_agent!(agent.id).id == agent.id
    end

    test "create_agent/1 with valid data creates a agent" do
      short = String.slice(Ecto.UUID.generate(), 0, 6)

      sa =
        TheMaestro.Repo.insert!(
          TheMaestro.SavedAuthentication.changeset(%TheMaestro.SavedAuthentication{}, %{
            provider: :openai,
            auth_type: :api_key,
            name: "test_openai_api_key_ctx-" <> short,
            credentials: %{"api_key" => "sk-test"}
          })
        )

      valid_attrs = %{
        memory: %{},
        name: "some_name-" <> short,
        tools: %{},
        mcps: %{},
        auth_id: sa.id
      }

      assert {:ok, %Agent{} = agent} = Agents.create_agent(valid_attrs)
      assert agent.memory == %{}
      assert agent.name == valid_attrs.name
      assert agent.tools == %{}
      assert agent.mcps == %{}
    end

    test "create_agent/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Agents.create_agent(@invalid_attrs)
    end

    test "update_agent/2 with valid data updates the agent" do
      agent = agent_fixture()

      update_attrs = %{
        memory: %{},
        name: "some_updated_name-" <> String.slice(Ecto.UUID.generate(), 0, 6),
        tools: %{},
        mcps: %{}
      }

      assert {:ok, %Agent{} = agent} = Agents.update_agent(agent, update_attrs)
      assert agent.memory == %{}
      assert agent.name == update_attrs.name
      assert agent.tools == %{}
      assert agent.mcps == %{}
    end

    test "update_agent/2 with invalid data returns error changeset" do
      agent = agent_fixture()
      assert {:error, %Ecto.Changeset{}} = Agents.update_agent(agent, @invalid_attrs)
      assert Agents.get_agent!(agent.id).id == agent.id
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

defmodule TheMaestro.AgentsTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Agents

  describe "start_agent/2" do
    test "starts a new agent process with unique ID" do
      agent_id = "test_agent_#{System.unique_integer()}"

      assert {:ok, pid} = Agents.start_agent(agent_id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "fails to start agent with duplicate ID" do
      agent_id = "duplicate_agent_#{System.unique_integer()}"

      assert {:ok, _pid1} = Agents.start_agent(agent_id)
      assert {:error, {:already_started, _pid2}} = Agents.start_agent(agent_id)
    end
  end

  describe "send_message/2" do
    test "sends message to agent and receives response" do
      agent_id = "message_agent_#{System.unique_integer()}"
      {:ok, _pid} = Agents.start_agent(agent_id)

      message = "Hello, agent!"
      assert {:ok, response} = Agents.send_message(agent_id, message)

      assert response.type == :assistant
      assert response.content =~ message
      assert %DateTime{} = response.timestamp
    end

    test "updates agent state with message history" do
      agent_id = "history_agent_#{System.unique_integer()}"
      {:ok, _pid} = Agents.start_agent(agent_id)

      message = "Test message"
      {:ok, _response} = Agents.send_message(agent_id, message)

      state = Agents.get_agent_state(agent_id)

      # user message + assistant response
      assert length(state.message_history) == 2

      [user_msg, assistant_msg] = state.message_history
      assert user_msg.type == :user
      assert user_msg.content == message
      assert assistant_msg.type == :assistant
    end
  end

  describe "find_or_start_agent/2" do
    test "returns existing agent if already started" do
      agent_id = "existing_agent_#{System.unique_integer()}"
      {:ok, pid1} = Agents.start_agent(agent_id)

      {:ok, pid2} = Agents.find_or_start_agent(agent_id)

      assert pid1 == pid2
    end

    test "starts new agent if not already started" do
      agent_id = "new_agent_#{System.unique_integer()}"

      {:ok, pid} = Agents.find_or_start_agent(agent_id)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "supervision and fault tolerance" do
    test "agents are managed through dynamic supervisor" do
      agent_id = "supervised_agent_#{System.unique_integer()}"

      # Can start agent through the context API
      {:ok, pid} = Agents.start_agent(agent_id)
      assert Process.alive?(pid)

      # Agent can process messages
      {:ok, _response} = Agents.send_message(agent_id, "Test message")

      # Can terminate agent cleanly
      :ok = Agents.terminate_agent(pid)
      :timer.sleep(10)
      refute Process.alive?(pid)

      # Can start new agents with different IDs
      new_agent_id = "supervised_agent_new_#{System.unique_integer()}"
      {:ok, new_pid} = Agents.start_agent(new_agent_id)
      assert Process.alive?(new_pid)
      assert new_pid != pid
    end
  end
end

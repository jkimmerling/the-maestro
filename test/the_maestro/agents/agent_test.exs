defmodule TheMaestro.Agents.AgentTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.Agents.Agent
  
  setup do
    agent_id = "test_agent_#{System.unique_integer()}"
    {:ok, pid} = Agent.start_link(agent_id: agent_id)
    
    {:ok, agent_id: agent_id, pid: pid}
  end
  
  describe "initialization" do
    test "starts with correct initial state", %{agent_id: agent_id} do
      state = Agent.get_state(agent_id)
      
      assert state.agent_id == agent_id
      assert state.message_history == []
      assert state.loop_state == :idle
      assert %DateTime{} = state.created_at
    end
  end
  
  describe "send_message/2" do
    test "processes message and returns response", %{agent_id: agent_id} do
      message = "Test message"
      
      assert {:ok, response} = Agent.send_message(agent_id, message)
      
      assert response.type == :assistant
      assert response.content =~ message
      assert %DateTime{} = response.timestamp
    end
    
    test "updates message history correctly", %{agent_id: agent_id} do
      message = "Hello, world!"
      
      {:ok, _response} = Agent.send_message(agent_id, message)
      
      state = Agent.get_state(agent_id)
      assert length(state.message_history) == 2
      
      [user_message, assistant_message] = state.message_history
      
      # Check user message
      assert user_message.type == :user
      assert user_message.content == message
      assert %DateTime{} = user_message.timestamp
      
      # Check assistant response
      assert assistant_message.type == :assistant
      assert assistant_message.content =~ message
      assert %DateTime{} = assistant_message.timestamp
    end
    
    test "maintains correct message order with multiple messages", %{agent_id: agent_id} do
      messages = ["First message", "Second message", "Third message"]
      
      Enum.each(messages, fn message ->
        {:ok, _} = Agent.send_message(agent_id, message)
      end)
      
      state = Agent.get_state(agent_id)
      
      # Should have 6 messages (3 user + 3 assistant)
      assert length(state.message_history) == 6
      
      # Messages should be in chronological order (oldest first)
      # Get the last two messages (newest)
      latest_messages = Enum.take(state.message_history, -2)
      [latest_user, latest_assistant] = latest_messages
      
      assert latest_user.content == "Third message"
      assert latest_assistant.content =~ "Third message"
    end
    
    test "maintains idle loop state after processing", %{agent_id: agent_id} do
      {:ok, _} = Agent.send_message(agent_id, "Test")
      
      state = Agent.get_state(agent_id)
      assert state.loop_state == :idle
    end
  end
  
  describe "registry integration" do
    test "agent is registered with unique name" do
      agent_id = "registry_test_#{System.unique_integer()}"
      {:ok, pid} = Agent.start_link(agent_id: agent_id)
      
      # Should be able to find the process via registry
      registry_result = Registry.lookup(TheMaestro.Agents.Registry, agent_id)
      assert [{^pid, nil}] = registry_result
    end
  end
end
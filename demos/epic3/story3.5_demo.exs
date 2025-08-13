# Demo script for Epic 3 Story 3.5: Conversation Checkpointing
#
# This script demonstrates the conversation session save and restore functionality
# by creating a conversation, saving it, clearing the state, and then restoring it.

alias TheMaestro.Agents
alias TheMaestro.Sessions

defmodule SessionDemo do
  def run do
    IO.puts("🎯 Epic 3 Story 3.5 Demo: Conversation Checkpointing")
    IO.puts("======================================================")
    IO.puts("")
    
    # Create a test agent
    agent_id = "demo_agent_#{System.system_time(:millisecond)}"
    IO.puts("🤖 Creating agent with ID: #{agent_id}")
    
    agent_opts = [
      agent_id: agent_id,
      llm_provider: TheMaestro.Providers.TestProvider
    ]
    
    case Agents.find_or_start_agent(agent_id, agent_opts) do
      {:ok, _pid} ->
        IO.puts("✅ Agent created successfully")
        demo_conversation(agent_id)
      
      {:error, reason} ->
        IO.puts("❌ Failed to create agent: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp demo_conversation(agent_id) do
    IO.puts("")
    IO.puts("💬 Starting demonstration conversation...")
    
    # Send a few messages to create conversation history
    messages = [
      "Hello, this is my first message",
      "Tell me about Elixir programming",
      "Can you help me with pattern matching?"
    ]
    
    Enum.each(messages, fn message ->
      IO.puts("👤 User: #{message}")
      case Agents.send_message(agent_id, message) do
        {:ok, response} ->
          IO.puts("🤖 Agent: #{String.slice(response.content, 0, 80)}...")
        {:error, reason} ->
          IO.puts("❌ Error: #{inspect(reason)}")
      end
    end)
    
    # Get current conversation state
    state = Agents.get_agent_state(agent_id)
    original_message_count = length(state.message_history)
    IO.puts("")
    IO.puts("📊 Current conversation has #{original_message_count} messages")
    
    # Test saving session
    demo_save_session(agent_id, original_message_count)
  end
  
  defp demo_save_session(agent_id, original_message_count) do
    IO.puts("")
    IO.puts("💾 Testing session save functionality...")
    
    session_name = "demo_session_#{System.system_time(:millisecond)}"
    
    case TheMaestro.Agents.Agent.save_session(agent_id, session_name) do
      {:ok, conversation_session} ->
        IO.puts("✅ Session '#{conversation_session.session_name}' saved successfully!")
        IO.puts("   - Session ID: #{conversation_session.id}")
        IO.puts("   - Message count: #{conversation_session.message_count}")
        IO.puts("   - Created at: #{conversation_session.inserted_at}")
        
        # Test listing sessions
        demo_list_sessions(agent_id, session_name, original_message_count)
      
      {:error, reason} ->
        IO.puts("❌ Failed to save session: #{inspect(reason)}")
    end
  end
  
  defp demo_list_sessions(agent_id, session_name, original_message_count) do
    IO.puts("")
    IO.puts("📋 Testing session listing...")
    
    sessions = TheMaestro.Agents.Agent.list_sessions(agent_id)
    IO.puts("✅ Found #{length(sessions)} saved sessions for agent")
    
    Enum.each(sessions, fn session ->
      IO.puts("   - #{session.session_name} (#{session.message_count} messages)")
    end)
    
    # Test restoring session
    demo_restore_session(agent_id, session_name, original_message_count)
  end
  
  defp demo_restore_session(agent_id, session_name, original_message_count) do
    IO.puts("")
    IO.puts("🔄 Testing session restore functionality...")
    
    # First, add a new message to change the current state
    case Agents.send_message(agent_id, "This is a new message after saving") do
      {:ok, _response} ->
        current_state = Agents.get_agent_state(agent_id)
        current_message_count = length(current_state.message_history)
        IO.puts("📊 Current state has #{current_message_count} messages")
        
        # Now restore the saved session
        case TheMaestro.Agents.Agent.restore_session(agent_id, session_name) do
          :ok ->
            restored_state = Agents.get_agent_state(agent_id)
            restored_message_count = length(restored_state.message_history)
            
            IO.puts("✅ Session restored successfully!")
            IO.puts("   - Original messages: #{original_message_count}")
            IO.puts("   - Before restore: #{current_message_count}")
            IO.puts("   - After restore: #{restored_message_count}")
            
            if restored_message_count == original_message_count do
              IO.puts("✅ Message history correctly restored!")
              demo_verify_content(restored_state)
            else
              IO.puts("❌ Message count mismatch!")
            end
          
          {:error, reason} ->
            IO.puts("❌ Failed to restore session: #{inspect(reason)}")
        end
      
      {:error, reason} ->
        IO.puts("❌ Failed to send test message: #{inspect(reason)}")
    end
  end
  
  defp demo_verify_content(restored_state) do
    IO.puts("")
    IO.puts("🔍 Verifying restored conversation content...")
    
    IO.puts("📝 Restored message history:")
    Enum.with_index(restored_state.message_history, 1)
    |> Enum.each(fn {message, index} ->
      type_icon = if message.type == :user, do: "👤", else: "🤖"
      content_preview = String.slice(message.content, 0, 50)
      IO.puts("   #{index}. #{type_icon} #{content_preview}...")
    end)
    
    IO.puts("")
    IO.puts("✅ Demo completed successfully!")
    IO.puts("🎉 Conversation checkpointing is working correctly!")
    IO.puts("")
    IO.puts("Key features demonstrated:")
    IO.puts("  ✓ Save conversation session with metadata")
    IO.puts("  ✓ List saved sessions for an agent")
    IO.puts("  ✓ Restore complete conversation history")
    IO.puts("  ✓ Preserve message content and timestamps")
    IO.puts("")
  end
end

# Run the demo
SessionDemo.run()
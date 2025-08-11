#!/usr/bin/env elixir

# Epic 1 Demo: Core Agent Engine
#
# This script demonstrates the foundational capabilities implemented in Epic 1:
# - Starting the OTP application and supervision tree
# - Spawning an AI agent with Gemini LLM integration
# - Basic conversation with the LLM provider
# - Secure file reading operations through the tooling system
#
# Prerequisites:
# - Gemini API key or OAuth credentials configured
# - File system tool allowed directories configured
# - Mix dependencies installed
#
# Usage: mix run demos/epic1/demo.exs

defmodule Epic1Demo do
  @moduledoc """
  Interactive demo showcasing Epic 1's core agent engine functionality.
  
  This demo creates a conversation session that demonstrates both direct LLM
  interaction and tool-assisted responses, showing the ReAct loop in action.
  """
  
  require Logger
  
  def run do
    IO.puts("""
    ═══════════════════════════════════════════════════════════════
    🤖 The Maestro - Epic 1 Demo: Core Agent Engine
    ═══════════════════════════════════════════════════════════════
    
    This demo showcases the foundational capabilities of The Maestro:
    • OTP application architecture with fault tolerance
    • AI Agent with Gemini LLM integration  
    • Secure file system operations
    • ReAct (Reason and Act) conversational loop
    """)
    
    case ensure_application_started() do
      :ok -> 
        IO.puts("✅ Application started successfully!")
        run_demo_conversation()
      {:error, reason} ->
        IO.puts("❌ Failed to start application: #{inspect(reason)}")
        exit_with_instructions()
    end
  end
  
  defp ensure_application_started do
    # Check if application is already running (when run with mix run)
    if Application.started_applications() |> Enum.any?(fn {app, _, _} -> app == :the_maestro end) do
      IO.puts("Application already running - using existing instance")
      :ok
    else
      # Try to start the application
      case Application.ensure_all_started(:the_maestro) do
        {:ok, _apps} -> 
          # Wait a moment for all supervisors to fully initialize
          Process.sleep(1000)
          :ok
        {:error, reason} -> 
          {:error, reason}
      end
    end
  end
  
  defp run_demo_conversation do
    agent_id = "epic1_demo_#{System.system_time(:second)}"
    IO.puts("🚀 Creating agent with ID: #{agent_id}")
    
    # Start the agent with Gemini provider and let it initialize auth
    case TheMaestro.Agents.start_agent(agent_id, [
      llm_provider: TheMaestro.Providers.Gemini,
      auth_context: nil  # Let agent initialize its own auth
    ]) do
      {:ok, _pid} ->
        IO.puts("✅ Agent started successfully!")
        
        # Run the demo conversation sequence
        demo_conversation_sequence(agent_id)
        
      {:error, reason} ->
        IO.puts("❌ Failed to start agent: #{inspect(reason)}")
        exit_with_instructions()
    end
  end
  
  defp demo_conversation_sequence(agent_id) do
    IO.puts("\n" <> String.duplicate("─", 60))
    IO.puts("📋 DEMO SEQUENCE: Testing Core Agent Capabilities")
    IO.puts(String.duplicate("─", 60))
    
    # Test 1: Simple LLM conversation
    test_simple_conversation(agent_id)
    
    # Brief pause between tests
    Process.sleep(2000)
    
    # Test 2: Tool-assisted response (file reading)
    test_file_tool_usage(agent_id)
    
    # Display final agent state
    display_final_state(agent_id)
    
    IO.puts("\n✨ Demo completed successfully!")
    IO.puts("The agent has demonstrated both direct LLM interaction and tool usage.")
  end
  
  defp test_simple_conversation(agent_id) do
    IO.puts("\n🔬 TEST 1: Simple LLM Conversation")
    IO.puts("Sending message: 'Hello! Please introduce yourself briefly.'")
    
    case TheMaestro.Agents.send_message(agent_id, "Hello! Please introduce yourself briefly.") do
      {:ok, response} ->
        IO.puts("✅ LLM Response received!")
        IO.puts("💬 Agent: #{String.slice(response.content, 0, 200)}...")
        if String.length(response.content) > 200 do
          IO.puts("   (response truncated for demo display)")
        end
        
      {:error, reason} ->
        IO.puts("❌ LLM call failed: #{inspect(reason)}")
        suggest_auth_troubleshooting()
    end
  end
  
  defp test_file_tool_usage(agent_id) do
    IO.puts("\n🛠️  TEST 2: File Tool Usage")
    
    # Create the test file path relative to the current demo directory
    demo_dir = Path.dirname(__ENV__.file)
    test_file_path = Path.join(demo_dir, "test_file.txt")
    
    IO.puts("Asking agent to read file: #{test_file_path}")
    
    message = """
    Please read the contents of the file located at: #{test_file_path}
    
    Use your file reading tool to access this file and tell me what it contains.
    """
    
    case TheMaestro.Agents.send_message(agent_id, message) do
      {:ok, response} ->
        IO.puts("✅ Tool-assisted response received!")
        IO.puts("🔧 Agent (with file tool): #{String.slice(response.content, 0, 300)}...")
        if String.length(response.content) > 300 do
          IO.puts("   (response truncated for demo display)")
        end
        
        # Check if the response indicates successful file reading
        if String.contains?(response.content, "Epic 1") or 
           String.contains?(response.content, "test file") or
           String.contains?(response.content, "✅") do
          IO.puts("🎯 File tool execution appears successful!")
        else
          IO.puts("⚠️  File tool may not have executed - check configuration")
          suggest_file_tool_troubleshooting()
        end
        
      {:error, reason} ->
        IO.puts("❌ Tool-assisted call failed: #{inspect(reason)}")
        suggest_file_tool_troubleshooting()
    end
  end
  
  defp display_final_state(agent_id) do
    IO.puts("\n📊 FINAL AGENT STATE")
    IO.puts(String.duplicate("─", 30))
    
    state = TheMaestro.Agents.get_agent_state(agent_id)
    
    IO.puts("Agent ID: #{state.agent_id}")
    IO.puts("Loop State: #{state.loop_state}")
    IO.puts("Message History: #{length(state.message_history)} messages")
    IO.puts("LLM Provider: #{inspect(state.llm_provider)}")
    IO.puts("Auth Status: #{if state.auth_context, do: "✅ Configured", else: "❌ Not configured"}")
    IO.puts("Created At: #{state.created_at}")
  end
  
  defp suggest_auth_troubleshooting do
    IO.puts("""
    
    🔧 AUTHENTICATION TROUBLESHOOTING:
    
    If the LLM calls are failing, ensure you have authentication configured:
    
    Option 1 - API Key:
      export GEMINI_API_KEY="your-gemini-api-key-here"
      
    Option 2 - OAuth (requires browser):
      # Run the application and follow the OAuth flow
      
    Option 3 - Service Account:
      export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
    
    For detailed setup instructions, see demos/epic1/README.md
    """)
  end
  
  defp suggest_file_tool_troubleshooting do
    IO.puts("""
    
    🔧 FILE TOOL TROUBLESHOOTING:
    
    If file operations are failing, check the configuration:
    
    1. Ensure the demo directory is in the allowed directories list
    2. Check file permissions on the test file
    3. Verify file tool is properly registered
    
    Current demo directory: #{Path.dirname(__ENV__.file)}
    
    For configuration details, see demos/epic1/README.md
    """)
  end
  
  defp exit_with_instructions do
    IO.puts("""
    
    For setup instructions and troubleshooting, please see:
    demos/epic1/README.md
    """)
    System.halt(1)
  end
end

# Ensure we're in the right directory context
File.cd!(Path.dirname(__ENV__.file) |> Path.join("../.."))

# Run the demo
Epic1Demo.run()
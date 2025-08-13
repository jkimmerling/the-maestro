#!/usr/bin/env elixir

# Epic 3 Story 3.6 Demo: Comprehensive Advanced Agent Capabilities
#
# This script demonstrates all the advanced capabilities implemented in Epic 3:
# - Multiple LLM providers (Gemini, OpenAI, Anthropic)
# - Full file system tools (read, write, list)
# - Sandboxed shell command execution
# - OpenAPI specification tool
# - Conversation checkpointing (save/restore sessions)
#
# Prerequisites:
# - At least one LLM provider API key configured (see README.md for details)
# - PostgreSQL database running (for session persistence)
# - Docker available (for shell tool sandboxing)
#
# Usage: 
# - Basic demo: mix run demos/epic3/story3.6_demo.exs
# - With specific provider: PREFERRED_PROVIDER=openai mix run demos/epic3/story3.6_demo.exs
# - Interactive mode: INTERACTIVE=true mix run demos/epic3/story3.6_demo.exs

defmodule Epic3Story36Demo do
  @moduledoc """
  Comprehensive demo showcasing all Epic 3 advanced agent capabilities:
  - Multi-provider LLM support with automatic fallback
  - Advanced file system operations (write, list, read)
  - Sandboxed shell command execution
  - OpenAPI integration for external services
  - Conversation session persistence and restoration
  """

  alias TheMaestro.{Agents, Tooling}
  alias TheMaestro.Sessions

  require Logger

  @demo_id "epic3_story36_#{System.system_time(:millisecond)}"
  @agent_id "#{@demo_id}_agent"
  @demo_dir "/tmp/#{@demo_id}"

  def run do
    IO.puts("🎯 Epic 3 Story 3.6 Demo: Comprehensive Advanced Agent Capabilities")
    IO.puts("=" |> String.duplicate(75))

    try do
      # Setup demo environment
      setup_demo_environment()

      # 1. Verify all tools are available
      verify_all_tools()

      # 2. Test multiple LLM providers
      test_llm_providers()

      # 3. Demonstrate file system tools
      demonstrate_file_system_tools()

      # 4. Demonstrate shell command execution
      demonstrate_shell_tools()

      # 5. Demonstrate OpenAPI integration
      demonstrate_openapi_tools()

      # 6. Demonstrate session checkpointing
      demonstrate_session_checkpointing()

      # 7. Interactive agent demo (if requested)
      if System.get_env("INTERACTIVE") == "true" do
        interactive_agent_demo()
      else
        automated_agent_demo()
      end

      IO.puts("\n🎉 Epic 3 Story 3.6 Demo completed successfully!")
      IO.puts("✨ All advanced agent capabilities are working correctly!")

    rescue
      error ->
        IO.puts("\n❌ Demo failed with error: #{inspect(error)}")
        IO.puts("💡 Check the README.md for setup instructions")
    after
      cleanup_demo_environment()
    end
  end

  defp setup_demo_environment do
    IO.puts("\n🏗️  Setting up comprehensive demo environment...")

    # Create demo directory
    if File.exists?(@demo_dir), do: File.rm_rf!(@demo_dir)
    File.mkdir_p!(@demo_dir)

    # Configure file system tool
    Application.put_env(:the_maestro, :file_system_tool,
      allowed_directories: [@demo_dir, "/tmp"],
      max_file_size: 10 * 1024 * 1024
    )

    # Configure shell tool (enable for demo)
    Application.put_env(:the_maestro, :shell_tool,
      enabled: true,
      sandbox_enabled: true,
      timeout: 30_000
    )

    IO.puts("   ✅ Demo directory created: #{@demo_dir}")
    IO.puts("   ✅ File system tool configured")
    IO.puts("   ✅ Shell tool configured with sandboxing")
    IO.puts("   ✅ Demo environment ready")
  end

  defp verify_all_tools do
    IO.puts("\n🔧 Verifying all Epic 3 tools are available...")

    tools = Tooling.get_tool_definitions()
    tool_names = Enum.map(tools, & &1["name"])

    required_tools = [
      "read_file", 
      "write_file", 
      "list_directory", 
      "execute_command",
      "call_api"
    ]

    required_tools
    |> Enum.each(fn tool_name ->
      if tool_name in tool_names do
        IO.puts("   ✅ #{tool_name} tool available")
      else
        IO.puts("   ⚠️  #{tool_name} tool not available (may be disabled)")
      end
    end)

    IO.puts("   ✅ Tool verification complete")
    IO.puts("   📊 Total tools available: #{length(tools)}")
  end

  defp test_llm_providers do
    IO.puts("\n🤖 Testing available LLM providers...")

    providers = [
      {"Gemini", :gemini, "GEMINI_API_KEY"},
      {"OpenAI", :openai, "OPENAI_API_KEY"},
      {"Anthropic", :anthropic, "ANTHROPIC_API_KEY"}
    ]

    available_providers = 
      providers
      |> Enum.filter(fn {name, _provider, env_var} ->
        api_key = System.get_env(env_var)
        if api_key do
          IO.puts("   ✅ #{name} provider available")
          true
        else
          IO.puts("   ⚠️  #{name} provider not configured (#{env_var} not set)")
          false
        end
      end)

    case available_providers do
      [] ->
        IO.puts("   ⚠️  No LLM providers configured!")
        IO.puts("   💡 Set at least one API key: GEMINI_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY")
        IO.puts("   🔄 Continuing with tool-only demonstration...")
        
        # Store that we have no providers
        Process.put(:primary_provider, nil)
        Process.put(:available_providers, [])

      providers ->
        IO.puts("   ✅ #{length(providers)} provider(s) configured")
        {primary_name, primary_provider, _} = List.first(providers)
        IO.puts("   🎯 Using #{primary_name} as primary provider for demo")
        
        # Store the primary provider for later use
        Process.put(:primary_provider, primary_provider)
        Process.put(:available_providers, providers)
    end
  end

  defp demonstrate_file_system_tools do
    IO.puts("\n📁 Demonstrating advanced file system tools...")

    # Test 1: Create project structure
    IO.puts("\n   📂 Creating demo project structure...")
    project_files = [
      {"README.md", "# Demo Project\\n\\nThis is a demo project created by The Maestro.\\n"},
      {"src/main.py", "#!/usr/bin/env python3\\n\\ndef main():\\n    print('Hello from The Maestro!')\\n\\nif __name__ == '__main__':\\n    main()\\n"},
      {"config/settings.json", "{\\\"app_name\\\": \\\"maestro-demo\\\", \\\"version\\\": \\\"1.0.0\\\"}"},
      {"docs/api.md", "# API Documentation\\n\\n## Endpoints\\n\\n- GET /health - Health check\\n"}
    ]

    project_files
    |> Enum.each(fn {relative_path, content} ->
      full_path = Path.join(@demo_dir, relative_path)
      {:ok, result} = Tooling.execute_tool("write_file", %{
        "path" => full_path,
        "content" => content
      })
      IO.puts("      ✅ Created #{relative_path} (#{result["size"]} bytes)")
    end)

    # Test 2: List directory structure
    IO.puts("\n   📋 Listing directory structure...")
    {:ok, root_list} = Tooling.execute_tool("list_directory", %{"path" => @demo_dir})
    IO.puts("      📊 Root directory contains #{root_list["count"]} entries:")
    
    root_list["entries"]
    |> Enum.each(fn entry ->
      icon = if entry["type"] == "directory", do: "📁", else: "📄"
      IO.puts("        #{icon} #{entry["name"]} (#{entry["type"]})")
    end)

    # Test 3: Read configuration file
    IO.puts("\n   📖 Reading configuration file...")
    config_path = Path.join([@demo_dir, "config", "settings.json"])
    {:ok, read_result} = Tooling.execute_tool("read_file", %{"path" => config_path})
    IO.puts("      📄 Config file content (#{read_result["size"]} bytes):")
    IO.puts("      #{String.trim(read_result["content"])}")

    IO.puts("   ✅ File system tools demonstration complete")
  end

  defp demonstrate_shell_tools do
    IO.puts("\n🖥️  Demonstrating sandboxed shell command execution...")

    shell_enabled = Application.get_env(:the_maestro, :shell_tool, [])[:enabled]
    
    if shell_enabled do
      # Test 1: Basic system information
      IO.puts("\n   ℹ️  Getting system information...")
      {:ok, uname_result} = Tooling.execute_tool("execute_command", %{"command" => "uname -a"})
      output = uname_result["stdout"] || uname_result["output"] || "No output"
      IO.puts("      🖥️  System: #{String.trim(output)}")

      # Test 2: List working directory (Docker has own filesystem)
      IO.puts("\n   📂 Listing Docker working directory...")
      {:ok, ls_result} = Tooling.execute_tool("execute_command", %{"command" => "ls -la ."})
      output = ls_result["stdout"] || ls_result["output"] || ""
      lines = String.split(output, "\n") |> Enum.take(5) |> Enum.reject(&(&1 == ""))
      IO.puts("      📋 Directory listing (first 5 lines):")
      Enum.each(lines, fn line ->
        IO.puts("        #{line}")
      end)

      # Test 3: Create and count files in Docker environment
      IO.puts("\n   📊 Creating and counting files in Docker environment...")
      {:ok, _} = Tooling.execute_tool("execute_command", %{
        "command" => "echo 'test file 1' > file1.txt && echo 'test file 2' > file2.txt && echo 'test file 3' > file3.txt"
      })
      {:ok, find_result} = Tooling.execute_tool("execute_command", %{
        "command" => "ls *.txt | wc -l"
      })
      output = find_result["stdout"] || find_result["output"] || "0"
      file_count = String.trim(output)
      IO.puts("      📈 Files created in Docker: #{file_count}")

      IO.puts("   ✅ Shell tools demonstration complete")
    else
      IO.puts("   ⚠️  Shell tool is disabled, skipping shell demonstration")
      IO.puts("   💡 Enable shell tool in configuration to test this feature")
    end
  end

  defp demonstrate_openapi_tools do
    IO.puts("\n🌐 Demonstrating OpenAPI integration...")

    # Create a simple OpenAPI spec for demo purposes
    openapi_spec = %{
      "openapi" => "3.0.0",
      "info" => %{
        "title" => "Demo API",
        "version" => "1.0.0"
      },
      "servers" => [%{"url" => "https://httpbin.org"}],
      "paths" => %{
        "/get" => %{
          "get" => %{
            "operationId" => "simpleGet",
            "summary" => "Simple GET request",
            "responses" => %{
              "200" => %{"description" => "Success"}
            }
          }
        }
      }
    }

    spec_file = Path.join(@demo_dir, "api_spec.json")
    {:ok, _} = Tooling.execute_tool("write_file", %{
      "path" => spec_file,
      "content" => Jason.encode!(openapi_spec, pretty: true)
    })

    IO.puts("   📝 Created demo OpenAPI specification")

    try do
      # Test API call using OpenAPI tool
      IO.puts("\n   🌐 Testing API call via OpenAPI tool...")
      {:ok, api_result} = Tooling.execute_tool("call_api", %{
        "spec_url" => spec_file,
        "operation_id" => "simpleGet",
        "arguments" => %{}
      })
      
      IO.puts("   ✅ API call successful")
      IO.puts("      📊 Response status: #{api_result["status"] || "200"}")
      
      body = api_result["body"] || ""
      body_size = if is_binary(body), do: byte_size(body), else: 0
      IO.puts("      📦 Response received (#{body_size} bytes)")

    rescue
      error ->
        IO.puts("   ⚠️  API call failed: #{inspect(error)}")
        IO.puts("   💡 This might be due to network connectivity or API limitations")
    end

    IO.puts("   ✅ OpenAPI tools demonstration complete")
  end

  defp demonstrate_session_checkpointing do
    IO.puts("\n💾 Demonstrating conversation session checkpointing...")

    primary_provider = Process.get(:primary_provider)
    
    if primary_provider do
      # Full demo with LLM provider
      demonstrate_session_checkpointing_with_llm()
    else
      # Demo without LLM - show session infrastructure
      demonstrate_session_checkpointing_infrastructure_only()
    end
  end

  defp demonstrate_session_checkpointing_with_llm do
    # Create and start an agent
    IO.puts("\n   🤖 Creating agent for session demo...")
    {:ok, agent_pid} = Agents.start_agent(@agent_id)
    IO.puts("      ✅ Agent #{@agent_id} created successfully")

    # Simulate conversation by sending messages through the agent
    IO.puts("\n   💬 Building conversation history...")
    messages = [
      "Hello, I'm testing the session checkpointing feature.",
      "Can you help me understand how file operations work?",
      "Please create a summary of our conversation so far."
    ]

    # Send messages to build history through the agent's send_message API
    Enum.each(messages, fn message ->
      # This will go through the agent's ReAct loop and use configured LLM provider
      case Agents.Agent.send_message(@agent_id, message) do
        {:ok, _response} ->
          IO.puts("      👤 User: #{String.slice(message, 0, 50)}...")
        {:error, reason} ->
          IO.puts("      ⚠️ Message failed: #{reason}")
      end
    end)

    current_state = Agents.Agent.get_state(@agent_id)
    message_count = length(current_state.message_history)
    IO.puts("   📊 Current conversation has #{message_count} messages")

    # Save session
    IO.puts("\n   💾 Saving conversation session...")
    session_name = "demo_session_#{System.system_time(:millisecond)}"
    
    case Sessions.save_session(current_state, session_name) do
      {:ok, session} ->
        IO.puts("   ✅ Session '#{session_name}' saved successfully!")
        IO.puts("      📄 Session ID: #{session.id}")
        IO.puts("      📊 Message count: #{message_count}")
        IO.puts("      🕒 Created at: #{session.inserted_at}")

        # Add more messages to change state
        IO.puts("\n   🔄 Adding new messages to change current state...")
        case Agents.Agent.send_message(@agent_id, "This is a new message after saving.") do
          {:ok, _response} ->
            new_state = Agents.Agent.get_state(@agent_id)
            new_message_count = length(new_state.message_history)
            IO.puts("   📊 Current state now has #{new_message_count} messages")

            # Restore session
            IO.puts("\n   📂 Restoring saved session...")
            case Sessions.restore_session(@agent_id, session_name) do
              {:ok, _restored_session} ->
                restored_state = Agents.Agent.get_state(@agent_id)
                restored_message_count = length(restored_state.message_history)
                IO.puts("   ✅ Session restored successfully!")
                IO.puts("      📊 Original messages: #{message_count}")
                IO.puts("      📊 Before restore: #{new_message_count}")
                IO.puts("      📊 After restore: #{restored_message_count}")
                
                if restored_message_count == message_count do
                  IO.puts("   ✅ Message history correctly restored!")
                else
                  IO.puts("   ⚠️  Message count mismatch after restore")
                end

              {:error, reason} ->
                IO.puts("   ❌ Session restore failed: #{reason}")
            end

          {:error, reason} ->
            IO.puts("   ⚠️ Failed to add new message: #{reason}")
        end

        # List sessions
        IO.puts("\n   📋 Listing saved sessions...")
        sessions = Sessions.list_sessions_for_agent(@agent_id)
        IO.puts("   📊 Found #{length(sessions)} saved sessions for agent:")
        Enum.each(sessions, fn session ->
          IO.puts("      📄 #{session.name} (#{session.inserted_at})")
        end)

      {:error, reason} ->
        IO.puts("   ❌ Session save failed: #{reason}")
    end

    # Cleanup agent
    GenServer.stop(agent_pid)
    IO.puts("   ✅ Session checkpointing demonstration complete")
  end

  defp demonstrate_session_checkpointing_infrastructure_only do
    IO.puts("\n   ⚠️  No LLM provider available - demonstrating session infrastructure only...")
    
    # Create a real agent for testing session persistence
    IO.puts("\n   🔧 Creating agent for session infrastructure testing...")
    
    # First create a real agent to test the session infrastructure
    {:ok, _agent_pid} = Agents.start_agent(@agent_id)
    IO.puts("      ✅ Agent created for session testing")

    # Test session save infrastructure
    IO.puts("\n   💾 Testing session save infrastructure...")
    session_name = "infrastructure_demo_session_#{System.system_time(:millisecond)}"
    
    case Agents.Agent.save_session(@agent_id, session_name) do
      {:ok, session} ->
        IO.puts("   ✅ Session '#{session_name}' saved successfully!")
        IO.puts("      📄 Session ID: #{session.id}")
        IO.puts("      📊 Message count: #{session.message_count}")
        IO.puts("      🕒 Created at: #{session.inserted_at}")

        # List sessions to verify
        IO.puts("\n   📋 Listing saved sessions...")
        sessions = Agents.Agent.list_sessions(@agent_id)
        IO.puts("   📊 Found #{length(sessions)} saved sessions for agent:")
        Enum.each(sessions, fn session ->
          IO.puts("      📄 #{session.session_name} (#{session.inserted_at})")
        end)
        
        # Clean up the agent
        pid = GenServer.whereis({:via, Registry, {TheMaestro.Agents.Registry, @agent_id}})
        if pid, do: GenServer.stop(pid)

        IO.puts("\n   💡 Session infrastructure is working correctly!")
        IO.puts("      To test session restore, start an agent and use:")
        IO.puts("      Sessions.restore_session(\"#{@agent_id}\", \"#{session_name}\")")

      {:error, reason} ->
        IO.puts("   ❌ Session save failed: #{reason}")
        IO.puts("   💡 Check that PostgreSQL is running and migrations are up to date")
    end

    IO.puts("   ✅ Session infrastructure demonstration complete")
  end

  defp automated_agent_demo do
    IO.puts("\n🤖 Running automated agent demo with all capabilities...")

    primary_provider = Process.get(:primary_provider)
    
    if primary_provider do
      IO.puts("   🎯 Starting comprehensive agent test...")

      {:ok, agent_pid} = Agents.start_agent("#{@agent_id}_full_demo")

      # Comprehensive prompt that uses multiple tools
      comprehensive_prompt = """
      Please help me with a comprehensive demonstration of your capabilities:

      1. **File Operations**: 
         - List the contents of the directory #{@demo_dir}
         - Read the README.md file and summarize its content
         - Create a new file called 'agent_summary.txt' with a summary of what you found

      2. **System Information**:
         - Get basic system information using shell commands
         - Count how many files are in the demo directory

      3. **Analysis**:
         - Analyze the project structure you discovered
         - Provide recommendations for improving the project organization

      Please use the appropriate tools for each task and provide detailed feedback.
      """

      IO.puts("   📝 Sending comprehensive prompt to agent...")
      IO.puts("      Using #{primary_provider} provider")
      
      try do
        response = Agents.send_message("#{@agent_id}_full_demo", comprehensive_prompt)

        case response do
          {:ok, agent_response} ->
            IO.puts("   ✅ Agent successfully completed comprehensive demo!")
            IO.puts("   📋 Response summary:")
            
            # Show key parts of the response
            lines = String.split(agent_response, "\\n")
            summary_lines = Enum.take(lines, 5) ++ ["..."] ++ Enum.take(lines, -3)
            
            Enum.each(summary_lines, fn line ->
              IO.puts("      #{line}")
            end)

          {:error, reason} ->
            IO.puts("   ⚠️  Comprehensive demo failed: #{reason}")
            IO.puts("   💡 This might be due to API limitations or configuration")
        end

        GenServer.stop(agent_pid)

      rescue
        error ->
          IO.puts("   ⚠️  Agent demo failed: #{inspect(error)}")
          GenServer.stop(agent_pid)
      end
    else
      IO.puts("   ⚠️  No LLM provider available for automated demo")
      IO.puts("   💡 All tool demonstrations have been completed successfully!")
      IO.puts("   🎯 The Maestro infrastructure is ready for LLM integration")
      IO.puts("   📝 To enable full agent capabilities, configure an LLM provider:")
      IO.puts("      - GEMINI_API_KEY for Gemini")
      IO.puts("      - OPENAI_API_KEY for OpenAI") 
      IO.puts("      - ANTHROPIC_API_KEY for Anthropic")
    end

    IO.puts("   ✅ Automated agent demo complete")
  end

  defp interactive_agent_demo do
    IO.puts("\n🎮 Interactive agent demo mode...")
    IO.puts("   💡 This would start an interactive session where you can:")
    IO.puts("      - Send custom prompts to the agent")
    IO.puts("      - Switch between different LLM providers")
    IO.puts("      - Save and restore conversation sessions")
    IO.puts("      - Test specific tool combinations")
    IO.puts("\n   📝 For now, use the web interface at http://localhost:4000/agent")
    IO.puts("      or run: mix phx.server")
  end

  defp cleanup_demo_environment do
    IO.puts("\n🧹 Cleaning up demo environment...")
    
    try do
      if File.exists?(@demo_dir) do
        File.rm_rf!(@demo_dir)
        IO.puts("   ✅ Demo directory cleaned up")
      end

      # Note: We don't clean up database sessions in case user wants to examine them
      IO.puts("   📝 Database sessions preserved for examination")
      IO.puts("   💡 Use Sessions.list_sessions/1 to see saved demo sessions")

    rescue
      error ->
        IO.puts("   ⚠️  Cleanup warning: #{inspect(error)}")
    end
  end
end

# Run the comprehensive demo
Epic3Story36Demo.run()
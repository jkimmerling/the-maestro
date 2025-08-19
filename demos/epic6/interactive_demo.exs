#!/usr/bin/env elixir

# Epic 6 Interactive MCP Integration Demo
# This script provides an interactive demonstration of MCP integration

defmodule InteractiveDemo do
  @moduledoc """
  Interactive demonstration module for Epic 6 MCP integration.
  """
  
  def run do
    IO.puts("🤖 The Maestro - Epic 6 Interactive MCP Demo")
    IO.puts("=" |> String.duplicate(45))
    
    show_welcome_message()
    
    if confirm_start() do
      run_interactive_demo()
    else
      IO.puts("👋 Demo cancelled. Goodbye!")
    end
  end
  
  defp show_welcome_message do
    IO.puts("\nWelcome to the interactive MCP integration demonstration!")
    IO.puts("This demo will show you:")
    IO.puts("  📚 Context7 documentation server integration")
    IO.puts("  🔍 Tavily web search server integration")
    IO.puts("  🔐 Security and trust management")
    IO.puts("  🤝 Multi-server coordination")
    IO.puts("  🖥️ CLI management capabilities")
  end
  
  defp confirm_start do
    response = IO.gets("\nWould you like to start the demonstration? (y/n): ")
               |> String.trim()
               |> String.downcase()
    
    response in ["y", "yes"]
  end
  
  defp run_interactive_demo do
    steps = [
      {:environment_check, "Check API keys and environment"},
      {:server_demo, "Demonstrate MCP server connections"},
      {:security_demo, "Show security features"},
      {:tool_demo, "Demonstrate tool execution"},
      {:cli_demo, "Show CLI management tools"}
    ]
    
    IO.puts("\n🚀 Starting interactive demonstration...\n")
    
    for {step_key, step_description} <- steps do
      if confirm_step(step_description) do
        execute_step(step_key)
      else
        IO.puts("⏭️ Skipping: #{step_description}")
      end
      
      IO.puts("")
    end
    
    IO.puts("🎉 Interactive demonstration completed!")
    IO.puts("Thank you for exploring The Maestro MCP integration!")
  end
  
  defp confirm_step(description) do
    response = IO.gets("Execute step: #{description}? (y/n): ")
               |> String.trim()
               |> String.downcase()
    
    response in ["y", "yes"]
  end
  
  defp execute_step(:environment_check) do
    IO.puts("🔍 Checking environment configuration...")
    
    context7_key = System.get_env("CONTEXT7_API_KEY")
    tavily_key = System.get_env("TAVILY_API_KEY")
    
    IO.puts("Context7 API Key: #{if context7_key, do: "✅ Configured", else: "❌ Not set"}")
    IO.puts("Tavily API Key: #{if tavily_key, do: "✅ Configured", else: "❌ Not set"}")
    
    if not context7_key or not tavily_key do
      IO.puts("\n⚠️ Some API keys are missing. Demo will run in simulation mode.")
      IO.puts("To enable full functionality, set these environment variables:")
      if not context7_key, do: IO.puts("  export CONTEXT7_API_KEY=your_key")
      if not tavily_key, do: IO.puts("  export TAVILY_API_KEY=your_key")
    end
    
    wait_for_user()
  end
  
  defp execute_step(:server_demo) do
    IO.puts("📡 Demonstrating MCP server connections...")
    
    servers = [
      %{name: "context7_stdio", transport: "stdio", description: "Documentation server via NPX"},
      %{name: "tavily_http", transport: "http", description: "Web search API server"},
      %{name: "context7_sse", transport: "sse", description: "Documentation server via SSE"}
    ]
    
    IO.puts("Available MCP servers:")
    for server <- servers do
      IO.puts("  📋 #{server.name} (#{server.transport}): #{server.description}")
    end
    
    choice = IO.gets("\nWhich server would you like to learn more about? (context7_stdio/tavily_http/context7_sse): ")
             |> String.trim()
    
    case choice do
      "context7_stdio" ->
        demonstrate_context7_stdio()
      "tavily_http" ->
        demonstrate_tavily_http()
      "context7_sse" ->
        demonstrate_context7_sse()
      _ ->
        IO.puts("Invalid choice. Showing general server information...")
        show_general_server_info()
    end
    
    wait_for_user()
  end
  
  defp execute_step(:security_demo) do
    IO.puts("🔐 Demonstrating security features...")
    
    security_features = [
      "Trust level management",
      "Confirmation flows for untrusted servers", 
      "Parameter sanitization",
      "API key security"
    ]
    
    IO.puts("Security features:")
    for feature <- security_features do
      IO.puts("  🛡️ #{feature}")
    end
    
    IO.puts("\n🎭 Security Scenario Simulation:")
    IO.puts("Imagine you're using Tavily (untrusted) to search for: 'company secrets'")
    
    choice = IO.gets("How should the system respond? (block/confirm/allow): ")
             |> String.trim()
             |> String.downcase()
    
    case choice do
      "block" ->
        IO.puts("✅ Correct! The system should block dangerous queries automatically.")
      "confirm" ->
        IO.puts("✅ Good choice! The system should ask for user confirmation.")
      "allow" ->
        IO.puts("❌ Risky! This could expose sensitive information.")
      _ ->
        IO.puts("The system would require user confirmation for this query.")
    end
    
    wait_for_user()
  end
  
  defp execute_step(:tool_demo) do
    IO.puts("🔧 Demonstrating tool execution...")
    
    available_tools = [
      %{server: "context7", tool: "resolve-library-id", description: "Find library documentation"},
      %{server: "context7", tool: "get-library-docs", description: "Retrieve library docs"},
      %{server: "tavily", tool: "search", description: "Web search"},
      %{server: "tavily", tool: "extract", description: "Extract content from URLs"}
    ]
    
    IO.puts("Available tools:")
    for tool <- available_tools do
      IO.puts("  🔧 #{tool.server}.#{tool.tool}: #{tool.description}")
    end
    
    query = IO.gets("\nWhat would you like to search for? (or press Enter for demo query): ")
            |> String.trim()
    
    query = if query == "", do: "FastAPI async documentation", else: query
    
    IO.puts("🔍 Executing demo query: '#{query}'")
    IO.puts("📋 This would:")
    IO.puts("  1. Use Context7 to resolve library documentation")
    IO.puts("  2. Use Tavily to search for additional information")
    IO.puts("  3. Combine results for comprehensive answer")
    
    wait_for_user()
  end
  
  defp execute_step(:cli_demo) do
    IO.puts("🖥️ Demonstrating CLI management tools...")
    
    cli_commands = [
      "maestro mcp list      - Show configured servers",
      "maestro mcp status    - Show connection status",
      "maestro mcp tools     - List available tools",
      "maestro mcp test      - Test server connections",
      "maestro mcp add       - Add new server",
      "maestro mcp remove    - Remove server"
    ]
    
    IO.puts("Available CLI commands:")
    for command <- cli_commands do
      IO.puts("  💻 #{command}")
    end
    
    choice = IO.gets("\nWhich command would you like to simulate? (list/status/tools): ")
             |> String.trim()
    
    case choice do
      "list" ->
        simulate_mcp_list()
      "status" ->
        simulate_mcp_status()
      "tools" ->
        simulate_mcp_tools()
      _ ->
        IO.puts("Simulating 'maestro mcp list' command...")
        simulate_mcp_list()
    end
    
    wait_for_user()
  end
  
  # Helper functions
  
  defp demonstrate_context7_stdio do
    IO.puts("\n📚 Context7 Stdio Server:")
    IO.puts("  Transport: stdio (subprocess communication)")
    IO.puts("  Command: npx -y @upstash/context7-mcp@latest")
    IO.puts("  Trust Level: Trusted (no confirmations needed)")
    IO.puts("  Tools: resolve-library-id, get-library-docs")
    IO.puts("  Use Case: Documentation lookup and code examples")
  end
  
  defp demonstrate_tavily_http do
    IO.puts("\n🔍 Tavily HTTP Server:")
    IO.puts("  Transport: HTTP (REST API)")
    IO.puts("  URL: https://mcp.tavily.com/mcp")
    IO.puts("  Trust Level: Untrusted (requires confirmation)")
    IO.puts("  Tools: search, extract, crawl")
    IO.puts("  Use Case: Web search and content extraction")
  end
  
  defp demonstrate_context7_sse do
    IO.puts("\n📡 Context7 SSE Server:")
    IO.puts("  Transport: SSE (Server-Sent Events)")
    IO.puts("  URL: https://mcp.context7.dev/sse")
    IO.puts("  Trust Level: Trusted")
    IO.puts("  Tools: resolve-library-id, get-library-docs")
    IO.puts("  Use Case: Real-time documentation streaming")
  end
  
  defp show_general_server_info do
    IO.puts("\nMCP servers extend agent capabilities by providing:")
    IO.puts("  🔧 Tools - Functions the agent can call")
    IO.puts("  📊 Resources - Data the agent can access")  
    IO.puts("  🔄 Real-time communication via different transports")
  end
  
  defp simulate_mcp_list do
    IO.puts("\n📋 MCP Servers (simulated):")
    IO.puts("  ✅ context7_stdio    - Connected (stdio)")
    IO.puts("  ✅ tavily_http       - Connected (http)")
    IO.puts("  ❌ context7_sse      - Disconnected (sse)")
    IO.puts("  ℹ️  filesystem_demo  - Local server (stdio)")
  end
  
  defp simulate_mcp_status do
    IO.puts("\n📊 MCP Status (simulated):")
    IO.puts("  Server Health:")
    IO.puts("    context7_stdio: OK (latency: 150ms)")
    IO.puts("    tavily_http: OK (latency: 300ms)")
    IO.puts("  Total Tools: 8")
    IO.puts("  Active Connections: 2/3")
  end
  
  defp simulate_mcp_tools do
    IO.puts("\n🔧 Available Tools (simulated):")
    IO.puts("  Context7:")
    IO.puts("    📚 resolve-library-id - Find library documentation")
    IO.puts("    📖 get-library-docs - Retrieve documentation")
    IO.puts("  Tavily:")
    IO.puts("    🔍 search - Web search")
    IO.puts("    📄 extract - Content extraction")
    IO.puts("    🕷️ crawl - Website crawling")
  end
  
  defp wait_for_user do
    IO.gets("Press Enter to continue...")
  end
end

# Run the interactive demo
InteractiveDemo.run()
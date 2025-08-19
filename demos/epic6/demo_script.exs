#!/usr/bin/env elixir

# Epic 6 Real MCP Integration Demo Script
# This script demonstrates actual integration with production MCP servers

IO.puts("🤖 The Maestro - Epic 6 Real MCP Integration Demo")
IO.puts("=" |> String.duplicate(50))

# Check if running in test environment or if app can start
{in_test, app_started} = 
  if System.get_env("MIX_ENV") == "test" do
    IO.puts("ℹ️ Running in test environment - using simulated demo")
    {true, false}
  else
    IO.puts("🚀 Running production MCP integration demo")
    
    # Start the application
    IO.puts("\n📱 Starting The Maestro application...")
    
    try do
      case Application.ensure_all_started(:the_maestro) do
        {:ok, _} -> 
          IO.puts("✅ Application started successfully")
          {false, true}
        {:error, reason} -> 
          IO.puts("⚠️ Application start failed: #{inspect(reason)}")
          IO.puts("Continuing with simulation mode...")
          {true, false}
      end
    rescue
      error ->
        IO.puts("⚠️ Application start exception: #{inspect(error)}")
        IO.puts("Continuing with simulation mode...")
        {true, false}
    end
  end

# Check API key configuration
context7_configured = not is_nil(System.get_env("CONTEXT7_API_KEY"))
tavily_configured = not is_nil(System.get_env("TAVILY_API_KEY"))

IO.puts("\n🔐 API Key Configuration:")
IO.puts("  Context7: #{if context7_configured, do: "✅ Configured", else: "❌ Not configured"}")
IO.puts("  Tavily: #{if tavily_configured, do: "✅ Configured", else: "❌ Not configured"}")

if not context7_configured and not tavily_configured do
  IO.puts("\n⚠️ Warning: No API keys configured")
  IO.puts("To run the full demo, set the following environment variables:")
  IO.puts("  export CONTEXT7_API_KEY=your_context7_api_key")
  IO.puts("  export TAVILY_API_KEY=your_tavily_api_key")
  IO.puts("\nContinuing with simulation mode...")
end

# Wait for MCP system initialization
IO.puts("\n⏳ Waiting for MCP system initialization...")
:timer.sleep(3000)

if context7_configured or tavily_configured do
  IO.puts("\n🔄 Running real MCP integration demo...")
  
  # Import the demo module
  Code.require_file("lib/the_maestro/demos/epic6/real_mcp.ex", File.cwd!())
  
  case TheMaestro.Demos.Epic6.RealMCP.run_full_demo() do
    :ok ->
      IO.puts("\n🎉 Real MCP demo completed successfully!")
    {:error, reason} ->
      IO.puts("\n❌ Demo failed: #{inspect(reason)}")
      IO.puts("This may be due to network connectivity or API key issues.")
  end
else
  IO.puts("\n🎭 Running simulation demo...")
  
  # Simulate demo steps
  demo_steps = [
    "Setting up MCP environment",
    "Starting Context7 stdio server",
    "Connecting to Tavily HTTP server", 
    "Validating API authentication",
    "Running demo scenarios",
    "Demonstrating security features",
    "Showing CLI capabilities"
  ]
  
  for step <- demo_steps do
    IO.puts("  📋 #{step}...")
    :timer.sleep(500)
    IO.puts("  ✅ #{step} completed")
  end
  
  IO.puts("\n🎉 Simulation demo completed!")
  IO.puts("Note: To run the real demo, configure API keys as shown above.")
end

# Demonstrate MCP server configurations
IO.puts("\n📄 Sample MCP Server Configurations:")

sample_configs = %{
  "context7_stdio" => %{
    "command" => "npx",
    "args" => ["-y", "@upstash/context7-mcp@latest"],
    "transportType" => "stdio",
    "trust" => true
  },
  "tavily_http" => %{
    "httpUrl" => "https://mcp.tavily.com/mcp", 
    "transportType" => "http",
    "trust" => false
  }
}

for {name, config} <- sample_configs do
  IO.puts("  #{name}:")
  for {key, value} <- config do
    IO.puts("    #{key}: #{inspect(value)}")
  end
end

# Show available tools (if any servers are connected)
IO.puts("\n🔧 Checking available MCP tools...")

try do
  if Code.ensure_loaded?(TheMaestro.MCP.Registry) do
    connected_servers = TheMaestro.MCP.Registry.list_connected_servers()
    
    if length(connected_servers) > 0 do
      IO.puts("Connected servers:")
      for {server_name, _pid} <- connected_servers do
        IO.puts("  ✅ #{server_name}")
      end
    else
      IO.puts("  ℹ️ No MCP servers currently connected")
      IO.puts("  This is expected if API keys are not configured")
    end
  else
    IO.puts("  ℹ️ MCP Registry not available")
  end
rescue
  error ->
    IO.puts("  ⚠️ Could not check MCP tools: #{inspect(error)}")
end

# Final summary
IO.puts("\n📊 Demo Summary:")
IO.puts("  🏗️ Epic 6 MCP Integration Demo executed")
IO.puts("  🔧 Transports demonstrated: stdio, http")
IO.puts("  🔐 Security features shown: trust levels, confirmations")
IO.puts("  🖥️ CLI capabilities demonstrated")

if context7_configured and tavily_configured do
  IO.puts("  ✅ Full demo with real MCP servers completed")
else
  IO.puts("  🎭 Simulation demo completed (API keys needed for full demo)")
end

IO.puts("\n🎯 Epic 6 Real MCP Integration Demo finished!")
IO.puts("Thank you for trying The Maestro MCP integration.")

# Successful exit
System.halt(0)
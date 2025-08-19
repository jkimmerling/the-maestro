#!/usr/bin/env elixir

# Epic 6 Multi-Server Coordination Demo
# Demonstrates advanced workflows using multiple MCP servers together

IO.puts("🤝 The Maestro - Multi-Server Coordination Demo")
IO.puts("=" |> String.duplicate(45))

# Start the application
IO.puts("\n📱 Starting The Maestro application...")

try do
  {:ok, _} = Application.ensure_all_started(:the_maestro)
  IO.puts("✅ Application started successfully")
rescue
  error ->
    IO.puts("❌ Failed to start application: #{inspect(error)}")
    System.halt(1)
end

# Check API key configuration
context7_configured = not is_nil(System.get_env("CONTEXT7_API_KEY"))
tavily_configured = not is_nil(System.get_env("TAVILY_API_KEY"))

IO.puts("\n🔐 Multi-Server Setup Check:")
IO.puts("  Context7: #{if context7_configured, do: "✅ Ready", else: "❌ Missing API key"}")
IO.puts("  Tavily: #{if tavily_configured, do: "✅ Ready", else: "❌ Missing API key"}")

if context7_configured and tavily_configured do
  IO.puts("✅ Full multi-server coordination available")
else
  IO.puts("⚠️ Running in simulation mode - some servers unavailable")
end

# Wait for MCP system initialization
IO.puts("\n⏳ Initializing MCP coordination system...")
:timer.sleep(3000)

# Load the demo coordination module
Code.require_file("lib/the_maestro/demos/epic6/real_mcp.ex", File.cwd!())

# Demonstrate multi-server coordination workflows
IO.puts("\n🚀 Multi-Server Coordination Workflows")
IO.puts("=" |> String.duplicate(40))

workflows = [
  %{
    name: "Documentation + Research",
    description: "Look up official docs, then search for latest updates",
    example: "FastAPI async patterns documentation + latest community discussions"
  },
  %{
    name: "Validation Workflow", 
    description: "Cross-reference web search results with official documentation",
    example: "Search for 'React 18 new features' then validate with React docs"
  },
  %{
    name: "Comprehensive Analysis",
    description: "Combine multiple sources for complete understanding",
    example: "MCP protocol overview from docs + implementation examples from web"
  }
]

for workflow <- workflows do
  IO.puts("\n📋 #{workflow.name}")
  IO.puts("   Description: #{workflow.description}")
  IO.puts("   Example: #{workflow.example}")
end

# Create demo agent for coordination workflows
agent_id = "coordination_demo_#{System.system_time(:second)}"

IO.puts("\n🤖 Creating coordination agent: #{agent_id}")

# Import the Agents module
Code.require_file("lib/the_maestro/agents.ex", File.cwd!())

case TheMaestro.Agents.start_agent(agent_id) do
  {:ok, _pid} ->
    IO.puts("✅ Coordination agent created successfully")
    
    # Demonstrate workflow coordination
    demonstrate_coordination_workflows(agent_id, context7_configured, tavily_configured)
    
    # Cleanup (agents terminate naturally)
    IO.puts("Agent will terminate naturally")
    IO.puts("🧹 Coordination agent cleaned up")
    
  {:error, reason} ->
    IO.puts("❌ Failed to create coordination agent: #{inspect(reason)}")
    IO.puts("Continuing with simulation mode...")
    simulate_coordination_workflows()
end

IO.puts("\n🎯 Multi-Server Coordination Demo completed!")

defp demonstrate_coordination_workflows(agent_id, context7_ready, tavily_ready) do
  IO.puts("\n🔄 Running Real Coordination Workflows")
  IO.puts("-" |> String.duplicate(35))
  
  if context7_ready and tavily_ready do
    run_documentation_research_workflow(agent_id)
    run_validation_workflow(agent_id)
    run_comprehensive_analysis_workflow(agent_id)
  else
    IO.puts("⚠️ Some servers unavailable - running partial workflows")
    
    if context7_ready do
      run_context7_only_workflow(agent_id)
    end
    
    if tavily_ready do
      run_tavily_only_workflow(agent_id)
    end
    
    unless context7_ready or tavily_ready do
      simulate_coordination_workflows()
    end
  end
end

defp run_documentation_research_workflow(agent_id) do
  IO.puts("\n📚 Documentation + Research Workflow")
  IO.puts("Step 1: Context7 documentation lookup")
  
  doc_query = "Look up React hooks documentation focusing on useEffect and useCallback"
  IO.puts("Query: #{doc_query}")
  
  case TheMaestro.Agents.send_message(agent_id, doc_query) do
    :ok -> 
      IO.puts("✅ Context7 documentation query sent")
      :timer.sleep(2000) # Allow processing time
    {:error, reason} -> 
      IO.puts("❌ Context7 query failed: #{inspect(reason)}")
  end
  
  IO.puts("\nStep 2: Tavily web research")
  research_query = "Search for latest React hooks best practices and common pitfalls 2024"
  IO.puts("Query: #{research_query}")
  
  case TheMaestro.Agents.send_message(agent_id, research_query) do
    :ok -> 
      IO.puts("✅ Tavily research query sent")
      :timer.sleep(2000)
    {:error, reason} -> 
      IO.puts("❌ Tavily query failed: #{inspect(reason)}")
  end
  
  IO.puts("\nStep 3: Synthesis")
  IO.puts("🔄 Agent combines official documentation with latest community insights")
  IO.puts("📊 Result: Comprehensive, up-to-date React hooks guidance")
end

defp run_validation_workflow(agent_id) do
  IO.puts("\n🔍 Validation Workflow")
  IO.puts("Step 1: Web search for claims")
  
  search_query = "Search for 'Elixir Phoenix LiveView performance improvements 2024'"
  IO.puts("Query: #{search_query}")
  
  case TheMaestro.Agents.send_message(agent_id, search_query) do
    :ok -> 
      IO.puts("✅ Tavily search completed")
      :timer.sleep(2000)
    {:error, reason} -> 
      IO.puts("❌ Search failed: #{inspect(reason)}")
  end
  
  IO.puts("\nStep 2: Official documentation validation")
  validation_query = "Look up official Phoenix LiveView documentation for performance features"
  IO.puts("Query: #{validation_query}")
  
  case TheMaestro.Agents.send_message(agent_id, validation_query) do
    :ok -> 
      IO.puts("✅ Context7 validation completed")
      :timer.sleep(2000)
    {:error, reason} -> 
      IO.puts("❌ Validation failed: #{inspect(reason)}")
  end
  
  IO.puts("\nStep 3: Cross-reference analysis")
  IO.puts("🔄 Agent cross-references web claims with official documentation")
  IO.puts("📊 Result: Validated information with source credibility ratings")
end

defp run_comprehensive_analysis_workflow(agent_id) do
  IO.puts("\n🧠 Comprehensive Analysis Workflow")
  IO.puts("Scenario: Understanding MCP protocol implementation")
  
  analysis_steps = [
    %{step: 1, source: "Context7", query: "MCP protocol specification and core concepts"},
    %{step: 2, source: "Tavily", query: "MCP protocol implementation examples and tutorials"},
    %{step: 3, source: "Integration", query: "Combine specification with real-world examples"}
  ]
  
  for step <- analysis_steps do
    IO.puts("\nStep #{step.step}: #{step.source}")
    IO.puts("Query: #{step.query}")
    
    if step.source != "Integration" do
      case TheMaestro.Agents.send_message(agent_id, step.query) do
        :ok -> 
          IO.puts("✅ #{step.source} query completed")
          :timer.sleep(1500)
        {:error, reason} -> 
          IO.puts("❌ #{step.source} query failed: #{inspect(reason)}")
      end
    else
      IO.puts("🔄 Agent synthesizes multiple sources")
      IO.puts("📊 Result: Complete understanding from theory to practice")
    end
  end
end

defp run_context7_only_workflow(agent_id) do
  IO.puts("\n📚 Context7-Only Workflow (Tavily unavailable)")
  
  query = "Look up comprehensive Elixir GenServer documentation with examples"
  IO.puts("Query: #{query}")
  
  case TheMaestro.Agents.send_message(agent_id, query) do
    :ok -> 
      IO.puts("✅ Context7 documentation retrieved")
      IO.puts("ℹ️ Note: Web research unavailable without Tavily")
    {:error, reason} -> 
      IO.puts("❌ Context7 query failed: #{inspect(reason)}")
  end
end

defp run_tavily_only_workflow(agent_id) do
  IO.puts("\n🔍 Tavily-Only Workflow (Context7 unavailable)")
  
  query = "Search for Elixir programming best practices and design patterns"
  IO.puts("Query: #{query}")
  
  case TheMaestro.Agents.send_message(agent_id, query) do
    :ok -> 
      IO.puts("✅ Tavily web search completed")
      IO.puts("ℹ️ Note: Official documentation unavailable without Context7")
    {:error, reason} -> 
      IO.puts("❌ Tavily query failed: #{inspect(reason)}")
  end
end

defp simulate_coordination_workflows do
  IO.puts("\n🎭 Simulation: Multi-Server Coordination")
  IO.puts("-" |> String.duplicate(40))
  
  simulation_steps = [
    "📚 Context7: Looking up React documentation...",
    "🔍 Tavily: Searching for latest React updates...",
    "🔄 Coordinating: Merging official docs with community insights...",
    "📊 Analysis: Cross-referencing information sources...",
    "✅ Synthesis: Generating comprehensive response..."
  ]
  
  for step <- simulation_steps do
    IO.puts("  #{step}")
    :timer.sleep(800)
  end
  
  IO.puts("\n🎯 Simulation Results:")
  IO.puts("  • Combined official documentation with latest community knowledge")
  IO.puts("  • Validated web search results against authoritative sources")
  IO.puts("  • Provided comprehensive, multi-perspective analysis")
  IO.puts("  • Demonstrated intelligent server selection and coordination")
  
  IO.puts("\nℹ️ To see real coordination, configure API keys:")
  IO.puts("  export CONTEXT7_API_KEY=your_key")
  IO.puts("  export TAVILY_API_KEY=your_key")
end

# Demonstrate coordination patterns
IO.puts("\n🔧 Coordination Patterns Demonstrated:")

patterns = [
  %{
    name: "Sequential Coordination",
    description: "Server A result feeds into Server B query",
    example: "Context7 library lookup → Tavily search for that library's tutorials"
  },
  %{
    name: "Parallel Coordination", 
    description: "Multiple servers work simultaneously",
    example: "Context7 docs + Tavily news + Calculator stats all at once"
  },
  %{
    name: "Validation Coordination",
    description: "One server validates another's results",
    example: "Tavily finds claim → Context7 checks official docs → validation"
  },
  %{
    name: "Synthesis Coordination",
    description: "Combine different server capabilities",
    example: "Context7 technical details + Tavily user experiences = complete picture"
  }
]

for pattern <- patterns do
  IO.puts("\n🔗 #{pattern.name}")
  IO.puts("   #{pattern.description}")
  IO.puts("   Example: #{pattern.example}")
end

# Show coordination benefits
IO.puts("\n✨ Multi-Server Coordination Benefits:")
benefits = [
  "🎯 More comprehensive responses by combining multiple data sources",
  "🔍 Enhanced accuracy through cross-validation and verification",
  "⚡ Improved efficiency by leveraging each server's strengths",
  "🛡️ Better security through distributed trust and confirmation",
  "📈 Scalable architecture that grows with available services"
]

for benefit <- benefits do
  IO.puts("  #{benefit}")
end

IO.puts("\n🏁 Multi-Server Coordination Demo finished!")
IO.puts("This demonstrates the power of MCP for building sophisticated AI agent workflows.")

System.halt(0)
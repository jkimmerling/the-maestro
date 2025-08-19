defmodule TheMaestro.Prompts.InstructionModulesTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.SystemInstructions.Modules.{
    CoreMandates,
    ToolIntegration,
    SecurityGuidelines,
    ContextAwareness,
    CapabilityDescription,
    WorkflowGuidance,
    ProviderOptimization
  }

  describe "CoreMandates module" do
    test "generates core operational principles" do
      mandates = CoreMandates.generate()

      assert is_binary(mandates)
      assert String.contains?(mandates, "You are an interactive CLI agent")
      assert String.contains?(mandates, "Conventions")
      assert String.contains?(mandates, "NEVER assume a library/framework")
      assert String.contains?(mandates, "absolute paths")
      assert String.contains?(mandates, "Proactiveness")
    end

    test "includes security consciousness" do
      mandates = CoreMandates.generate()

      assert String.contains?(mandates, "Security First")
      assert String.contains?(mandates, "never expose")
      assert String.contains?(mandates, "secrets")
    end
  end

  describe "ToolIntegration module" do
    test "generates tool instructions for multiple tools" do
      tools = [
        %{name: "read_file", description: "Read file contents", usage: "Use to examine code"},
        %{name: "write_file", description: "Write file contents", usage: "Use to create/modify files"},
        %{name: "execute_command", description: "Execute shell commands", usage: "Use for testing and building"}
      ]

      instructions = ToolIntegration.generate(tools)

      assert is_binary(instructions)
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "read_file")
      assert String.contains?(instructions, "write_file")
      assert String.contains?(instructions, "execute_command")
      assert String.contains?(instructions, "Tool Usage Guidelines")
      assert String.contains?(instructions, "Parallelism")
    end

    test "handles empty tool list gracefully" do
      instructions = ToolIntegration.generate([])

      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "No tools currently available")
    end

    test "formats tool descriptions correctly" do
      tools = [
        %{name: "test_tool", description: "Test description", usage: "Test usage"}
      ]

      instructions = ToolIntegration.generate(tools)

      assert String.contains?(instructions, "**test_tool**")
      assert String.contains?(instructions, "Test description")
      assert String.contains?(instructions, "Test usage")
    end

    test "includes tool usage guidelines" do
      tools = [%{name: "read_file", description: "Read files"}]

      instructions = ToolIntegration.generate(tools)

      assert String.contains?(instructions, "Execute multiple independent tool calls in parallel")
      assert String.contains?(instructions, "Always use absolute paths")
      assert String.contains?(instructions, "Handle tool errors gracefully")
    end
  end

  describe "SecurityGuidelines module" do
    test "generates security guidelines for sandboxed environment" do
      context = %{sandbox_enabled: true, trust_level: :medium}

      guidelines = SecurityGuidelines.generate(context)

      assert String.contains?(guidelines, "Security and Safety Rules")
      assert String.contains?(guidelines, "sandboxed environment")
      assert String.contains?(guidelines, "Explain Critical Commands")
      assert String.contains?(guidelines, "Security First")
    end

    test "generates security guidelines for production environment" do
      context = %{sandbox_enabled: false, trust_level: :high}

      guidelines = SecurityGuidelines.generate(context)

      assert String.contains?(guidelines, "production environment")
      assert String.contains?(guidelines, "Security First")
    end

    test "adapts to different trust levels" do
      low_trust = %{sandbox_enabled: false, trust_level: :low}
      high_trust = %{sandbox_enabled: false, trust_level: :high}

      low_trust_guidelines = SecurityGuidelines.generate(low_trust)
      high_trust_guidelines = SecurityGuidelines.generate(high_trust)

      # Low trust should have more restrictive language
      assert String.length(low_trust_guidelines) >= String.length(high_trust_guidelines)
      assert String.contains?(low_trust_guidelines, "additional verification")
    end
  end

  describe "ContextAwareness module" do
    test "generates environmental context information" do
      context = %{
        current_date: "2025-01-19",
        operating_system: "Darwin",
        working_directory: "/Users/test/project",
        available_tools: [:read_file, :write_file],
        connected_mcp_servers: [:context7, :sequential],
        sandbox_enabled: false,
        project_type: :elixir
      }

      env_context = ContextAwareness.generate(context)

      assert String.contains?(env_context, "Current Environment")
      assert String.contains?(env_context, "2025-01-19")
      assert String.contains?(env_context, "Darwin")
      assert String.contains?(env_context, "/Users/test/project")
      assert String.contains?(env_context, "2 tools")
      assert String.contains?(env_context, "context7, sequential")
      assert String.contains?(env_context, "elixir")
    end

    test "includes project structure when available" do
      context = %{
        current_date: "2025-01-19",
        working_directory: "/test/project",
        project_structure: [
          "lib/",
          "test/",
          "mix.exs"
        ]
      }

      env_context = ContextAwareness.generate(context)

      assert String.contains?(env_context, "Project Structure")
      assert String.contains?(env_context, "lib/")
      assert String.contains?(env_context, "test/")
      assert String.contains?(env_context, "mix.exs")
    end
  end

  describe "CapabilityDescription module" do
    test "generates capability description" do
      agent_state = %{
        current_provider: :anthropic,
        current_model: "claude-3-5-sonnet-20241022",
        file_access_level: :full,
        command_execution_level: :restricted,
        available_mcp_tools: [:context7, :sequential],
        auth_status: :authenticated,
        limitations: ["No internet access", "Cannot modify system files"]
      }

      capabilities = CapabilityDescription.generate(agent_state)

      assert String.contains?(capabilities, "Your Current Capabilities")
      assert String.contains?(capabilities, "Core Functions")
      assert String.contains?(capabilities, "anthropic")
      assert String.contains?(capabilities, "claude-3-5-sonnet-20241022")
      assert String.contains?(capabilities, "context7")
      assert String.contains?(capabilities, "sequential")
      assert String.contains?(capabilities, "Current Limitations")
      assert String.contains?(capabilities, "No internet access")
    end

    test "adapts to different access levels" do
      full_access = %{
        file_access_level: :full,
        command_execution_level: :full,
        current_provider: :anthropic,
        current_model: "claude"
      }

      restricted_access = %{
        file_access_level: :read_only,
        command_execution_level: :none,
        current_provider: :anthropic,
        current_model: "claude"
      }

      full_capabilities = CapabilityDescription.generate(full_access)
      restricted_capabilities = CapabilityDescription.generate(restricted_access)

      assert String.contains?(full_capabilities, "full file system access")
      assert String.contains?(restricted_capabilities, "read-only file access")
      assert String.contains?(restricted_capabilities, "no command execution")
    end
  end

  describe "WorkflowGuidance module" do
    test "generates software engineering workflow" do
      task_context = %{
        primary_task_type: :software_engineering,
        complexity_level: :moderate,
        available_tools: [:read_file, :write_file, :execute_command]
      }

      workflow = WorkflowGuidance.generate(task_context)

      assert String.contains?(workflow, "Software Engineering Tasks")
      assert String.contains?(workflow, "Understand")
      assert String.contains?(workflow, "Plan")
      assert String.contains?(workflow, "Implement")
      assert String.contains?(workflow, "Verify (Tests)")
      assert String.contains?(workflow, "Verify (Standards)")
    end

    test "generates new application workflow" do
      task_context = %{
        primary_task_type: :new_application,
        complexity_level: :high
      }

      workflow = WorkflowGuidance.generate(task_context)

      assert String.contains?(workflow, "New Application Development")
      assert String.contains?(workflow, "visually appealing")
      assert String.contains?(workflow, "Understand Requirements")
      assert String.contains?(workflow, "Propose Plan")
      assert String.contains?(workflow, "User Approval")
      assert String.contains?(workflow, "Implementation")
    end

    test "generates debugging workflow" do
      task_context = %{
        primary_task_type: :debugging,
        complexity_level: :high
      }

      workflow = WorkflowGuidance.generate(task_context)

      assert String.contains?(workflow, "Debugging Tasks")
      assert String.contains?(workflow, "Reproduce")
      assert String.contains?(workflow, "Investigate")
      assert String.contains?(workflow, "Root Cause")
    end

    test "generates generic workflow for unknown task types" do
      task_context = %{
        primary_task_type: :unknown,
        complexity_level: :moderate
      }

      workflow = WorkflowGuidance.generate(task_context)

      assert String.contains?(workflow, "General Task Workflow")
      assert String.contains?(workflow, "Analyze")
      assert String.contains?(workflow, "Execute")
      assert String.contains?(workflow, "Validate")
    end
  end

  describe "ProviderOptimization module" do
    test "generates Claude-specific optimizations" do
      optimizations = ProviderOptimization.generate(:anthropic, "claude-3-5-sonnet-20241022")

      assert String.contains?(optimizations, "Claude-Specific Optimizations")
      assert String.contains?(optimizations, "reasoning capabilities")
      assert String.contains?(optimizations, "code understanding")
      assert String.contains?(optimizations, "context window")
      assert String.contains?(optimizations, "structured thinking")
    end

    test "generates Gemini-specific optimizations" do
      optimizations = ProviderOptimization.generate(:google, "gemini-pro")

      assert String.contains?(optimizations, "Gemini-Specific Optimizations")
      assert String.contains?(optimizations, "multimodal capabilities")
      assert String.contains?(optimizations, "integrated search")
      assert String.contains?(optimizations, "function calling")
    end

    test "generates GPT-specific optimizations" do
      optimizations = ProviderOptimization.generate(:openai, "gpt-4")

      assert String.contains?(optimizations, "GPT-Specific Optimizations")
      assert String.contains?(optimizations, "general reasoning")
      assert String.contains?(optimizations, "natural language understanding")
      assert String.contains?(optimizations, "structured outputs")
    end

    test "returns empty string for unknown providers" do
      optimizations = ProviderOptimization.generate(:unknown_provider, "unknown-model")

      assert optimizations == ""
    end

    test "handles various model versions correctly" do
      claude_optimizations = ProviderOptimization.generate(:anthropic, "claude-3-haiku-20240307")
      gpt_optimizations = ProviderOptimization.generate(:openai, "gpt-3.5-turbo")
      gemini_optimizations = ProviderOptimization.generate(:google, "gemini-1.5-pro")

      assert String.contains?(claude_optimizations, "Claude-Specific")
      assert String.contains?(gpt_optimizations, "GPT-Specific")
      assert String.contains?(gemini_optimizations, "Gemini-Specific")
    end
  end

  describe "module integration" do
    test "all modules can be loaded and called" do
      modules = [
        {CoreMandates, []},
        {ToolIntegration, [[]]},
        {SecurityGuidelines, [%{sandbox_enabled: false, trust_level: :medium}]},
        {ContextAwareness, [%{current_date: "2025-01-19", working_directory: "/test"}]},
        {CapabilityDescription, [%{current_provider: :anthropic, current_model: "claude"}]},
        {WorkflowGuidance, [%{primary_task_type: :software_engineering}]},
        {ProviderOptimization, [:anthropic, "claude-3-5-sonnet-20241022"]}
      ]

      for {module, args} <- modules do
        result = apply(module, :generate, args)
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end
  end
end
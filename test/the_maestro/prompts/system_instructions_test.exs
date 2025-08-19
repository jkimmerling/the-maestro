defmodule TheMaestro.Prompts.SystemInstructionsTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.SystemInstructions
  alias TheMaestro.Prompts.SystemInstructions.{
    AssemblyContext,
    TaskContext,
    InstructionAssembler
  }

  describe "instruction module constants" do
    test "defines all required instruction modules" do
      expected_modules = [
        :core_mandates,
        :tool_integration,
        :security_guidelines,
        :context_awareness,
        :provider_optimization,
        :capability_description,
        :workflow_guidance,
        :error_handling,
        :output_formatting
      ]

      assert SystemInstructions.instruction_modules() == expected_modules
    end
  end

  describe "assemble_system_instructions/1" do
    setup do
      context = %{
        available_tools: [:read_file, :write_file, :execute_command],
        connected_mcp_servers: [:context7, :sequential],
        environment: %{
          current_date: "2025-01-19",
          operating_system: "Darwin",
          working_directory: "/Users/test/project",
          sandbox_enabled: false
        },
        provider_info: %{
          provider: :anthropic,
          model: "claude-3-5-sonnet-20241022"
        },
        security_context: %{
          trust_level: :medium,
          sandbox_mode: false
        },
        task_type: :software_engineering
      }

      {:ok, context: context}
    end

    test "assembles complete system instructions", %{context: context} do
      instructions = SystemInstructions.assemble_system_instructions(context)

      assert is_binary(instructions)
      assert String.contains?(instructions, "You are an interactive CLI agent")
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "Security and Safety Rules")
    end

    test "includes provider-specific optimizations", %{context: context} do
      instructions = SystemInstructions.assemble_system_instructions(context)

      assert String.contains?(instructions, "Claude-Specific Optimizations")
      assert String.contains?(instructions, "reasoning capabilities")
    end

    test "adapts to different task types", %{context: context} do
      context_new_app = Map.put(context, :task_type, :new_application)
      instructions = SystemInstructions.assemble_system_instructions(context_new_app)

      assert String.contains?(instructions, "New Application Development")
      assert String.contains?(instructions, "visually appealing")
    end

    test "filters instructions based on available tools", %{context: context} do
      limited_context = Map.put(context, :available_tools, [:read_file])
      instructions = SystemInstructions.assemble_system_instructions(limited_context)

      assert String.contains?(instructions, "read_file")
      refute String.contains?(instructions, "execute_command")
    end
  end

  describe "core mandates module" do
    test "generates core mandates instructions" do
      mandates = SystemInstructions.generate_core_mandates()

      assert is_binary(mandates)
      assert String.contains?(mandates, "Conventions")
      assert String.contains?(mandates, "NEVER assume a library/framework")
      assert String.contains?(mandates, "absolute paths")
    end
  end

  describe "tool integration module" do
    test "generates tool instructions for available tools" do
      tools = [
        %{name: "read_file", description: "Read file contents"},
        %{name: "write_file", description: "Write file contents"}
      ]

      instructions = SystemInstructions.generate_tool_instructions(tools)

      assert is_binary(instructions)
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "read_file")
      assert String.contains?(instructions, "write_file")
      assert String.contains?(instructions, "Tool Usage Guidelines")
    end

    test "handles empty tool list" do
      instructions = SystemInstructions.generate_tool_instructions([])

      assert is_binary(instructions)
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "No tools currently available")
    end
  end

  describe "security guidelines module" do
    test "generates security guidelines with sandbox status" do
      context = %{sandbox_enabled: true}
      guidelines = SystemInstructions.generate_security_guidelines(context)

      assert is_binary(guidelines)
      assert String.contains?(guidelines, "Security and Safety Rules")
      assert String.contains?(guidelines, "Sandboxing Awareness")
      assert String.contains?(guidelines, "sandboxed environment")
    end

    test "adapts to non-sandbox environment" do
      context = %{sandbox_enabled: false}
      guidelines = SystemInstructions.generate_security_guidelines(context)

      assert String.contains?(guidelines, "production environment")
    end
  end

  describe "environmental context module" do
    test "generates environmental context information" do
      context = %{
        current_date: "2025-01-19",
        operating_system: "Darwin",
        working_directory: "/Users/test/project",
        available_tools: [:read_file, :write_file],
        connected_mcp_servers: [:context7]
      }

      env_context = SystemInstructions.generate_environmental_context(context)

      assert is_binary(env_context)
      assert String.contains?(env_context, "Current Environment")
      assert String.contains?(env_context, "2025-01-19")
      assert String.contains?(env_context, "Darwin")
      assert String.contains?(env_context, "/Users/test/project")
      assert String.contains?(env_context, "2 tools")
      assert String.contains?(env_context, "context7")
    end
  end

  describe "capability description module" do
    test "generates capability description" do
      agent_state = %{
        current_provider: :anthropic,
        current_model: "claude-3-5-sonnet-20241022",
        file_access_level: :full,
        command_execution_level: :restricted,
        available_mcp_tools: [:context7, :sequential],
        auth_status: :authenticated
      }

      capabilities = SystemInstructions.generate_capability_description(agent_state)

      assert is_binary(capabilities)
      assert String.contains?(capabilities, "Your Current Capabilities")
      assert String.contains?(capabilities, "anthropic")
      assert String.contains?(capabilities, "claude-3-5-sonnet-20241022")
      assert String.contains?(capabilities, "context7")
    end
  end

  describe "workflow guidance module" do
    test "generates software engineering workflow instructions" do
      task_context = %{primary_task_type: :software_engineering}
      workflow = SystemInstructions.generate_workflow_instructions(task_context)

      assert is_binary(workflow)
      assert String.contains?(workflow, "Software Engineering Tasks")
      assert String.contains?(workflow, "Understand")
      assert String.contains?(workflow, "Plan")
      assert String.contains?(workflow, "Implement")
      assert String.contains?(workflow, "Verify")
    end

    test "generates new application workflow instructions" do
      task_context = %{primary_task_type: :new_application}
      workflow = SystemInstructions.generate_workflow_instructions(task_context)

      assert String.contains?(workflow, "New Application Development")
      assert String.contains?(workflow, "visually appealing")
      assert String.contains?(workflow, "User Approval")
    end
  end

  describe "provider optimization module" do
    test "generates Claude-specific optimizations" do
      optimizations = SystemInstructions.generate_provider_optimizations(:anthropic, "claude-3-5-sonnet-20241022")

      assert is_binary(optimizations)
      assert String.contains?(optimizations, "Claude-Specific Optimizations")
      assert String.contains?(optimizations, "reasoning capabilities")
      assert String.contains?(optimizations, "context window")
    end

    test "generates Gemini-specific optimizations" do
      optimizations = SystemInstructions.generate_provider_optimizations(:google, "gemini-pro")

      assert String.contains?(optimizations, "Gemini-Specific Optimizations")
      assert String.contains?(optimizations, "multimodal capabilities")
    end

    test "generates GPT-specific optimizations" do
      optimizations = SystemInstructions.generate_provider_optimizations(:openai, "gpt-4")

      assert String.contains?(optimizations, "GPT-Specific Optimizations")
      assert String.contains?(optimizations, "general reasoning")
    end

    test "returns empty string for unknown providers" do
      optimizations = SystemInstructions.generate_provider_optimizations(:unknown, "unknown-model")

      assert optimizations == ""
    end
  end

  describe "InstructionAssembler" do
    test "creates assembly context from input context" do
      input_context = %{
        available_tools: [:read_file],
        connected_mcp_servers: [:context7],
        environment: %{current_date: "2025-01-19"},
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        security_context: %{trust_level: :medium}
      }

      assembly_context = InstructionAssembler.create_assembly_context(input_context)

      assert %AssemblyContext{} = assembly_context
      assert assembly_context.available_tools == [:read_file]
      assert assembly_context.mcp_servers == [:context7]
      assert assembly_context.provider_info.provider == :anthropic
    end

    test "assembles instructions with all modules" do
      input_context = %{
        available_tools: [:read_file, :write_file],
        connected_mcp_servers: [:context7],
        environment: %{
          current_date: "2025-01-19",
          operating_system: "Darwin",
          working_directory: "/test",
          sandbox_enabled: false
        },
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"},
        security_context: %{trust_level: :medium},
        task_type: :software_engineering
      }

      assembly_context = InstructionAssembler.create_assembly_context(input_context)
      instructions = InstructionAssembler.assemble_instructions(assembly_context)

      assert is_binary(instructions)
      
      # Verify all sections are present
      assert String.contains?(instructions, "You are an interactive CLI agent")
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "Security and Safety Rules")
      assert String.contains?(instructions, "Current Environment")
      assert String.contains?(instructions, "Your Current Capabilities")
      assert String.contains?(instructions, "Software Engineering Tasks")
      assert String.contains?(instructions, "Claude-Specific Optimizations")
    end
  end

  describe "context analysis" do
    test "analyzes task context correctly" do
      context = %{
        user_request: "Fix the authentication bug in the login system",
        available_tools: [:read_file, :write_file, :execute_command],
        project_complexity: :moderate,
        time_constraints: :normal,
        risk_factors: [:security_sensitive]
      }

      task_context = SystemInstructions.analyze_task_context(context)

      assert %TaskContext{} = task_context
      assert task_context.primary_task_type == :software_engineering
      assert task_context.complexity_level == :moderate
      assert task_context.risk_level == :medium
    end

    test "identifies new application development context" do
      context = %{
        user_request: "Create a new React app for task management",
        available_tools: [:read_file, :write_file],
        project_complexity: :high,
        time_constraints: :flexible
      }

      task_context = SystemInstructions.analyze_task_context(context)

      assert task_context.primary_task_type == :new_application
      assert task_context.complexity_level == :high
    end
  end

  describe "instruction optimization" do
    test "optimizes instruction length when over budget" do
      long_instructions = String.duplicate("This is a long instruction. ", 1000)
      token_budget = 5000

      optimized = SystemInstructions.optimize_instructions_for_length(long_instructions, token_budget)

      assert byte_size(optimized) < byte_size(long_instructions)
      assert String.contains?(optimized, "This is a long instruction")
    end

    test "filters irrelevant instruction modules" do
      context = %{
        task_type: :software_engineering,
        available_tools: [:read_file],
        requires_security: false,
        provider: :anthropic
      }

      filtered_modules = SystemInstructions.filter_relevant_modules(context)

      assert :core_mandates in filtered_modules
      assert :tool_integration in filtered_modules
      assert :workflow_guidance in filtered_modules
      assert :provider_optimization in filtered_modules
    end
  end

  describe "caching and performance" do
    test "caches static instruction components" do
      # First call should generate and cache
      mandates1 = SystemInstructions.get_cached_core_mandates()
      # Second call should return cached version
      mandates2 = SystemInstructions.get_cached_core_mandates()

      assert mandates1 == mandates2
      # Verify cache was used by checking process dictionary or cache store
      assert :ok == SystemInstructions.verify_cache_hit(:core_mandates)
    end

    test "invalidates cache when context changes significantly" do
      context1 = %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      context2 = %{provider: :google, model: "gemini-pro"}

      # Generate instructions for first context
      instructions1 = SystemInstructions.assemble_system_instructions(context1)
      
      # Generate instructions for second context
      instructions2 = SystemInstructions.assemble_system_instructions(context2)

      # Should be different due to provider optimization differences
      refute instructions1 == instructions2
    end
  end

  describe "error handling" do
    test "handles empty context gracefully" do
      empty_context = %{}
      
      # Should not raise an error, but return basic instructions
      instructions = SystemInstructions.assemble_system_instructions(empty_context)
      
      assert is_binary(instructions)
      assert String.contains?(instructions, "Core Mandates")
    end

    test "handles invalid tool descriptions" do
      invalid_tools = [
        %{name: nil, description: "Invalid tool"},
        %{description: "Tool without name"}
      ]

      instructions = SystemInstructions.generate_tool_instructions(invalid_tools)
      
      # Should handle gracefully and skip invalid tools
      assert is_binary(instructions)
      assert String.contains?(instructions, "Available Tools")
    end
  end
end
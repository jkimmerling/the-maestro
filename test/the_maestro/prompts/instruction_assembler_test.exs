defmodule TheMaestro.Prompts.InstructionAssemblerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.SystemInstructions.{
    InstructionAssembler,
    AssemblyContext,
    TaskContext
  }

  describe "create_assembly_context/1" do
    test "creates assembly context with all required fields" do
      input = %{
        available_tools: [:read_file, :write_file],
        connected_mcp_servers: [:context7, :sequential],
        environment: %{
          current_date: "2025-01-19",
          operating_system: "Darwin",
          working_directory: "/test/project",
          sandbox_enabled: false
        },
        provider_info: %{
          provider: :anthropic,
          model: "claude-3-5-sonnet-20241022"
        },
        security_context: %{
          trust_level: :high,
          sandbox_mode: false
        },
        task_type: :software_engineering
      }

      context = InstructionAssembler.create_assembly_context(input)

      assert %AssemblyContext{} = context
      assert context.available_tools == [:read_file, :write_file]
      assert context.mcp_servers == [:context7, :sequential]
      assert context.environment.current_date == "2025-01-19"
      assert context.provider_info.provider == :anthropic
      assert context.security_context.trust_level == :high
      assert %TaskContext{} = context.task_context
    end

    test "defaults missing optional fields" do
      minimal_input = %{
        available_tools: [],
        environment: %{current_date: "2025-01-19"}
      }

      context = InstructionAssembler.create_assembly_context(minimal_input)

      assert context.mcp_servers == []
      assert context.provider_info.provider == :unknown
      assert context.security_context.trust_level == :medium
    end
  end

  describe "assemble_instructions/1" do
    setup do
      context = %AssemblyContext{
        base_instructions: TheMaestro.Prompts.SystemInstructions.Modules.CoreMandates.generate(),
        available_tools: [
          %{name: "read_file", description: "Read file contents"},
          %{name: "write_file", description: "Write file contents"}
        ],
        mcp_servers: [:context7],
        environment: %{
          current_date: "2025-01-19",
          operating_system: "Darwin",
          working_directory: "/test/project",
          sandbox_enabled: false
        },
        task_context: %TaskContext{
          primary_task_type: :software_engineering,
          complexity_level: :moderate,
          required_capabilities: [:file_operations],
          time_sensitivity: :normal,
          risk_level: :low,
          collaboration_mode: :autonomous
        },
        provider_info: %{
          provider: :anthropic,
          model: "claude-3-5-sonnet-20241022"
        },
        security_context: %{
          trust_level: :high,
          sandbox_mode: false
        }
      }

      {:ok, context: context}
    end

    test "assembles complete instructions with all modules", %{context: context} do
      instructions = InstructionAssembler.assemble_instructions(context)

      assert is_binary(instructions)
      
      # Check for presence of all expected sections
      assert String.contains?(instructions, "Core Mandates")
      assert String.contains?(instructions, "Available Tools")
      assert String.contains?(instructions, "read_file")
      assert String.contains?(instructions, "write_file")
      assert String.contains?(instructions, "Security and Safety Rules")
      assert String.contains?(instructions, "Current Environment")
      assert String.contains?(instructions, "2025-01-19")
      assert String.contains?(instructions, "Your Current Capabilities")
      assert String.contains?(instructions, "Software Engineering Tasks")
      assert String.contains?(instructions, "Claude-Specific Optimizations")
    end

    test "respects module order in assembly", %{context: context} do
      instructions = InstructionAssembler.assemble_instructions(context)

      # Core mandates should come first
      core_pos = String.length(instructions) - String.length(String.split(instructions, "Base instructions", parts: 2) |> List.last())
      tools_pos = String.length(instructions) - String.length(String.split(instructions, "Available Tools", parts: 2) |> List.last())
      security_pos = String.length(instructions) - String.length(String.split(instructions, "Security and Safety Rules", parts: 2) |> List.last())

      assert core_pos < tools_pos
      assert tools_pos < security_pos
    end

    test "skips modules when not relevant", %{context: context} do
      # Remove tools to test conditional inclusion
      context_no_tools = %{context | available_tools: []}
      instructions = InstructionAssembler.assemble_instructions(context_no_tools)

      assert String.contains?(instructions, "No tools currently available")
    end
  end

  describe "add_tool_integration_instructions/1" do
    test "adds tool instructions when tools are available" do
      context = %AssemblyContext{
        available_tools: [
          %{name: "read_file", description: "Read file contents"},
          %{name: "execute_command", description: "Execute shell commands"}
        ]
      }

      updated_context = InstructionAssembler.add_tool_integration_instructions(context)

      assert String.contains?(updated_context.assembled_instructions, "Available Tools")
      assert String.contains?(updated_context.assembled_instructions, "read_file")
      assert String.contains?(updated_context.assembled_instructions, "execute_command")
      assert String.contains?(updated_context.assembled_instructions, "Tool Usage Guidelines")
    end

    test "handles empty tool list" do
      context = %AssemblyContext{available_tools: []}

      updated_context = InstructionAssembler.add_tool_integration_instructions(context)

      assert String.contains?(updated_context.assembled_instructions, "No tools currently available")
    end
  end

  describe "add_security_guidelines/1" do
    test "adds security guidelines with sandbox awareness" do
      context = %AssemblyContext{
        security_context: %{trust_level: :medium, sandbox_mode: true},
        environment: %{sandbox_enabled: true}
      }

      updated_context = InstructionAssembler.add_security_guidelines(context)

      assert String.contains?(updated_context.assembled_instructions, "Security and Safety Rules")
      assert String.contains?(updated_context.assembled_instructions, "sandboxed environment")
    end

    test "adapts guidelines to trust level" do
      high_trust_context = %AssemblyContext{
        security_context: %{trust_level: :high, sandbox_mode: false}
      }
      low_trust_context = %AssemblyContext{
        security_context: %{trust_level: :low, sandbox_mode: false}
      }

      high_trust_updated = InstructionAssembler.add_security_guidelines(high_trust_context)
      low_trust_updated = InstructionAssembler.add_security_guidelines(low_trust_context)

      # Low trust should have more restrictive guidelines
      assert String.length(low_trust_updated.assembled_instructions) >= String.length(high_trust_updated.assembled_instructions)
    end
  end

  describe "add_provider_optimizations/1" do
    test "adds Claude-specific optimizations" do
      context = %AssemblyContext{
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      }

      updated_context = InstructionAssembler.add_provider_optimizations(context)

      assert String.contains?(updated_context.assembled_instructions, "Claude-Specific Optimizations")
      assert String.contains?(updated_context.assembled_instructions, "reasoning capabilities")
    end

    test "adds Gemini-specific optimizations" do
      context = %AssemblyContext{
        provider_info: %{provider: :google, model: "gemini-pro"}
      }

      updated_context = InstructionAssembler.add_provider_optimizations(context)

      assert String.contains?(updated_context.assembled_instructions, "Gemini-Specific Optimizations")
      assert String.contains?(updated_context.assembled_instructions, "multimodal capabilities")
    end

    test "skips optimizations for unknown providers" do
      context = %AssemblyContext{
        provider_info: %{provider: :unknown, model: "unknown-model"}
      }

      updated_context = InstructionAssembler.add_provider_optimizations(context)

      refute String.contains?(updated_context.assembled_instructions, "Specific Optimizations")
    end
  end

  describe "finalize_assembly/1" do
    test "validates instruction completeness" do
      context = %AssemblyContext{
        assembled_instructions: """
        You are an interactive CLI agent.
        
        ## Available Tools
        - read_file: Read file contents
        
        ## Security and Safety Rules
        - Always explain critical commands
        
        ## Current Environment
        - Date: 2025-01-19
        
        ## Your Current Capabilities
        - File operations
        
        ## Software Engineering Tasks
        - Follow TDD practices
        """,
        validation_errors: []
      }

      final_instructions = InstructionAssembler.finalize_assembly(context)

      assert is_binary(final_instructions)
      assert String.contains?(final_instructions, "You are an interactive CLI agent")
    end

    test "raises error when validation fails" do
      context = %AssemblyContext{
        assembled_instructions: "Incomplete instructions",
        validation_errors: ["Missing core mandates", "Missing tool integration"]
      }

      assert_raise RuntimeError, ~r/Instruction assembly validation failed/, fn ->
        InstructionAssembler.finalize_assembly(context)
      end
    end
  end

  describe "validate_instruction_completeness/1" do
    test "validates presence of required sections" do
      complete_instructions = """
      You are an interactive CLI agent specializing in software engineering tasks.
      
      # Core Mandates
      Essential operational guidelines.
      
      ## Available Tools
      You have access to the following tools.
      
      ## Security and Safety Rules
      Always follow security best practices.
      
      ## Current Environment
      Working in development environment.
      
      ## Your Current Capabilities
      You can perform various tasks.
      """

      errors = InstructionAssembler.validate_instruction_completeness(complete_instructions)

      assert Enum.empty?(errors)
    end

    test "identifies missing required sections" do
      incomplete_instructions = """
      You are an interactive CLI agent.
      
      ## Available Tools
      You have access to tools.
      """

      errors = InstructionAssembler.validate_instruction_completeness(incomplete_instructions)

      assert "Missing security guidelines" in errors
      assert "Missing environmental context" in errors
      assert "Missing capability description" in errors
    end
  end
end
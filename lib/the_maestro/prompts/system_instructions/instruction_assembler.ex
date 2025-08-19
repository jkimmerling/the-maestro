defmodule TheMaestro.Prompts.SystemInstructions.InstructionAssembler do
  @moduledoc """
  Intelligent instruction assembly engine for dynamic system instructions.
  """

  alias TheMaestro.Prompts.SystemInstructions.{
    AssemblyContext,
    TaskContext,
    TaskAnalyzer,
    Modules
  }

  @doc """
  Creates an assembly context from the input context.
  """
  def create_assembly_context(input_context) do
    %AssemblyContext{
      base_instructions: Modules.CoreMandates.generate(),
      available_tools: Map.get(input_context, :available_tools, []),
      mcp_servers: Map.get(input_context, :connected_mcp_servers, []),
      environment: Map.get(input_context, :environment, %{}),
      task_context: analyze_task_context(input_context),
      provider_info: get_provider_info(input_context),
      security_context: get_security_context(input_context)
    }
  end

  @doc """
  Assembles complete system instructions from the assembly context.
  """
  def assemble_instructions(%AssemblyContext{} = context) do
    context
    |> add_base_instructions()
    |> add_tool_integration_instructions()
    |> add_security_guidelines()
    |> add_environmental_context()
    |> add_capability_descriptions()
    |> add_workflow_guidance()
    |> add_provider_optimizations()
    |> add_output_formatting_rules()
    |> validate_assembly()
    |> finalize_assembly()
  end

  @doc """
  Adds tool integration instructions to the assembly context.
  """
  def add_tool_integration_instructions(%AssemblyContext{} = context) do
    tool_instructions = Modules.ToolIntegration.generate(context.available_tools)

    %{
      context
      | assembled_instructions: context.assembled_instructions <> "\n\n" <> tool_instructions
    }
  end

  @doc """
  Adds security guidelines to the assembly context.
  """
  def add_security_guidelines(%AssemblyContext{} = context) do
    environment = context.environment || %{}
    security_context = Map.merge(context.security_context, environment)
    security_instructions = Modules.SecurityGuidelines.generate(security_context)

    %{
      context
      | assembled_instructions: context.assembled_instructions <> "\n\n" <> security_instructions
    }
  end

  @doc """
  Adds provider-specific optimizations to the assembly context.
  """
  def add_provider_optimizations(%AssemblyContext{} = context) do
    provider = get_in(context.provider_info, [:provider])
    model = get_in(context.provider_info, [:model])

    optimizations = Modules.ProviderOptimization.generate(provider, model)

    if String.trim(optimizations) != "" do
      %{
        context
        | assembled_instructions: context.assembled_instructions <> "\n\n" <> optimizations
      }
    else
      context
    end
  end

  @doc """
  Finalizes the instruction assembly and returns the complete instructions.
  """
  def finalize_assembly(%AssemblyContext{} = context) do
    if Enum.empty?(context.validation_errors) do
      context.assembled_instructions
    else
      error_message =
        "Instruction assembly validation failed: " <>
          Enum.join(context.validation_errors, ", ")

      raise RuntimeError, error_message
    end
  end

  @doc """
  Validates the completeness of assembled instructions.
  """
  def validate_instruction_completeness(instructions) do
    required_sections = [
      {"Core Mandates", "Missing core mandates"},
      {"Security and Safety Rules", "Missing security guidelines"},
      {"Current Environment", "Missing environmental context"},
      {"Your Current Capabilities", "Missing capability description"}
    ]

    Enum.reduce(required_sections, [], fn {section, error}, errors ->
      if String.contains?(instructions, section) or String.contains?(instructions, "# #{section}") do
        errors
      else
        [error | errors]
      end
    end)
  end

  # Private helper functions

  defp add_base_instructions(%AssemblyContext{} = context) do
    %{context | assembled_instructions: context.base_instructions}
  end

  defp add_environmental_context(%AssemblyContext{} = context) do
    env_instructions = Modules.ContextAwareness.generate(context.environment)

    %{
      context
      | assembled_instructions: context.assembled_instructions <> "\n\n" <> env_instructions
    }
  end

  defp add_capability_descriptions(%AssemblyContext{} = context) do
    agent_state = build_agent_state(context)
    capability_instructions = Modules.CapabilityDescription.generate(agent_state)

    %{
      context
      | assembled_instructions:
          context.assembled_instructions <> "\n\n" <> capability_instructions
    }
  end

  defp add_workflow_guidance(%AssemblyContext{} = context) do
    if context.task_context do
      workflow_instructions = Modules.WorkflowGuidance.generate(context.task_context)

      %{
        context
        | assembled_instructions:
            context.assembled_instructions <> "\n\n" <> workflow_instructions
      }
    else
      context
    end
  end

  defp add_output_formatting_rules(%AssemblyContext{} = context) do
    # Placeholder for output formatting rules
    context
  end

  defp validate_assembly(%AssemblyContext{} = context) do
    validation_errors = validate_instruction_completeness(context.assembled_instructions)
    %{context | validation_errors: validation_errors}
  end

  defp analyze_task_context(input_context) do
    if Map.has_key?(input_context, :task_type) or Map.has_key?(input_context, :user_request) do
      TaskAnalyzer.analyze_task_context(input_context)
    else
      %TaskContext{
        primary_task_type: :generic,
        complexity_level: :moderate,
        required_capabilities: [],
        time_sensitivity: :normal,
        risk_level: :medium,
        collaboration_mode: :autonomous
      }
    end
  end

  defp get_provider_info(input_context) do
    case Map.get(input_context, :provider_info) do
      nil ->
        # Try to extract from direct provider/model keys
        %{
          provider: Map.get(input_context, :provider, :unknown),
          model: Map.get(input_context, :model, "unknown")
        }

      provider_info ->
        provider_info
    end
  end

  defp get_security_context(input_context) do
    Map.get(input_context, :security_context, %{trust_level: :medium, sandbox_mode: false})
  end

  defp build_agent_state(context) do
    %{
      current_provider: get_in(context.provider_info, [:provider]) || :unknown,
      current_model: get_in(context.provider_info, [:model]) || "unknown",
      file_access_level: determine_file_access_level(context),
      command_execution_level: determine_command_execution_level(context),
      available_mcp_tools: context.mcp_servers,
      # Placeholder
      auth_status: :authenticated,
      limitations: determine_limitations(context)
    }
  end

  defp determine_file_access_level(context) do
    has_read =
      Enum.any?(context.available_tools, fn
        %{name: name} -> String.contains?(to_string(name), "read")
        name when is_atom(name) -> String.contains?(to_string(name), "read")
        _ -> false
      end)

    has_write =
      Enum.any?(context.available_tools, fn
        %{name: name} -> String.contains?(to_string(name), "write")
        name when is_atom(name) -> String.contains?(to_string(name), "write")
        _ -> false
      end)

    cond do
      has_read and has_write -> :full
      has_read -> :read_only
      true -> :none
    end
  end

  defp determine_command_execution_level(context) do
    has_execute =
      Enum.any?(context.available_tools, fn
        %{name: name} ->
          String.contains?(to_string(name), "execute") or
            String.contains?(to_string(name), "command")

        name when is_atom(name) ->
          String.contains?(to_string(name), "execute") or
            String.contains?(to_string(name), "command")

        _ ->
          false
      end)

    if has_execute do
      if Map.get(context.environment, :sandbox_enabled, false) do
        :restricted
      else
        :full
      end
    else
      :none
    end
  end

  defp determine_limitations(context) do
    limitations = []

    limitations =
      if Map.get(context.environment, :sandbox_enabled, false) do
        ["Running in sandboxed environment" | limitations]
      else
        limitations
      end

    limitations =
      if get_in(context.security_context, [:trust_level]) == :low do
        ["Limited trust level - additional confirmations required" | limitations]
      else
        limitations
      end

    limitations
  end
end

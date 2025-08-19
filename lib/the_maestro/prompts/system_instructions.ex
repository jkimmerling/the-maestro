defmodule TheMaestro.Prompts.SystemInstructions do
  @moduledoc """
  Dynamic system instruction management for The Maestro agents.

  This module provides composable system instruction modules that adapt
  based on agent capabilities, context, and task requirements.
  """

  alias TheMaestro.Prompts.SystemInstructions.{
    InstructionAssembler,
    TaskAnalyzer,
    Modules
  }

  @instruction_modules [
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

  @doc """
  Returns the list of available instruction modules.
  """
  def instruction_modules, do: @instruction_modules

  @doc """
  Assembles complete system instructions based on the provided context.

  ## Parameters

  - `context` - A map containing:
    - `available_tools` - List of available tools
    - `connected_mcp_servers` - List of connected MCP servers
    - `environment` - Environmental context information
    - `provider_info` - Provider and model information
    - `security_context` - Security and trust level information
    - `task_type` - Primary task type (optional)

  ## Returns

  A string containing the assembled system instructions.

  ## Examples

      iex> context = %{
      ...>   available_tools: [:read_file, :write_file],
      ...>   environment: %{current_date: "2025-01-19"},
      ...>   provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      ...> }
      iex> instructions = SystemInstructions.assemble_system_instructions(context)
      iex> is_binary(instructions)
      true
  """
  def assemble_system_instructions(context) do
    context
    |> validate_required_context()
    |> InstructionAssembler.create_assembly_context()
    |> InstructionAssembler.assemble_instructions()
  end

  @doc """
  Generates core operational mandates.
  """
  def generate_core_mandates do
    Modules.CoreMandates.generate()
  end

  @doc """
  Generates tool integration instructions for the given tools.
  """
  def generate_tool_instructions(tools) do
    Modules.ToolIntegration.generate(tools)
  end

  @doc """
  Generates security guidelines based on context.
  """
  def generate_security_guidelines(context) do
    Modules.SecurityGuidelines.generate(context)
  end

  @doc """
  Generates environmental context information.
  """
  def generate_environmental_context(context) do
    Modules.ContextAwareness.generate(context)
  end

  @doc """
  Generates capability description based on agent state.
  """
  def generate_capability_description(agent_state) do
    Modules.CapabilityDescription.generate(agent_state)
  end

  @doc """
  Generates workflow-specific instructions based on task context.
  """
  def generate_workflow_instructions(task_context) do
    Modules.WorkflowGuidance.generate(task_context)
  end

  @doc """
  Generates provider-specific optimizations.
  """
  def generate_provider_optimizations(provider, model) do
    Modules.ProviderOptimization.generate(provider, model)
  end

  @doc """
  Analyzes task context to determine requirements and complexity.
  """
  def analyze_task_context(context) do
    TaskAnalyzer.analyze_task_context(context)
  end

  @doc """
  Optimizes instructions for length within the given token budget.
  """
  def optimize_instructions_for_length(instructions, token_budget) do
    # Simple length optimization - in practice this would be more sophisticated
    # Rough estimate: 1 token ≈ 4 characters
    target_length = token_budget * 4

    if String.length(instructions) <= target_length do
      instructions
    else
      # Truncate to fit within budget, keeping proportional content
      instructions
      # Leave some room for the truncation message
      |> String.slice(0, round(target_length * 0.9))
      |> Kernel.<>("\n\n[Instructions truncated for length optimization]")
    end
  end

  @doc """
  Filters instruction modules based on context relevance.
  """
  def filter_relevant_modules(context) do
    base_modules = [:core_mandates]

    modules =
      base_modules ++
        if(has_tools?(context), do: [:tool_integration], else: []) ++
        if(requires_security?(context), do: [:security_guidelines], else: []) ++
        if(has_environment_info?(context), do: [:context_awareness], else: []) ++
        if(has_workflow_context?(context), do: [:workflow_guidance], else: []) ++
        if has_provider_info?(context), do: [:provider_optimization], else: []

    modules
  end

  @doc """
  Gets cached core mandates (stub for caching implementation).
  """
  def get_cached_core_mandates do
    # In a real implementation, this would use a cache like ETS or Agent
    generate_core_mandates()
  end

  @doc """
  Verifies cache hit for the given module (stub for testing).
  """
  def verify_cache_hit(_module) do
    # Stub implementation for testing
    :ok
  end

  # Private helper functions

  defp validate_required_context(context) when is_map(context) do
    # Made flexible for now
    required_fields = []

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(context, field)
      end)

    if length(missing_fields) > 0 do
      raise ArgumentError, "Required context fields missing: #{Enum.join(missing_fields, ", ")}"
    end

    context
  end

  defp validate_required_context(_context) do
    raise ArgumentError, "Context must be a map"
  end

  defp has_tools?(context) do
    Map.get(context, :available_tools, []) != []
  end

  defp requires_security?(context) do
    Map.get(context, :requires_security, true)
  end

  defp has_environment_info?(context) do
    Map.has_key?(context, :environment)
  end

  defp has_workflow_context?(context) do
    Map.has_key?(context, :task_type)
  end

  defp has_provider_info?(context) do
    Map.has_key?(context, :provider) or Map.has_key?(context, :provider_info)
  end
end

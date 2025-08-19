defmodule TheMaestro.Prompts.Optimization.Providers.UniversalOptimizer do
  @moduledoc """
  Universal optimization patterns that work across all LLM providers.

  This module provides cross-provider optimizations that improve prompt quality,
  clarity, and effectiveness regardless of the specific LLM being used.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  @doc """
  Applies universal optimization patterns to the enhanced prompt.

  These optimizations work well with all providers and focus on fundamental
  prompt quality improvements like clarity, organization, and task definition.
  """
  @spec apply_universal_optimizations(EnhancedPrompt.t(), map()) :: EnhancedPrompt.t()
  def apply_universal_optimizations(enhanced_prompt, provider_info) do
    enhanced_prompt
    |> optimize_instruction_clarity()
    |> enhance_context_organization()
    |> optimize_example_selection()
    |> improve_task_decomposition()
    |> add_quality_validation_prompts()
    |> optimize_output_format_requests()
    |> add_provider_neutral_enhancements(provider_info)
  end

  @doc """
  Applies universal optimizations to an optimization context.
  """
  @spec optimize(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize(optimization_context) do
    enhanced_prompt =
      apply_universal_optimizations(
        optimization_context.enhanced_prompt,
        optimization_context.provider_info
      )

    %{optimization_context | enhanced_prompt: enhanced_prompt, optimization_applied: true}
  end

  # Instruction clarity optimizations

  defp optimize_instruction_clarity(enhanced_prompt) do
    enhanced_prompt
    |> use_active_voice()
    |> eliminate_ambiguous_language()
    |> add_clear_task_boundaries()
    |> specify_expected_outputs()
    |> add_constraint_clarifications()
  end

  defp use_active_voice(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Convert common passive voice patterns to active voice
    active_text =
      text
      |> String.replace(~r/should be (\w+)/i, "must \\1")
      |> String.replace(~r/will be (\w+)/i, "will \\1")
      |> String.replace(~r/can be (\w+)/i, "can \\1")

    %{enhanced_prompt | enhanced_prompt: active_text}
  end

  defp eliminate_ambiguous_language(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Replace vague terms with more specific language
    clear_text =
      text
      |> String.replace(~r/\bstuff\b/i, "items")
      |> String.replace(~r/\bthings\b/i, "elements")
      |> String.replace(~r/\bsomehow\b/i, "using appropriate methods")
      |> String.replace(~r/\bkinda\b/i, "approximately")
      |> String.replace(~r/\bsorta\b/i, "somewhat")

    %{enhanced_prompt | enhanced_prompt: clear_text}
  end

  defp add_clear_task_boundaries(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add task boundary markers if not present
    if String.contains?(text, ["## Task", "# Task", "**Task**"]) do
      enhanced_prompt
    else
      boundary_text = """
      ## Primary Task
      #{text}

      ## Expected Deliverable
      Please provide a complete response addressing all aspects of the above task.
      """

      %{enhanced_prompt | enhanced_prompt: boundary_text}
    end
  end

  defp specify_expected_outputs(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add output specification if not present
    if String.contains?(text, ["output", "response", "result", "deliverable"]) do
      enhanced_prompt
    else
      output_text =
        text <>
          """

          ## Output Requirements
          - Provide clear, specific responses
          - Include reasoning for key decisions
          - Use appropriate formatting for readability
          """

      %{enhanced_prompt | enhanced_prompt: output_text}
    end
  end

  defp add_constraint_clarifications(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add constraint section if constraints are mentioned but not clearly defined
    if String.contains?(text, ["constraint", "limit", "must not", "cannot"]) and
         not String.contains?(text, "## Constraints") do
      constraint_text =
        text <>
          """

          ## Important Constraints
          Please adhere to any constraints mentioned in the task description.
          If uncertain about constraints, ask for clarification.
          """

      %{enhanced_prompt | enhanced_prompt: constraint_text}
    else
      enhanced_prompt
    end
  end

  # Context organization optimizations

  defp enhance_context_organization(enhanced_prompt) do
    enhanced_prompt
    |> implement_hierarchical_structure()
    |> add_section_headers()
    |> use_consistent_formatting()
    |> optimize_information_flow()
    |> add_reference_aids()
  end

  defp implement_hierarchical_structure(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add hierarchical structure if the text is long but lacks organization
    word_count = String.split(text) |> length()
    has_headers = String.contains?(text, ["##", "###", "**", "---"])

    if word_count > 100 and not has_headers do
      structured_text = """
      ## Context
      #{text}

      ## Instructions
      Please process the above context and provide a comprehensive response.
      """

      %{enhanced_prompt | enhanced_prompt: structured_text}
    else
      enhanced_prompt
    end
  end

  defp add_section_headers(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Improve existing section separation
    improved_text =
      text
      |> String.replace(~r/\n(\d+\.\s)/m, "\n### \\1")
      |> String.replace(~r/\n([A-Z][a-z]+:)\s/m, "\n#### \\1\n")

    %{enhanced_prompt | enhanced_prompt: improved_text}
  end

  defp use_consistent_formatting(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Standardize formatting patterns
    formatted_text =
      text
      # Ensure bold formatting
      |> String.replace(~r/\*\*([^*]+)\*\*/m, "**\\1**")
      # Remove excessive line breaks
      |> String.replace(~r/\n\n\n+/m, "\n\n")
      # Remove trailing whitespace
      |> String.replace(~r/[ \t]+$/m, "")

    %{enhanced_prompt | enhanced_prompt: formatted_text}
  end

  defp optimize_information_flow(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add flow markers for better comprehension
    if String.length(text) > 500 and not String.contains?(text, ["First", "Next", "Finally"]) do
      flow_text = """
      #{text}

      ## Processing Instructions
      Please work through this systematically:
      1. First, analyze the requirements
      2. Next, consider your approach
      3. Finally, provide your complete response
      """

      %{enhanced_prompt | enhanced_prompt: flow_text}
    else
      enhanced_prompt
    end
  end

  defp add_reference_aids(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add reference numbers for complex instructions
    lines = String.split(text, "\n")

    if length(lines) > 10 do
      # Add line numbers to long, complex prompts
      numbered_lines =
        lines
        |> Enum.with_index(1)
        |> Enum.map(fn {line, idx} ->
          if String.match?(line, ~r/^(##|###|\*\*|\d+\.)/) do
            "[#{idx}] #{line}"
          else
            line
          end
        end)
        |> Enum.join("\n")

      %{enhanced_prompt | enhanced_prompt: numbered_lines}
    else
      enhanced_prompt
    end
  end

  # Task and example optimization

  defp optimize_example_selection(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Enhance examples with better structure
    if String.contains?(text, ["example", "for instance", "such as"]) do
      example_text =
        text <>
          """

          ## Example Quality Guidelines
          - Use concrete, specific examples
          - Ensure examples directly relate to the task
          - Provide context for each example
          """

      %{enhanced_prompt | enhanced_prompt: example_text}
    else
      enhanced_prompt
    end
  end

  defp improve_task_decomposition(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Break down complex tasks into steps
    complex_keywords = ["analyze", "evaluate", "compare", "implement", "design", "create"]
    is_complex = Enum.any?(complex_keywords, &String.contains?(String.downcase(text), &1))

    if is_complex and not String.contains?(text, ["step", "phase", "stage"]) do
      decomposed_text =
        text <>
          """

          ## Approach Recommendation
          Consider breaking this task into logical steps:
          1. Analysis and understanding
          2. Planning and strategy
          3. Implementation or response
          4. Review and validation
          """

      %{enhanced_prompt | enhanced_prompt: decomposed_text}
    else
      enhanced_prompt
    end
  end

  defp add_quality_validation_prompts(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add quality checks for important tasks
    importance_keywords = ["critical", "important", "essential", "required", "must"]
    is_important = Enum.any?(importance_keywords, &String.contains?(String.downcase(text), &1))

    if is_important and not String.contains?(text, ["validate", "verify", "check"]) do
      validation_text =
        text <>
          """

          ## Quality Validation
          Before finalizing your response, please:
          - Verify accuracy of key information
          - Ensure completeness of coverage
          - Check for logical consistency
          """

      %{enhanced_prompt | enhanced_prompt: validation_text}
    else
      enhanced_prompt
    end
  end

  defp optimize_output_format_requests(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    # Add format guidelines if output format is mentioned but not specified
    if String.contains?(text, ["format", "structure", "organize"]) and
         not String.contains?(text, ["markdown", "JSON", "table", "list"]) do
      format_text =
        text <>
          """

          ## Output Format Guidelines
          - Use clear headings and sections
          - Employ bullet points or numbered lists for clarity
          - Include specific examples where helpful
          - Maintain professional, readable formatting
          """

      %{enhanced_prompt | enhanced_prompt: format_text}
    else
      enhanced_prompt
    end
  end

  defp add_provider_neutral_enhancements(enhanced_prompt, provider_info) do
    text = enhanced_prompt.enhanced_prompt

    # Add generic improvements that work well across all providers
    enhanced_text =
      text <>
        """

        ## General Guidelines
        - Provide thorough, well-reasoned responses
        - Use clear, professional language
        - Include relevant context and examples
        - Ensure accuracy and reliability
        """

    # Add optimization metadata
    universal_metadata = %{
      provider_optimized: provider_info.provider,
      universal_optimization_score: calculate_universal_score(enhanced_prompt),
      universal_optimizations_applied: true
    }

    updated_metadata = Map.merge(enhanced_prompt.metadata || %{}, universal_metadata)

    %{enhanced_prompt | enhanced_prompt: enhanced_text, metadata: updated_metadata}
  end

  defp calculate_universal_score(enhanced_prompt) do
    text = enhanced_prompt.enhanced_prompt

    score_factors = [
      # Structure
      if(String.contains?(text, ["##", "###"]), do: 0.2, else: 0.0),
      # Completeness
      if(String.length(text) > 200, do: 0.2, else: 0.1),
      # Examples
      if(String.contains?(text, ["example", "instance"]), do: 0.15, else: 0.0),
      # Methodology
      if(String.contains?(text, ["step", "approach"]), do: 0.15, else: 0.0),
      # Quality
      if(String.contains?(text, ["validate", "verify"]), do: 0.15, else: 0.0),
      # Base universal improvements
      0.15
    ]

    Enum.sum(score_factors)
  end
end

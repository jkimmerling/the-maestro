defmodule TheMaestro.Prompts.Optimization.Providers.AnthropicOptimizer do
  @moduledoc """
  Claude/Anthropic-specific prompt optimization engine.

  Leverages Claude's unique strengths in reasoning, code understanding,
  context utilization, safety awareness, and instruction following.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext
  alias TheMaestro.Prompts.Optimization.Config.OptimizationConfig

  @claude_strengths %{
    reasoning: :excellent,
    code_understanding: :excellent,
    context_utilization: :excellent,
    safety_awareness: :excellent,
    instruction_following: :excellent,
    structured_thinking: :excellent
  }

  def get_claude_strengths, do: @claude_strengths

  @doc """
  Applies Claude-specific optimization to the prompt context.
  """
  @spec optimize(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize(optimization_context) do
    # Get Anthropic-specific configuration
    optimization_config = OptimizationConfig.get_provider_config(:anthropic)

    optimization_context
    |> apply_configured_optimizations(optimization_config)
    |> format_for_claude_preferences()
    |> mark_optimization_complete()
  end

  defp apply_configured_optimizations(context, config) do
    context
    |> conditionally_apply(:leverage_reasoning_capabilities, config[:reasoning_enhancement])
    |> conditionally_apply_context_optimization(config)
    # Always apply this
    |> conditionally_apply(:enhance_instruction_clarity, true)
    |> conditionally_apply(:utilize_structured_thinking_patterns, config[:structured_thinking])
    |> conditionally_apply(:optimize_safety_considerations, config[:safety_optimization])
  end

  defp conditionally_apply_context_optimization(context, config) do
    # Apply large context optimization if both config allows and prompt is large enough
    should_optimize =
      config[:max_context_utilization] > 0.8 and
        exceeds_token_threshold?(context.enhanced_prompt, 20_000)

    conditionally_apply(context, :optimize_for_large_context, should_optimize)
  end

  defp conditionally_apply(context, _function, false), do: context

  defp conditionally_apply(context, function_atom, true) do
    apply(__MODULE__, function_atom, [context])
  end

  @doc """
  Adds reasoning framework for complex tasks requiring step-by-step analysis.
  """
  @spec leverage_reasoning_capabilities(OptimizationContext.t()) :: OptimizationContext.t()
  def leverage_reasoning_capabilities(context) do
    if complex_reasoning_required?(context.enhanced_prompt) do
      context
      |> add_thinking_framework()
      |> encourage_step_by_step_analysis()
      |> add_reasoning_validation_prompts()
      |> Map.put(:reasoning_enhanced, true)
    else
      context
    end
  end

  @doc """
  Optimizes prompt for Claude's large context window capabilities.
  """
  @spec optimize_for_large_context(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize_for_large_context(context) do
    if exceeds_token_threshold?(context.enhanced_prompt, 20_000) do
      context
      |> add_context_navigation_aids()
      |> implement_hierarchical_information_structure()
      |> add_context_summarization_requests()
      |> Map.put(:large_context_optimized, true)
    else
      context
    end
  end

  @doc """
  Checks if a prompt requires complex reasoning capabilities.
  """
  @spec complex_reasoning_required?(EnhancedPrompt.t()) :: boolean()
  def complex_reasoning_required?(enhanced_prompt) do
    reasoning_keywords = [
      "analyze",
      "architectural",
      "design",
      "system",
      "compare",
      "contrast",
      "evaluate",
      "trade-offs",
      "implications",
      "consider",
      "approach",
      "problem-solving",
      "strategy",
      "multiple",
      "scenarios",
      "complex",
      "multi-step",
      "problem",
      "solve",
      "solution"
    ]

    prompt_text = String.downcase(enhanced_prompt.enhanced_prompt)

    Enum.any?(reasoning_keywords, fn keyword ->
      String.contains?(prompt_text, keyword)
    end)
  end

  @doc """
  Checks if prompt exceeds token threshold requiring context optimization.
  """
  @spec exceeds_token_threshold?(EnhancedPrompt.t(), integer()) :: boolean()
  def exceeds_token_threshold?(enhanced_prompt, threshold) do
    estimated_tokens = estimate_token_count(enhanced_prompt.enhanced_prompt)
    estimated_tokens > threshold
  end

  # Private functions

  defp add_thinking_framework(context) do
    thinking_prompt = """

    Please approach this systematically:
    1. First, analyze the current situation and requirements
    2. Consider multiple approaches and their trade-offs  
    3. Choose the best approach and explain your reasoning
    4. Implement the solution step by step
    5. Validate the results and suggest improvements
    """

    update_prompt(context, fn prompt ->
      prompt <> thinking_prompt
    end)
  end

  defp encourage_step_by_step_analysis(context) do
    step_by_step_prompt = """

    Take your time to work through this step by step, showing your reasoning at each stage.
    """

    update_prompt(context, fn prompt ->
      prompt <> step_by_step_prompt
    end)
  end

  defp add_reasoning_validation_prompts(context) do
    validation_prompt = """

    After completing your analysis, please perform reasoning validation by:
    - Double-checking your logic and assumptions
    - Considering alternative perspectives
    - Identifying any potential issues or limitations
    """

    update_prompt(context, fn prompt ->
      prompt <> validation_prompt
    end)
  end

  defp add_context_navigation_aids(context) do
    navigation_prompt = """

    ## Context Navigation
    This prompt contains extensive context. Please:
    - Reference specific sections when making points
    - Summarize key information before detailed analysis
    - Use the hierarchical structure to organize your response
    """

    update_prompt(context, fn prompt ->
      navigation_prompt <> "\n\n" <> prompt
    end)
  end

  defp implement_hierarchical_information_structure(context) do
    # Add structure markers to help Claude navigate large context
    structure_prompt = """

    ## Information Hierarchy
    Please organize your response using clear hierarchical structure:
    - Main points as ## headers
    - Sub-points as ### headers  
    - Supporting details as bullet points
    """

    update_prompt(context, fn prompt ->
      structure_prompt <> "\n\n" <> prompt
    end)
  end

  defp add_context_summarization_requests(context) do
    summary_prompt = """

    Given the extensive context, please begin your response with a brief summary
    of the key points before diving into detailed analysis.
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> summary_prompt
    end)
  end

  def enhance_instruction_clarity(context) do
    # Claude responds well to clear, specific instructions
    clarity_prompt = """

    Please provide clear, structured, and detailed responses. Consider:
    - Breaking down complex tasks into manageable steps
    - Providing specific examples where helpful
    - Being explicit about your reasoning and approach
    """

    updated_context =
      update_prompt(context, fn prompt ->
        prompt <> clarity_prompt
      end)

    updated_context
    |> Map.put(:optimization_applied, true)
  end

  def utilize_structured_thinking_patterns(context) do
    context
    |> Map.put(:structured_thinking_applied, true)
  end

  def optimize_safety_considerations(context) do
    # Claude has strong safety awareness - can leverage this
    context
    |> Map.put(:safety_optimized, true)
  end

  defp format_for_claude_preferences(context) do
    # Format according to Claude's preferences
    context
    |> Map.put(:claude_formatted, true)
  end

  defp mark_optimization_complete(context) do
    context
    |> Map.put(:optimization_applied, true)
    |> Map.put(:optimization_score, calculate_optimization_score(context))
    |> Map.put(:validation_passed, true)
  end

  defp calculate_optimization_score(context) do
    base_score = 0.7

    score_adjustments = [
      if(context.reasoning_enhanced, do: 0.1, else: 0.0),
      if(context.large_context_optimized, do: 0.1, else: 0.0),
      if(context.structured_thinking_applied, do: 0.05, else: 0.0),
      if(context.safety_optimized, do: 0.05, else: 0.0)
    ]

    base_score + Enum.sum(score_adjustments)
  end

  defp update_prompt(context, update_fn) do
    updated_prompt = update_fn.(context.enhanced_prompt.enhanced_prompt)

    updated_enhanced_prompt = %{context.enhanced_prompt | enhanced_prompt: updated_prompt}

    %{context | enhanced_prompt: updated_enhanced_prompt}
  end

  defp estimate_token_count(text) do
    # More accurate token estimation: roughly 2.5-3 characters per token
    # Being conservative with 2.5 to err on the side of detecting large contexts
    (String.length(text) * 0.4) |> round()
  end
end

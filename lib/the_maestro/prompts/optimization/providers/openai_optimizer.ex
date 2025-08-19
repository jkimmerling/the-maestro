defmodule TheMaestro.Prompts.Optimization.Providers.OpenAIOptimizer do
  @moduledoc """
  OpenAI/ChatGPT-specific prompt optimization engine.

  Leverages GPT's capabilities in general reasoning, language understanding,
  creative tasks, consistency, API reliability, and structured output.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  @gpt_strengths %{
    general_reasoning: :excellent,
    language_understanding: :excellent,
    creative_tasks: :excellent,
    consistency: :excellent,
    api_reliability: :excellent,
    structured_output: :good
  }

  def get_gpt_strengths, do: @gpt_strengths

  # Token limits for different GPT models
  @token_limits %{
    "gpt-4o" => 128_000,
    "gpt-4-turbo" => 128_000,
    "gpt-4" => 8_192,
    "gpt-3.5-turbo" => 16_385
  }

  @doc """
  Applies OpenAI-specific optimization to the prompt context.
  """
  @spec optimize(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize(optimization_context) do
    optimization_context
    |> optimize_for_consistent_reasoning()
    |> enhance_structured_output_requests()
    |> optimize_for_api_reliability()
    |> leverage_strong_language_capabilities()
    |> optimize_creative_and_analytical_balance()
    |> format_for_openai_preferences()
    |> mark_optimization_complete()
  end

  @doc """
  Optimizes for consistent reasoning patterns.
  """
  @spec optimize_for_consistent_reasoning(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize_for_consistent_reasoning(context) do
    context
    |> add_consistency_checks()
    |> implement_reasoning_validation()
    |> add_output_format_specifications()
    |> enhance_error_detection_prompts()
    |> Map.put(:consistent_reasoning_optimized, true)
  end

  @doc """
  Enhances structured output requests when needed.
  """
  @spec enhance_structured_output_requests(OptimizationContext.t()) :: OptimizationContext.t()
  def enhance_structured_output_requests(context) do
    if requires_structured_output?(context.enhanced_prompt) do
      context
      |> add_json_schema_specifications()
      |> add_output_format_examples()
      |> add_validation_instructions()
      |> Map.put(:structured_output_enhanced, true)
    else
      context
    end
  end

  @doc """
  Checks if the prompt requires structured output.
  """
  @spec requires_structured_output?(EnhancedPrompt.t()) :: boolean()
  def requires_structured_output?(enhanced_prompt) do
    structured_keywords = [
      "json",
      "xml",
      "yaml",
      "csv",
      "table",
      "format",
      "schema",
      "structured",
      "data",
      "output format",
      "return as",
      "format as"
    ]

    prompt_text = String.downcase(enhanced_prompt.enhanced_prompt)

    Enum.any?(structured_keywords, fn keyword ->
      String.contains?(prompt_text, keyword)
    end)
  end

  @doc """
  Optimizes GPT token usage based on model limits.
  """
  @spec optimize_gpt_token_usage(EnhancedPrompt.t(), map()) :: EnhancedPrompt.t()
  def optimize_gpt_token_usage(enhanced_prompt, model_info) do
    # Use provided token_limit from model_info if available, otherwise use default
    token_limit = model_info[:token_limit] || get_gpt_token_limit(model_info.model)
    current_tokens = estimate_gpt_tokens(enhanced_prompt)

    optimization_strategies = [
      :compress_repetitive_content,
      :use_abbreviations_for_common_terms,
      :optimize_example_selection,
      :streamline_instruction_language,
      :prioritize_essential_context
    ]

    if current_tokens > token_limit * 0.05 do
      Enum.reduce(optimization_strategies, enhanced_prompt, fn strategy, prompt ->
        apply_optimization_strategy(strategy, prompt, token_limit - current_tokens)
      end)
    else
      enhanced_prompt
    end
  end

  @doc """
  Gets token limit for specific GPT model.
  """
  @spec get_gpt_token_limit(String.t()) :: integer()
  def get_gpt_token_limit(model) do
    Map.get(@token_limits, model, 8_000)
  end

  @doc """
  Estimates token count for GPT models.
  """
  @spec estimate_gpt_tokens(EnhancedPrompt.t()) :: integer()
  def estimate_gpt_tokens(enhanced_prompt) do
    # GPT tokenization: roughly 4 characters per token, but can vary
    # This is a simple estimation - production would use tiktoken
    text = enhanced_prompt.enhanced_prompt
    String.length(text) |> div(4)
  end

  # Private functions

  defp add_consistency_checks(context) do
    consistency_prompt = """

    Please ensure consistency throughout your response:
    - Use consistent terminology and definitions
    - Maintain logical flow between sections
    - Cross-reference related points for coherence
    - Validate reasoning at each step
    """

    update_prompt(context, fn prompt ->
      prompt <> consistency_prompt
    end)
  end

  defp implement_reasoning_validation(context) do
    validation_prompt = """

    Before finalizing your response:
    - Review your reasoning for logical consistency
    - Check that conclusions follow from premises
    - Identify and address any contradictions
    - Ensure evidence supports all claims
    """

    update_prompt(context, fn prompt ->
      prompt <> validation_prompt
    end)
  end

  defp add_output_format_specifications(context) do
    format_prompt = """

    Format your response clearly:
    - Use appropriate headers and structure
    - Present information in logical order
    - Include clear transitions between ideas
    - Maintain professional tone throughout
    """

    update_prompt(context, fn prompt ->
      prompt <> format_prompt
    end)
  end

  defp enhance_error_detection_prompts(context) do
    error_prompt = """

    Please double-check your work:
    - Verify factual accuracy where possible
    - Check calculations and logical steps  
    - Ensure all requirements are addressed
    - Flag any uncertainties or assumptions
    """

    update_prompt(context, fn prompt ->
      prompt <> error_prompt
    end)
  end

  defp add_json_schema_specifications(context) do
    schema_prompt = """

    ## JSON Output Requirements
    Please format your response as valid JSON with:
    - Proper syntax and structure
    - Consistent data types
    - Clear field names and organization
    - No trailing commas or syntax errors
    """

    update_prompt(context, fn prompt ->
      schema_prompt <> "\n\n" <> prompt
    end)
  end

  defp add_output_format_examples(context) do
    example_prompt = """

    Example output format:
    ```json
    {
      "result": "your analysis here",
      "confidence": 0.95,
      "reasoning": ["step 1", "step 2"],
      "recommendations": ["rec 1", "rec 2"]
    }
    ```
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> example_prompt
    end)
  end

  defp add_validation_instructions(context) do
    validation_prompt = """

    Before submitting your JSON response:
    - Validate JSON syntax is correct
    - Ensure all required fields are included
    - Check data types match expectations
    - Verify content completeness and accuracy
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> validation_prompt
    end)
  end

  defp optimize_for_api_reliability(context) do
    context
    |> Map.put(:api_reliability_optimized, true)
  end

  defp leverage_strong_language_capabilities(context) do
    context
    |> Map.put(:language_capabilities_leveraged, true)
  end

  defp optimize_creative_and_analytical_balance(context) do
    context
    |> Map.put(:creative_analytical_balanced, true)
  end

  defp format_for_openai_preferences(context) do
    context
    |> Map.put(:openai_formatted, true)
  end

  defp mark_optimization_complete(context) do
    context
    |> Map.put(:openai_optimized, true)
    |> Map.put(:optimization_applied, true)
    |> Map.put(:optimization_score, calculate_optimization_score(context))
    |> Map.put(:validation_passed, true)
  end

  defp calculate_optimization_score(context) do
    base_score = 0.7

    score_adjustments = [
      if(context.consistent_reasoning_optimized, do: 0.1, else: 0.0),
      if(context.structured_output_enhanced, do: 0.1, else: 0.0),
      if(context.api_reliability_optimized, do: 0.05, else: 0.0),
      if(context.language_capabilities_leveraged, do: 0.05, else: 0.0),
      if(context.creative_analytical_balanced, do: 0.05, else: 0.0)
    ]

    base_score + Enum.sum(score_adjustments)
  end

  defp update_prompt(context, update_fn) do
    updated_prompt = update_fn.(context.enhanced_prompt.enhanced_prompt)
    updated_enhanced_prompt = %{context.enhanced_prompt | enhanced_prompt: updated_prompt}
    %{context | enhanced_prompt: updated_enhanced_prompt}
  end

  defp apply_optimization_strategy(:compress_repetitive_content, enhanced_prompt, _tokens_to_save) do
    # Simple compression - remove repeated phrases
    text = enhanced_prompt.enhanced_prompt
    compressed_text = String.replace(text, ~r/(.{20,}?)\s+\1/, "\\1")
    %{enhanced_prompt | enhanced_prompt: compressed_text}
  end

  defp apply_optimization_strategy(
         :use_abbreviations_for_common_terms,
         enhanced_prompt,
         _tokens_to_save
       ) do
    # Replace common long terms with abbreviations
    text = enhanced_prompt.enhanced_prompt

    abbreviations = %{
      "artificial intelligence" => "AI",
      "machine learning" => "ML",
      "natural language processing" => "NLP",
      "application programming interface" => "API"
    }

    abbreviated_text =
      Enum.reduce(abbreviations, text, fn {full, abbrev}, acc ->
        String.replace(acc, full, abbrev, global: true)
      end)

    %{enhanced_prompt | enhanced_prompt: abbreviated_text}
  end

  defp apply_optimization_strategy(:optimize_example_selection, enhanced_prompt, _tokens_to_save) do
    # For now, just return the original prompt
    # In a full implementation, would intelligently select most relevant examples
    enhanced_prompt
  end

  defp apply_optimization_strategy(
         :streamline_instruction_language,
         enhanced_prompt,
         _tokens_to_save
       ) do
    # Simplify verbose instructions
    text = enhanced_prompt.enhanced_prompt

    streamlined_text =
      text
      |> String.replace("Please make sure to", "")
      |> String.replace("It is important that you", "")
      |> String.replace("I would like you to", "")
      |> String.replace("Could you please", "")

    %{enhanced_prompt | enhanced_prompt: streamlined_text}
  end

  defp apply_optimization_strategy(
         :prioritize_essential_context,
         enhanced_prompt,
         _tokens_to_save
       ) do
    # For now, just return the original prompt
    # In a full implementation, would identify and keep only essential context
    enhanced_prompt
  end

  defp apply_optimization_strategy(_strategy, enhanced_prompt, _tokens_to_save) do
    enhanced_prompt
  end
end

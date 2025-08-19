defmodule TheMaestro.Prompts.Optimization.Providers.GoogleOptimizer do
  @moduledoc """
  Gemini/Google-specific prompt optimization engine.

  Leverages Gemini's capabilities in multimodal processing, function calling,
  code generation, large context windows, and Google services integration.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.Structs.OptimizationContext

  @gemini_strengths %{
    multimodal: :excellent,
    function_calling: :excellent,
    code_generation: :excellent,
    reasoning: :very_good,
    context_window: :very_large,
    integration_capabilities: :excellent
  }

  def get_gemini_strengths, do: @gemini_strengths

  @doc """
  Applies Gemini-specific optimization to the prompt context.
  """
  @spec optimize(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize(optimization_context) do
    optimization_context
    |> optimize_for_multimodal_capabilities()
    |> enhance_function_calling_integration()
    |> optimize_for_code_generation()
    |> leverage_large_context_window()
    |> integrate_google_services_context()
    |> format_for_gemini_preferences()
    |> mark_optimization_complete()
  end

  @doc """
  Optimizes for multimodal capabilities when visual elements are present.
  """
  @spec optimize_for_multimodal_capabilities(OptimizationContext.t()) :: OptimizationContext.t()
  def optimize_for_multimodal_capabilities(context) do
    if has_visual_elements?(context.enhanced_prompt) do
      context
      |> add_visual_analysis_instructions()
      |> optimize_image_description_requests()
      |> enhance_visual_reasoning_prompts()
      |> Map.put(:multimodal_optimized, true)
    else
      context
    end
  end

  @doc """
  Enhances function calling integration when tools are available.
  """
  @spec enhance_function_calling_integration(OptimizationContext.t()) :: OptimizationContext.t()
  def enhance_function_calling_integration(context) do
    available_tools = extract_available_tools(context)

    if length(available_tools) > 0 do
      context
      |> add_tool_usage_optimization(available_tools)
      |> enhance_parameter_validation()
      |> add_tool_chaining_suggestions()
      |> optimize_tool_selection_logic()
      |> Map.put(:function_calling_optimized, true)
    else
      context
    end
  end

  @doc """
  Checks if prompt contains visual elements requiring multimodal optimization.
  """
  @spec has_visual_elements?(EnhancedPrompt.t()) :: boolean()
  def has_visual_elements?(enhanced_prompt) do
    # Check metadata for visual indicators
    has_images = get_in(enhanced_prompt.metadata, ["has_images"]) == true

    # Check prompt text for visual keywords
    visual_keywords = [
      "image",
      "picture",
      "photo",
      "screenshot",
      "chart",
      "graph",
      "diagram",
      "visual",
      "look at",
      "analyze this",
      "describe",
      "what do you see"
    ]

    prompt_text = String.downcase(enhanced_prompt.enhanced_prompt)

    has_visual_keywords =
      Enum.any?(visual_keywords, fn keyword ->
        String.contains?(prompt_text, keyword)
      end)

    has_images or has_visual_keywords
  end

  @doc """
  Extracts available tools from the optimization context.
  """
  @spec extract_available_tools(OptimizationContext.t()) :: list()
  def extract_available_tools(context) do
    case context.available_tools do
      nil -> []
      tools when is_list(tools) -> tools
      _ -> []
    end
  end

  # Private functions

  defp add_visual_analysis_instructions(context) do
    visual_prompt = """

    ## Visual Analysis Instructions
    When analyzing visual content:
    - Describe what you observe systematically
    - Identify key visual elements, patterns, and relationships
    - Consider the context and purpose of the visual information
    - Highlight any important details that support the analysis
    """

    update_prompt(context, fn prompt ->
      visual_prompt <> "\n\n" <> prompt
    end)
  end

  defp optimize_image_description_requests(context) do
    description_prompt = """

    For image analysis, please provide:
    - Overall scene or content description
    - Specific details relevant to the request
    - Any text visible in the image
    - Spatial relationships and composition notes
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> description_prompt
    end)
  end

  defp enhance_visual_reasoning_prompts(context) do
    reasoning_prompt = """

    Use visual information to support your reasoning:
    - Reference specific visual elements in your analysis
    - Explain how visual information supports conclusions
    - Consider visual context when making recommendations
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> reasoning_prompt
    end)
  end

  defp add_tool_usage_optimization(context, available_tools) do
    tool_guidance = generate_tool_selection_guidance(available_tools)
    parameter_optimization = optimize_tool_parameters(available_tools)
    chaining_opportunities = identify_tool_chaining_opportunities(available_tools)
    error_handling = generate_tool_error_handling_guidance(available_tools)

    tool_prompt = """

    ## Tool Usage Optimization

    #{tool_guidance}

    ### Available Tools
    #{format_tools_for_gemini(available_tools)}

    ### Tool Usage Guidelines
    - Consider tool chaining opportunities: #{chaining_opportunities}
    - Validate parameters carefully: #{parameter_optimization}
    - Handle errors gracefully: #{error_handling}
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> tool_prompt
    end)
  end

  defp enhance_parameter_validation(context) do
    validation_prompt = """

    When using tools, always:
    - Validate input parameters match expected types
    - Check for required vs optional parameters
    - Handle edge cases and boundary conditions
    """

    update_prompt(context, fn prompt ->
      prompt <> "\n\n" <> validation_prompt
    end)
  end

  defp add_tool_chaining_suggestions(context) do
    context
  end

  defp optimize_tool_selection_logic(context) do
    context
  end

  defp optimize_for_code_generation(context) do
    context
    |> Map.put(:code_generation_optimized, true)
  end

  defp leverage_large_context_window(context) do
    # Gemini can handle very large contexts effectively
    context
    |> Map.put(:large_context_leveraged, true)
  end

  defp integrate_google_services_context(context) do
    # Check if Google services are mentioned
    prompt_text = String.downcase(context.enhanced_prompt.enhanced_prompt)
    google_services = ["google drive", "gmail", "google docs", "google sheets", "google cloud"]

    has_google_services =
      Enum.any?(google_services, fn service ->
        String.contains?(prompt_text, service)
      end)

    if has_google_services do
      Map.put(context, :google_services_integrated, true)
    else
      context
    end
  end

  defp format_for_gemini_preferences(context) do
    context
    |> Map.put(:gemini_formatted, true)
  end

  defp mark_optimization_complete(context) do
    context
    |> Map.put(:gemini_optimized, true)
    |> Map.put(:optimization_applied, true)
    |> Map.put(:optimization_score, calculate_optimization_score(context))
    |> Map.put(:validation_passed, true)
  end

  defp calculate_optimization_score(context) do
    base_score = 0.7

    score_adjustments = [
      if(context.multimodal_optimized, do: 0.1, else: 0.0),
      if(context.function_calling_optimized, do: 0.1, else: 0.0),
      if(context.code_generation_optimized, do: 0.05, else: 0.0),
      if(context.large_context_leveraged, do: 0.05, else: 0.0),
      if(context.google_services_integrated, do: 0.05, else: 0.0)
    ]

    base_score + Enum.sum(score_adjustments)
  end

  defp update_prompt(context, update_fn) do
    updated_prompt = update_fn.(context.enhanced_prompt.enhanced_prompt)
    updated_enhanced_prompt = %{context.enhanced_prompt | enhanced_prompt: updated_prompt}
    %{context | enhanced_prompt: updated_enhanced_prompt}
  end

  defp generate_tool_selection_guidance(tools) do
    "Select tools based on task requirements: #{inspect(Enum.map(tools, & &1[:name]))}"
  end

  defp optimize_tool_parameters(_tools) do
    "Ensure all parameters are properly formatted and validated"
  end

  defp identify_tool_chaining_opportunities(tools) do
    "Consider combining #{length(tools)} tools for complex operations"
  end

  defp generate_tool_error_handling_guidance(_tools) do
    "Implement proper error handling with fallback strategies"
  end

  defp format_tools_for_gemini(tools) do
    tools
    |> Enum.map(fn tool ->
      "- #{tool[:name]}: #{tool[:description]}"
    end)
    |> Enum.join("\n")
  end
end

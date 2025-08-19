defmodule TheMaestro.Prompts.Enhancement.Pipeline do
  @moduledoc """
  Main prompt enhancement pipeline that orchestrates the multi-stage enhancement process.

  This module implements a sophisticated prompt enhancement system that intelligently
  augments user prompts with relevant context, environmental data, and task-specific
  information to improve AI response quality.
  """

  alias TheMaestro.Prompts.Enhancement.{
    Structs.EnhancementContext,
    Structs.EnhancedPrompt,
    PromptFormatter
  }

  alias TheMaestro.Prompts.Enhancement.Analyzers.{
    ContextAnalyzer,
    IntentDetector
  }

  alias TheMaestro.Prompts.Enhancement.Gatherers.ContextGatherer
  alias TheMaestro.Prompts.Enhancement.Scorers.{RelevanceScorer, QualityValidator}
  alias TheMaestro.Prompts.Enhancement.Integrators.ContextIntegrator
  alias TheMaestro.Prompts.Enhancement.Optimizers.EnhancementOptimizer

  require Logger

  @pipeline_stages [
    # Analyze prompt and context
    :context_analysis,
    # Detect user intent and goals
    :intent_detection,
    # Gather relevant contextual information
    :context_gathering,
    # Score and prioritize context elements
    :relevance_scoring,
    # Integrate context into prompt
    :context_integration,
    # Optimize enhanced prompt
    :optimization,
    # Validate enhanced prompt quality
    :validation,
    # Format for provider delivery
    :formatting
  ]

  @doc """
  Enhances a user prompt with contextual information and intelligent augmentation.

  ## Parameters

  - `original_prompt` - The user's original prompt string
  - `context` - User and environmental context map

  ## Returns

  An `EnhancedPrompt` struct with the original prompt, contextual enhancements,
  metadata about the enhancement process, and quality metrics.

  ## Examples

      iex> context = %{
      ...>   user_id: "user123",
      ...>   working_directory: "/app",
      ...>   environment: %{operating_system: "Darwin"},
      ...>   available_tools: [:read_file, :write_file]
      ...> }
      iex> result = Pipeline.enhance_prompt("Fix the auth bug", context)
      iex> is_binary(result.enhanced_prompt)
      true
  """
  @spec enhance_prompt(String.t(), map()) :: EnhancedPrompt.t()
  def enhance_prompt(original_prompt, context) do
    enhance_prompt_with_provider(original_prompt, context, nil)
  end

  @doc """
  Enhances a user prompt with contextual information and provider-specific optimization.

  ## Parameters

  - `original_prompt` - The user's original prompt string
  - `context` - User and environmental context map
  - `provider_info` - Optional provider information for optimization (%{provider: :anthropic, model: "claude-3-5-sonnet"})

  ## Returns

  An `EnhancedPrompt` struct with the original prompt, contextual enhancements,
  provider-specific optimizations, metadata about the enhancement process, and quality metrics.
  """
  @spec enhance_prompt_with_provider(String.t(), map(), map() | nil) :: EnhancedPrompt.t()
  def enhance_prompt_with_provider(original_prompt, context, provider_info) do
    start_time = System.monotonic_time(:millisecond)

    %EnhancementContext{
      original_prompt: original_prompt,
      user_context: context,
      enhancement_config: get_enhancement_config(context, provider_info),
      pipeline_state: %{}
    }
    |> run_enhancement_pipeline(@pipeline_stages)
    |> extract_enhanced_prompt()
    |> add_performance_metadata(start_time)
  end

  @doc """
  Runs the enhancement pipeline through the specified stages.

  Each stage processes the EnhancementContext and adds its results to the pipeline_state.
  """
  @spec run_enhancement_pipeline(EnhancementContext.t(), [atom()]) :: EnhancementContext.t()
  def run_enhancement_pipeline(context, stages) do
    Enum.reduce(stages, context, &execute_pipeline_stage/2)
  end

  # Private functions

  defp get_enhancement_config(context, provider_info) do
    base_config = %{
      max_context_items: Map.get(context, :max_context_items, 20),
      token_budget: Map.get(context, :token_budget, 4000),
      quality_threshold: Map.get(context, :quality_threshold, 0.75),
      relevance_threshold: Map.get(context, :relevance_threshold, 0.3),
      enable_caching: Map.get(context, :enable_caching, true),
      provider_optimization: Map.get(context, :provider_optimization, true)
    }

    if provider_info do
      base_config
      |> Map.put(:provider_info, provider_info)
      |> Map.put(:optimization_config, Map.get(context, :optimization_config, %{}))
    else
      base_config
    end
  end

  defp execute_pipeline_stage(stage, context) do
    try do
      case stage do
        :context_analysis ->
          ContextAnalyzer.analyze_context(context)

        :intent_detection ->
          intent_result = IntentDetector.detect_intent(context.original_prompt)
          put_in(context.pipeline_state[:intent_detection], intent_result)

        :context_gathering ->
          analysis = context.pipeline_state[:context_analysis]
          intent = context.pipeline_state[:intent_detection]

          gathered_context =
            ContextGatherer.gather_context(analysis, intent, context.user_context)

          put_in(context.pipeline_state[:context_gathering], gathered_context)

        :relevance_scoring ->
          analysis = context.pipeline_state[:context_analysis]
          gathered_context = context.pipeline_state[:context_gathering]
          scored_context = RelevanceScorer.score_context_relevance(gathered_context, analysis)
          put_in(context.pipeline_state[:relevance_scoring], scored_context)

        :context_integration ->
          scored_context = context.pipeline_state[:relevance_scoring]

          integrated_prompt =
            ContextIntegrator.integrate_context_into_prompt(
              context.original_prompt,
              scored_context,
              context.enhancement_config
            )

          put_in(context.pipeline_state[:context_integration], integrated_prompt)

        :optimization ->
          integrated_prompt = context.pipeline_state[:context_integration]

          optimized_prompt =
            EnhancementOptimizer.optimize_enhanced_prompt(
              integrated_prompt,
              context.enhancement_config
            )

          put_in(context.pipeline_state[:optimization], optimized_prompt)

        :validation ->
          optimized_prompt = context.pipeline_state[:optimization]
          validation_result = QualityValidator.validate_enhancement_quality(optimized_prompt)
          put_in(context.pipeline_state[:validation], validation_result)

        :formatting ->
          optimized_prompt = context.pipeline_state[:optimization]
          validation = context.pipeline_state[:validation]

          formatted_prompt =
            PromptFormatter.format_enhanced_prompt(
              optimized_prompt,
              validation,
              context.enhancement_config
            )

          put_in(context.pipeline_state[:formatting], formatted_prompt)

        _ ->
          Logger.warning("Unknown pipeline stage: #{stage}")
          context
      end
    rescue
      error ->
        Logger.error("Error in pipeline stage #{stage}: #{inspect(error)}")
        # Continue pipeline with error recorded
        error_info = %{stage: stage, error: error, timestamp: DateTime.utc_now()}
        errors = Map.get(context.pipeline_state, :errors, [])
        put_in(context.pipeline_state[:errors], [error_info | errors])
    end
  end

  defp extract_enhanced_prompt(context) do
    final_prompt = context.pipeline_state[:formatting]
    scored_context = context.pipeline_state[:relevance_scoring] || []
    validation = context.pipeline_state[:validation] || %{quality_score: 0.5}

    # Handle case where final_prompt is nil (formatting stage failed)
    formatted_result =
      case final_prompt do
        nil ->
          %{
            pre_context: "",
            enhanced_prompt: context.original_prompt,
            post_context: ""
          }

        result when is_map(result) ->
          result

        _ ->
          %{
            pre_context: "",
            enhanced_prompt: context.original_prompt,
            post_context: ""
          }
      end

    %EnhancedPrompt{
      original: context.original_prompt,
      pre_context: Map.get(formatted_result, :pre_context, ""),
      enhanced_prompt: Map.get(formatted_result, :enhanced_prompt, context.original_prompt),
      post_context: Map.get(formatted_result, :post_context, ""),
      metadata: build_metadata(context, validation),
      total_tokens: estimate_token_count(formatted_result),
      relevance_scores: extract_relevance_scores(scored_context)
    }
  end

  defp build_metadata(context, validation) do
    base_metadata = %{
      # Will be set by add_performance_metadata/2
      processing_time: 0,
      context_items_used: count_context_items(context),
      average_relevance_score: calculate_average_relevance(context),
      quality_score: Map.get(validation, :quality_score, 0.5),
      pipeline_errors: Map.get(context.pipeline_state, :errors, []),
      enhancement_config: context.enhancement_config
    }

    # Include optimization metadata if available
    optimization_result = context.pipeline_state[:optimization]
    if optimization_result && is_map(optimization_result) do
      optimization_metadata = Map.get(optimization_result, :metadata, %{})
      Map.merge(base_metadata, optimization_metadata)
    else
      base_metadata
    end
  end

  defp count_context_items(context) do
    scored_context = context.pipeline_state[:relevance_scoring] || []
    if is_list(scored_context), do: length(scored_context), else: 0
  end

  defp calculate_average_relevance(context) do
    scored_context = context.pipeline_state[:relevance_scoring] || []

    if is_list(scored_context) and length(scored_context) > 0 do
      scores =
        Enum.map(scored_context, fn item ->
          Map.get(item, :relevance_score, 0.0)
        end)

      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp estimate_token_count(prompt_parts) when is_map(prompt_parts) do
    content =
      [
        Map.get(prompt_parts, :pre_context, ""),
        Map.get(prompt_parts, :enhanced_prompt, ""),
        Map.get(prompt_parts, :post_context, "")
      ]
      |> Enum.join(" ")

    # Rough token estimation: ~4 characters per token
    round(String.length(content) / 4)
  end

  defp estimate_token_count(_), do: 0

  defp extract_relevance_scores(scored_context) when is_list(scored_context) do
    Enum.map(scored_context, fn item ->
      Map.get(item, :relevance_score, 0.0)
    end)
  end

  defp extract_relevance_scores(_), do: []

  defp add_performance_metadata(enhanced_prompt, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    updated_metadata = Map.put(enhanced_prompt.metadata, :processing_time, processing_time)

    %{enhanced_prompt | metadata: updated_metadata}
  end
end

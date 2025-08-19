defmodule TheMaestro.Prompts.Enhancement.Optimizers.EnhancementOptimizer do
  @moduledoc """
  Optimization engine for enhanced prompts focusing on token efficiency and quality.
  """

  alias TheMaestro.Prompts.Optimization.ProviderOptimizer
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  
  require Logger

  @doc """
  Optimizes enhanced prompts for performance and quality.
  """
  @spec optimize_enhanced_prompt(map(), map()) :: map()
  def optimize_enhanced_prompt(enhanced_prompt, provider_config) do
    enhanced_prompt
    |> optimize_for_token_budget(provider_config)
    |> optimize_for_provider_preferences(provider_config)
    |> optimize_for_response_quality(provider_config)
  end

  defp optimize_for_token_budget(prompt, config) do
    max_tokens = Map.get(config, :token_budget, 4000)
    current_tokens = Map.get(prompt, :total_tokens, 0)

    if current_tokens > max_tokens do
      # Simple truncation optimization
      truncate_context_sections(prompt, max_tokens)
    else
      prompt
    end
  end

  defp optimize_for_provider_preferences(prompt, config) do
    # Check if provider-specific optimization is enabled and provider info is available
    if Map.get(config, :provider_optimization, false) and Map.has_key?(config, :provider_info) do
      apply_provider_specific_optimization(prompt, config)
    else
      prompt
    end
  end

  defp apply_provider_specific_optimization(prompt, config) do
    # Convert the enhanced prompt to the structure expected by ProviderOptimizer
    enhanced_prompt_struct = %EnhancedPrompt{
      enhanced_prompt: Map.get(prompt, :enhanced_prompt, ""),
      original: Map.get(prompt, :original, ""),
      pre_context: Map.get(prompt, :pre_context, ""),
      post_context: Map.get(prompt, :post_context, ""),
      metadata: Map.get(prompt, :metadata, %{}),
      total_tokens: Map.get(prompt, :total_tokens, 0),
      relevance_scores: Map.get(prompt, :relevance_scores, [])
    }

    provider_info = Map.get(config, :provider_info, %{})
    optimization_config = Map.get(config, :optimization_config, %{})

    try do
      # Apply provider-specific optimization
      case ProviderOptimizer.optimize_for_provider(
        enhanced_prompt_struct,
        provider_info,
        optimization_config
      ) do
        {:ok, optimized_context} ->
          # Convert back to the map format expected by the pipeline
          %{
            prompt
            | enhanced_prompt: optimized_context.enhanced_prompt.enhanced_prompt,
              pre_context: optimized_context.enhanced_prompt.pre_context,
              post_context: optimized_context.enhanced_prompt.post_context,
              metadata: Map.merge(
                Map.get(prompt, :metadata, %{}),
                Map.merge(
                  optimized_context.enhanced_prompt.metadata,
                  %{provider_optimization_applied: true, optimization_score: optimized_context.optimization_score}
                )
              )
          }

        {:error, reason} ->
          Logger.warning("Provider optimization failed: #{inspect(reason)}")
          Map.put(prompt, :provider_optimization_failed, true)
      end
    rescue
      error ->
        # Fall back to original prompt if optimization fails
        Logger.warning("Provider optimization failed: #{inspect(error)}")
        Map.put(prompt, :provider_optimization_failed, true)
    end
  end

  defp optimize_for_response_quality(prompt, _config) do
    # Placeholder for quality optimizations
    prompt
  end

  defp truncate_context_sections(prompt, _max_tokens) do
    # Simple truncation by reducing context sections
    %{
      prompt
      | pre_context: String.slice(Map.get(prompt, :pre_context, ""), 0, 500),
        post_context: String.slice(Map.get(prompt, :post_context, ""), 0, 200)
    }
  end
end

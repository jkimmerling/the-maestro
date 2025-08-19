defmodule TheMaestro.Prompts.Optimization.Monitoring.EffectivenessTracker do
  @moduledoc """
  Tracks and monitors the effectiveness of prompt optimizations.

  Measures optimization impact across multiple dimensions including token usage,
  response quality, latency, error rates, and user satisfaction.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt

  @doc """
  Tracks comprehensive optimization effectiveness metrics.
  """
  @spec track_optimization_effectiveness(
          EnhancedPrompt.t(),
          EnhancedPrompt.t(),
          map(),
          map()
        ) :: map()
  def track_optimization_effectiveness(
        original_prompt,
        optimized_prompt,
        provider_info,
        response_data
      ) do
    metrics = %{
      token_reduction: calculate_token_reduction(original_prompt, optimized_prompt),
      response_quality_improvement: measure_quality_improvement(response_data),
      latency_impact: measure_latency_impact(response_data),
      error_rate_change: measure_error_rate_change(response_data),
      user_satisfaction_delta: measure_satisfaction_delta(response_data),
      cost_impact: calculate_cost_impact(original_prompt, optimized_prompt, response_data),
      token_efficiency_gain:
        calculate_token_efficiency_gain(original_prompt, optimized_prompt, response_data)
    }

    # Emit telemetry for monitoring
    :telemetry.execute(
      [:maestro, :prompt_optimization],
      metrics,
      %{provider: provider_info.provider, model: provider_info.model}
    )

    # Store results for adaptive learning
    storage_result = store_optimization_results(provider_info, metrics)

    Map.put(metrics, :stored_for_learning, storage_result.stored_successfully)
    |> Map.put(:learning_data_id, storage_result[:storage_key])
  end

  @doc """
  Calculates percentage token reduction from optimization.
  """
  @spec calculate_token_reduction(EnhancedPrompt.t(), EnhancedPrompt.t()) :: float()
  def calculate_token_reduction(original_prompt, optimized_prompt) do
    original_tokens = estimate_token_count(original_prompt.enhanced_prompt)
    optimized_tokens = estimate_token_count(optimized_prompt.enhanced_prompt)

    if original_tokens == 0 do
      0.0
    else
      (original_tokens - optimized_tokens) / original_tokens
    end
  end

  @doc """
  Measures response quality improvement from response data.
  """
  @spec measure_quality_improvement(map()) :: float()
  def measure_quality_improvement(response_data) do
    case response_data do
      %{response_quality_score: current, baseline_quality_score: baseline} ->
        current - baseline

      %{response_quality_score: current} ->
        # Estimate improvement based on optimization presence
        # This is a heuristic when baseline is not available
        # Assume baseline of 0.7
        current - 0.7

      %{coherence_score: coherence, relevance_score: relevance, completeness_score: completeness} ->
        # Calculate composite quality score
        composite_current = (coherence + relevance + completeness) / 3
        # Assume baseline of 0.7
        composite_current - 0.7

      _ ->
        0.0
    end
  end

  @doc """
  Measures latency impact from optimization.
  """
  @spec measure_latency_impact(map()) :: float()
  def measure_latency_impact(response_data) do
    case response_data do
      %{response_time_ms: current, baseline_response_time_ms: baseline} ->
        # Negative indicates improvement
        (current - baseline) / baseline

      %{
        processing_time_ms: processing,
        network_time_ms: network,
        baseline_response_time_ms: baseline
      } ->
        current = processing + network
        (current - baseline) / baseline

      _ ->
        0.0
    end
  end

  @doc """
  Measures error rate change from optimization.
  """
  @spec measure_error_rate_change(map()) :: float()
  def measure_error_rate_change(response_data) do
    case response_data do
      %{current_error_rate: current, baseline_error_rate: baseline} ->
        # Negative indicates improvement
        current - baseline

      %{error_occurred: false, baseline_error_rate: baseline} ->
        # Current success, so error rate is 0
        0.0 - baseline

      %{error_occurred: true, baseline_error_rate: baseline} ->
        # Current error, so error rate is 1
        1.0 - baseline

      %{error_occurred: false} ->
        # Single successful response - assign small positive impact
        -0.05

      %{error_occurred: true} ->
        # Single error - assign small negative impact
        0.05

      _ ->
        0.0
    end
  end

  @doc """
  Measures user satisfaction delta from optimization.
  """
  @spec measure_satisfaction_delta(map()) :: float()
  def measure_satisfaction_delta(response_data) do
    case response_data do
      %{user_satisfaction: current, baseline_satisfaction: baseline} ->
        current - baseline

      %{satisfaction_factors: factors} ->
        # Calculate average satisfaction from factors
        factor_values = Map.values(factors)
        avg_satisfaction = Enum.sum(factor_values) / length(factor_values)
        # Assume baseline of 3.5 (neutral)
        avg_satisfaction - 3.5

      %{
        response_quality_score: quality,
        user_engagement_score: engagement,
        task_completion_rate: completion
      } ->
        # Infer satisfaction from quality metrics
        inferred_satisfaction = (quality * 5 + engagement * 5 + completion * 5) / 3
        # Assume baseline of 3.5
        inferred_satisfaction - 3.5

      _ ->
        0.0
    end
  end

  @doc """
  Stores optimization results for learning and analysis.
  """
  @spec store_optimization_results(map(), map()) :: map()
  def store_optimization_results(provider_info, metrics) do
    storage_key = "#{provider_info.provider}:#{provider_info.model}"

    # In a real implementation, this would store to a database or cache
    # For now, simulate storage and aggregation

    # Simulate retrieving existing aggregated data
    existing_metrics = get_existing_aggregated_metrics(storage_key)

    # Calculate new aggregated metrics
    aggregated_metrics = %{
      avg_token_reduction:
        calculate_average(existing_metrics[:token_reduction], metrics.token_reduction),
      avg_quality_improvement:
        calculate_average(
          existing_metrics[:quality_improvement],
          metrics.response_quality_improvement
        ),
      avg_latency_impact:
        calculate_average(existing_metrics[:latency_impact], metrics.latency_impact),
      avg_error_rate_change:
        calculate_average(existing_metrics[:error_rate_change], metrics.error_rate_change),
      avg_satisfaction_delta:
        calculate_average(existing_metrics[:satisfaction_delta], metrics.user_satisfaction_delta),
      total_optimizations: (existing_metrics[:count] || 0) + 1
    }

    # Store the updated aggregated metrics back to ETS
    updated_storage_metrics = %{
      token_reduction: aggregated_metrics.avg_token_reduction,
      quality_improvement: aggregated_metrics.avg_quality_improvement,
      latency_impact: aggregated_metrics.avg_latency_impact,
      error_rate_change: aggregated_metrics.avg_error_rate_change,
      satisfaction_delta: aggregated_metrics.avg_satisfaction_delta,
      count: aggregated_metrics.total_optimizations
    }

    :ets.insert(__MODULE__, {storage_key, updated_storage_metrics})

    %{
      stored_successfully: true,
      storage_key: storage_key,
      metrics_stored: metrics,
      aggregated_metrics: aggregated_metrics,
      stored_at: DateTime.utc_now()
    }
  end

  # Private functions

  defp estimate_token_count(text) do
    # Simple estimation: roughly 4 characters per token
    String.length(text) |> div(4)
  end

  defp calculate_cost_impact(original_prompt, optimized_prompt, response_data) do
    original_cost = estimate_cost(original_prompt, response_data)
    optimized_cost = estimate_cost(optimized_prompt, response_data)

    # Positive indicates cost savings
    original_cost - optimized_cost
  end

  defp calculate_token_efficiency_gain(original_prompt, optimized_prompt, response_data) do
    original_tokens = estimate_token_count(original_prompt.enhanced_prompt)
    optimized_tokens = estimate_token_count(optimized_prompt.enhanced_prompt)

    quality_score = Map.get(response_data, :response_quality_score, 0.8)

    if original_tokens > 0 do
      original_efficiency = quality_score / original_tokens
      optimized_efficiency = quality_score / max(optimized_tokens, 1)

      optimized_efficiency - original_efficiency
    else
      0.0
    end
  end

  defp estimate_cost(prompt, response_data) do
    tokens = estimate_token_count(prompt.enhanced_prompt)
    cost_per_token = Map.get(response_data, :cost_per_token, 0.0001)

    tokens * cost_per_token
  end

  defp get_existing_aggregated_metrics(storage_key) do
    # In a real implementation, this would query a database or ETS table
    # For now, we maintain a simple in-memory store for testing consistency
    case :ets.whereis(__MODULE__) do
      :undefined ->
        :ets.new(__MODULE__, [:named_table, :public, :set])
        %{count: 0}

      _ ->
        case :ets.lookup(__MODULE__, storage_key) do
          [{_key, metrics}] -> metrics
          [] -> %{count: 0}
        end
    end
  end

  defp calculate_average(existing_value, new_value) when is_nil(existing_value) do
    new_value
  end

  defp calculate_average(existing_value, new_value) do
    # Simple average - in real implementation would use proper weighted averaging
    (existing_value + new_value) / 2
  end
end

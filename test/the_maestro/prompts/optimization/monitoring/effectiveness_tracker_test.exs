defmodule TheMaestro.Prompts.Optimization.Monitoring.EffectivenessTrackerTest do
  # Changed to false because we're using a shared ETS table
  use ExUnit.Case, async: false

  alias TheMaestro.Prompts.Optimization.Monitoring.EffectivenessTracker
  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt

  setup do
    # Clean up ETS table before each test
    case :ets.whereis(EffectivenessTracker) do
      :undefined -> :ok
      _table -> :ets.delete_all_objects(EffectivenessTracker)
    end

    :ok
  end

  describe "track_optimization_effectiveness/4" do
    test "calculates and tracks comprehensive optimization metrics" do
      original_prompt = %EnhancedPrompt{
        enhanced_prompt: String.duplicate("Original content ", 100)
      }

      optimized_prompt = %EnhancedPrompt{
        enhanced_prompt: String.duplicate("Optimized content ", 80)
      }

      provider_info = %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }

      response_data = %{
        response_quality_score: 0.85,
        response_time_ms: 1500,
        error_occurred: false,
        user_satisfaction: 4.2,
        token_count: 1200,
        cost_usd: 0.024
      }

      result =
        EffectivenessTracker.track_optimization_effectiveness(
          original_prompt,
          optimized_prompt,
          provider_info,
          response_data
        )

      assert result.token_reduction > 0
      assert result.response_quality_improvement >= 0
      assert result.latency_impact != nil
      assert result.error_rate_change != nil
      assert result.user_satisfaction_delta != nil
      assert result.cost_impact != nil
    end

    test "detects quality improvements from optimization" do
      original_prompt = %EnhancedPrompt{enhanced_prompt: "Simple prompt"}

      optimized_prompt = %EnhancedPrompt{
        enhanced_prompt: "Well-structured, detailed prompt with clear instructions"
      }

      provider_info = %{provider: :openai, model: "gpt-4o"}

      response_data = %{
        response_quality_score: 0.9,
        baseline_quality_score: 0.7,
        response_time_ms: 2000,
        baseline_response_time_ms: 2500,
        error_occurred: false,
        baseline_error_rate: 0.05
      }

      result =
        EffectivenessTracker.track_optimization_effectiveness(
          original_prompt,
          optimized_prompt,
          provider_info,
          response_data
        )

      assert result.response_quality_improvement > 0
      # Negative means improvement (faster)
      assert result.latency_impact < 0
    end

    test "tracks token reduction from optimization" do
      original_prompt = %EnhancedPrompt{
        enhanced_prompt: String.duplicate("Repetitive content. ", 1000)
      }

      optimized_prompt = %EnhancedPrompt{
        enhanced_prompt: String.duplicate("Condensed content. ", 500)
      }

      provider_info = %{provider: :google, model: "gemini-1.5-pro"}
      response_data = %{response_quality_score: 0.8}

      result =
        EffectivenessTracker.track_optimization_effectiveness(
          original_prompt,
          optimized_prompt,
          provider_info,
          response_data
        )

      # Should show significant reduction
      assert result.token_reduction > 0.4
      assert result.token_efficiency_gain > 0
    end

    test "emits telemetry events for monitoring" do
      original_prompt = %EnhancedPrompt{enhanced_prompt: "Test prompt"}
      optimized_prompt = %EnhancedPrompt{enhanced_prompt: "Optimized test prompt"}

      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}
      response_data = %{response_quality_score: 0.8}

      # Capture telemetry events
      :telemetry.attach(
        "test_handler",
        [:maestro, :prompt_optimization],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      EffectivenessTracker.track_optimization_effectiveness(
        original_prompt,
        optimized_prompt,
        provider_info,
        response_data
      )

      assert_receive {:telemetry_event, [:maestro, :prompt_optimization], measurements, metadata}
      assert measurements.token_reduction != nil
      assert metadata.provider == :anthropic
      assert metadata.model == "claude-3-5-sonnet-20241022"

      :telemetry.detach("test_handler")
    end

    test "stores results for adaptive learning" do
      original_prompt = %EnhancedPrompt{enhanced_prompt: "Learning prompt"}
      optimized_prompt = %EnhancedPrompt{enhanced_prompt: "Optimized learning prompt"}

      provider_info = %{provider: :openai, model: "gpt-4o"}
      response_data = %{response_quality_score: 0.85}

      result =
        EffectivenessTracker.track_optimization_effectiveness(
          original_prompt,
          optimized_prompt,
          provider_info,
          response_data
        )

      assert result.stored_for_learning == true
      assert result.learning_data_id != nil
    end
  end

  describe "calculate_token_reduction/2" do
    test "calculates percentage token reduction" do
      original_prompt = %EnhancedPrompt{
        # ~1000 tokens
        enhanced_prompt: String.duplicate("word ", 1000)
      }

      optimized_prompt = %EnhancedPrompt{
        # ~800 tokens
        enhanced_prompt: String.duplicate("word ", 800)
      }

      reduction =
        EffectivenessTracker.calculate_token_reduction(original_prompt, optimized_prompt)

      # ~20% reduction
      assert reduction > 0.15 and reduction < 0.25
    end

    test "handles cases where optimization increases token count" do
      original_prompt = %EnhancedPrompt{enhanced_prompt: "Short"}

      optimized_prompt = %EnhancedPrompt{
        enhanced_prompt: "Much longer and more detailed optimized prompt"
      }

      reduction =
        EffectivenessTracker.calculate_token_reduction(original_prompt, optimized_prompt)

      # Negative indicates increase
      assert reduction < 0
    end

    test "returns zero for identical prompts" do
      prompt = %EnhancedPrompt{enhanced_prompt: "Same prompt"}

      reduction = EffectivenessTracker.calculate_token_reduction(prompt, prompt)

      assert reduction == 0.0
    end
  end

  describe "measure_quality_improvement/1" do
    test "calculates quality improvement from response data" do
      response_data = %{
        response_quality_score: 0.9,
        baseline_quality_score: 0.7,
        coherence_score: 0.85,
        relevance_score: 0.88,
        completeness_score: 0.92
      }

      improvement = EffectivenessTracker.measure_quality_improvement(response_data)

      # Significant improvement
      assert improvement > 0.15
    end

    test "handles missing baseline scores" do
      response_data = %{
        response_quality_score: 0.8,
        # No baseline_quality_score
        coherence_score: 0.75
      }

      improvement = EffectivenessTracker.measure_quality_improvement(response_data)

      # Should use heuristic estimation when baseline unavailable
      assert is_float(improvement)
    end

    test "returns zero when no quality data available" do
      response_data = %{}

      improvement = EffectivenessTracker.measure_quality_improvement(response_data)

      assert improvement == 0.0
    end
  end

  describe "measure_latency_impact/1" do
    test "calculates latency change from response data" do
      response_data = %{
        response_time_ms: 1800,
        baseline_response_time_ms: 2200,
        processing_time_ms: 1500,
        network_time_ms: 300
      }

      latency_impact = EffectivenessTracker.measure_latency_impact(response_data)

      # Negative indicates improvement (faster)
      assert latency_impact < 0
      # Significant improvement
      assert abs(latency_impact) > 0.1
    end

    test "handles cases where optimization increases latency" do
      response_data = %{
        response_time_ms: 3000,
        baseline_response_time_ms: 2000
      }

      latency_impact = EffectivenessTracker.measure_latency_impact(response_data)

      # Positive indicates degradation (slower)
      assert latency_impact > 0
    end

    test "returns zero when no timing data available" do
      response_data = %{}

      latency_impact = EffectivenessTracker.measure_latency_impact(response_data)

      assert latency_impact == 0.0
    end
  end

  describe "measure_error_rate_change/1" do
    test "calculates error rate change from response data" do
      response_data = %{
        error_occurred: false,
        baseline_error_rate: 0.1,
        current_error_rate: 0.05,
        error_type_distribution: %{
          timeout: 0.02,
          validation: 0.02,
          parsing: 0.01
        }
      }

      error_rate_change = EffectivenessTracker.measure_error_rate_change(response_data)

      # Negative indicates improvement (fewer errors)
      assert error_rate_change < 0
    end

    test "handles single response error status" do
      response_data = %{
        error_occurred: true,
        error_type: :validation_error
      }

      error_rate_change = EffectivenessTracker.measure_error_rate_change(response_data)

      # Single error should be weighted appropriately
      assert is_float(error_rate_change)
    end
  end

  describe "measure_satisfaction_delta/1" do
    test "calculates user satisfaction change" do
      response_data = %{
        user_satisfaction: 4.3,
        baseline_satisfaction: 3.8,
        satisfaction_factors: %{
          response_relevance: 4.5,
          response_clarity: 4.2,
          response_completeness: 4.1
        }
      }

      satisfaction_delta = EffectivenessTracker.measure_satisfaction_delta(response_data)

      # Significant improvement
      assert satisfaction_delta > 0.4
    end

    test "handles implicit satisfaction metrics" do
      response_data = %{
        response_quality_score: 0.9,
        user_engagement_score: 0.85,
        task_completion_rate: 0.95
      }

      satisfaction_delta = EffectivenessTracker.measure_satisfaction_delta(response_data)

      # Should infer satisfaction from quality metrics
      assert is_float(satisfaction_delta)
    end
  end

  describe "store_optimization_results/2" do
    test "stores optimization metrics for provider" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet-20241022"}

      metrics = %{
        token_reduction: 0.25,
        response_quality_improvement: 0.15,
        latency_impact: -0.1,
        error_rate_change: -0.05,
        user_satisfaction_delta: 0.3
      }

      result = EffectivenessTracker.store_optimization_results(provider_info, metrics)

      assert result.stored_successfully == true
      assert result.storage_key == "anthropic:claude-3-5-sonnet-20241022"
      assert result.metrics_stored == metrics
    end

    test "aggregates metrics with existing provider data" do
      provider_info = %{provider: :openai, model: "gpt-4o"}

      # Store first set of metrics
      metrics_1 = %{
        token_reduction: 0.2,
        response_quality_improvement: 0.1,
        latency_impact: 0.05,
        error_rate_change: -0.02,
        user_satisfaction_delta: 0.15
      }

      EffectivenessTracker.store_optimization_results(provider_info, metrics_1)

      # Store second set of metrics
      metrics_2 = %{
        token_reduction: 0.3,
        response_quality_improvement: 0.2,
        latency_impact: 0.1,
        error_rate_change: -0.05,
        user_satisfaction_delta: 0.25
      }

      result = EffectivenessTracker.store_optimization_results(provider_info, metrics_2)

      assert result.aggregated_metrics.avg_token_reduction == 0.25
      # Use approximate comparison due to floating point precision
      assert_in_delta result.aggregated_metrics.avg_quality_improvement, 0.15, 0.01
    end
  end
end

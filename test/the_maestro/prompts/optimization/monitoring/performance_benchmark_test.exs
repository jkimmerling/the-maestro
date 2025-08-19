defmodule TheMaestro.Prompts.Optimization.Monitoring.PerformanceBenchmarkTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.Monitoring.PerformanceBenchmark

  describe "baseline metrics" do
    test "establish_baseline_metrics/0 returns metrics for all providers" do
      # Mock the benchmark system to avoid long-running tests
      baseline_metrics = PerformanceBenchmark.establish_baseline_metrics()

      assert is_map(baseline_metrics)
      assert Map.has_key?(baseline_metrics, :anthropic)
      assert Map.has_key?(baseline_metrics, :google)
      assert Map.has_key?(baseline_metrics, :openai)

      # Verify each provider has test case metrics
      Enum.each([:anthropic, :google, :openai], fn provider ->
        provider_metrics = baseline_metrics[provider]
        assert is_map(provider_metrics)
        assert Map.has_key?(provider_metrics, "simple_instruction")
        assert Map.has_key?(provider_metrics, "complex_reasoning")
      end)
    end

    test "measure_baseline_performance/2 returns valid metrics structure" do
      test_case = %{
        name: "test_case",
        prompt: "Test prompt",
        complexity: :low
      }

      metrics = PerformanceBenchmark.measure_baseline_performance(test_case, :anthropic)

      assert is_map(metrics)
      assert is_number(metrics.token_count)
      assert is_number(metrics.response_time_ms)
      assert is_number(metrics.quality_score)
      assert is_number(metrics.coherence_score)
      assert is_number(metrics.relevance_score)
      assert is_number(metrics.completeness_score)
      assert is_boolean(metrics.error_occurred)
      assert is_number(metrics.cost_estimate)
      assert %DateTime{} = metrics.measured_at
    end
  end

  describe "optimization benchmarks" do
    test "run_provider_optimization_benchmarks/0 returns optimization results" do
      optimization_results = PerformanceBenchmark.run_provider_optimization_benchmarks()

      assert is_map(optimization_results)
      assert Map.has_key?(optimization_results, :anthropic)
      assert Map.has_key?(optimization_results, :google)
      assert Map.has_key?(optimization_results, :openai)

      # Verify structure of optimization results
      anthropic_results = optimization_results[:anthropic]
      assert is_map(anthropic_results)
      assert Map.has_key?(anthropic_results, "simple_instruction")
    end

    test "measure_optimization_performance/2 returns comprehensive metrics" do
      test_case = %{
        name: "test_optimization",
        prompt: "Create a simple function",
        complexity: :medium
      }

      metrics = PerformanceBenchmark.measure_optimization_performance(test_case, :anthropic)

      assert is_map(metrics)
      assert is_number(metrics.original_token_count)
      assert is_number(metrics.optimized_token_count)
      assert is_number(metrics.optimization_time_ms)
      assert is_number(metrics.response_time_ms)
      assert is_number(metrics.total_time_ms)
      assert is_number(metrics.quality_score)
      assert is_boolean(metrics.error_occurred)
      assert is_map(metrics.effectiveness_metrics)
      assert is_map(metrics.optimization_metadata)
      assert %DateTime{} = metrics.measured_at
    end
  end

  describe "result analysis" do
    test "compare_optimization_results/2 generates comparison insights" do
      baseline_metrics = %{
        anthropic: %{
          "test_case" => %{
            token_count: 100,
            response_time_ms: 1000,
            quality_score: 0.8,
            cost_estimate: 0.01
          }
        }
      }

      optimization_metrics = %{
        anthropic: %{
          "test_case" => %{
            optimized_token_count: 80,
            response_time_ms: 800,
            total_time_ms: 850,
            quality_score: 0.85,
            cost_estimate: 0.008
          }
        }
      }

      comparison =
        PerformanceBenchmark.compare_optimization_results(baseline_metrics, optimization_metrics)

      assert is_map(comparison)
      assert Map.has_key?(comparison, :anthropic)

      anthropic_comparison = comparison[:anthropic]["test_case"]
      assert is_number(anthropic_comparison.token_reduction)
      assert is_number(anthropic_comparison.quality_improvement)
      assert is_number(anthropic_comparison.latency_impact)
      assert is_number(anthropic_comparison.cost_savings)
      assert is_number(anthropic_comparison.overall_effectiveness)

      # Verify calculations
      # 20% reduction
      assert anthropic_comparison.token_reduction == 0.2
      # 0.85 - 0.8
      assert_in_delta anthropic_comparison.quality_improvement, 0.05, 0.001
      # Should save money
      assert anthropic_comparison.cost_savings > 0
    end

    test "generate_performance_summary/1 creates comprehensive summary" do
      comparison_results = %{
        anthropic: %{
          "test1" => %{
            overall_effectiveness: 0.15,
            token_reduction: 0.2,
            quality_improvement: 0.05
          },
          "test2" => %{
            overall_effectiveness: 0.10,
            token_reduction: 0.1,
            quality_improvement: 0.03
          }
        },
        google: %{
          "test1" => %{
            overall_effectiveness: 0.12,
            token_reduction: 0.15,
            quality_improvement: 0.04
          },
          "test2" => %{
            overall_effectiveness: 0.08,
            token_reduction: 0.05,
            quality_improvement: 0.02
          }
        }
      }

      summary = PerformanceBenchmark.generate_performance_summary(comparison_results)

      assert is_map(summary)
      assert is_number(summary.overall_token_reduction)
      assert is_number(summary.overall_quality_improvement)
      assert is_atom(summary.best_performing_provider)
      assert is_map(summary.optimization_effectiveness_by_complexity)
      assert is_map(summary.recommended_configurations)

      # Anthropic should be best performing provider
      assert summary.best_performing_provider == :anthropic
    end
  end

  describe "comprehensive benchmark" do
    # Skip by default due to long runtime
    @tag :skip
    test "run_comprehensive_benchmark/0 completes successfully" do
      results = PerformanceBenchmark.run_comprehensive_benchmark()

      assert is_map(results)
      assert %DateTime{} = results.started_at
      assert %DateTime{} = results.completed_at
      assert is_map(results.baseline_metrics)
      assert is_map(results.optimization_metrics)
      assert is_map(results.comparison_results)
      assert is_map(results.performance_summary)

      # Verify all providers were tested
      assert Map.has_key?(results.baseline_metrics, :anthropic)
      assert Map.has_key?(results.baseline_metrics, :google)
      assert Map.has_key?(results.baseline_metrics, :openai)
    end
  end

  describe "helper functions" do
    test "token reduction calculation is correct" do
      baseline = %{
        token_count: 100,
        response_time_ms: 1000,
        quality_score: 0.8,
        cost_estimate: 0.01
      }

      optimization = %{
        optimized_token_count: 80,
        response_time_ms: 800,
        quality_score: 0.85,
        cost_estimate: 0.008
      }

      # Test private function through public interface
      comparison_results = %{
        anthropic: %{"test" => optimization}
      }

      baseline_results = %{
        anthropic: %{"test" => baseline}
      }

      comparison =
        PerformanceBenchmark.compare_optimization_results(baseline_results, comparison_results)

      result = comparison[:anthropic]["test"]

      # (100-80)/100 = 0.2
      assert result.token_reduction == 0.2
      # 0.85 - 0.8
      assert_in_delta result.quality_improvement, 0.05, 0.001
      assert result.cost_savings > 0
    end
  end
end

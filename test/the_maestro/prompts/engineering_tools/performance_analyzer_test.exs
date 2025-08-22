defmodule TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzer
  alias TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzer.{
    PerformanceAnalysis,
    PerformanceMetrics,
    OptimizationSuggestion
  }

  describe "analyze_prompt_performance/3" do
    setup do
      prompt = "You are a {{role | default: assistant}}. Help with {{task | required}}."
      execution_context = %{provider: :openai, model: "gpt-4", environment: :production}
      
      historical_data = [
        %{
          timestamp: DateTime.utc_now() |> DateTime.add(-7, :day),
          provider: :openai,
          model: "gpt-4",
          response_time: 1200,
          token_usage: %{input: 50, output: 150, total: 200},
          quality_score: 0.85,
          success: true,
          parameters: %{"role" => "assistant", "task" => "code review"}
        },
        %{
          timestamp: DateTime.utc_now() |> DateTime.add(-6, :day),
          provider: :anthropic,
          model: "claude-3-sonnet",
          response_time: 950,
          token_usage: %{input: 48, output: 180, total: 228},
          quality_score: 0.92,
          success: true,
          parameters: %{"role" => "expert", "task" => "bug analysis"}
        }
      ]

      {:ok, prompt: prompt, execution_context: execution_context, historical_data: historical_data}
    end

    test "returns a valid PerformanceAnalysis struct", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      assert %PerformanceAnalysis{} = analysis
      assert is_binary(analysis.prompt_id)
      assert %DateTime{} = analysis.analysis_timestamp
      assert is_map(analysis.response_time_metrics)
      assert is_map(analysis.response_quality_metrics)
      assert is_map(analysis.latency_analysis)
      assert is_map(analysis.token_efficiency)
      assert is_map(analysis.resource_utilization)
      assert is_map(analysis.bottleneck_analysis)
      assert is_list(analysis.optimization_recommendations)
      assert is_number(analysis.performance_score)
      assert is_map(analysis.historical_comparison)
      assert is_map(analysis.real_time_monitoring)
      assert is_map(analysis.scalability_assessment)
      assert is_map(analysis.cost_analysis)
    end

    test "analyzes response quality metrics", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      quality_metrics = analysis.response_quality_metrics

      assert Map.has_key?(quality_metrics, :average_quality_score)
      assert Map.has_key?(quality_metrics, :quality_distribution)
      assert Map.has_key?(quality_metrics, :consistency_score)
      assert Map.has_key?(quality_metrics, :improvement_potential)

      assert quality_metrics.average_quality_score > 0
      assert quality_metrics.average_quality_score <= 1
      assert quality_metrics.consistency_score >= 0
      assert quality_metrics.consistency_score <= 1
    end

    test "analyzes response time metrics", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      response_time_metrics = analysis.response_time_metrics

      assert Map.has_key?(response_time_metrics, :mean)
      assert Map.has_key?(response_time_metrics, :median)
      assert Map.has_key?(response_time_metrics, :p95)
      assert Map.has_key?(response_time_metrics, :p99)
      assert Map.has_key?(response_time_metrics, :std_dev)

      assert response_time_metrics.mean > 0
      assert response_time_metrics.median > 0
      assert response_time_metrics.p95 > 0
      assert response_time_metrics.p99 > 0
      assert response_time_metrics.std_dev >= 0
    end

    test "analyzes latency patterns", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      latency_analysis = analysis.latency_analysis

      assert Map.has_key?(latency_analysis, :average_response_time)
      assert Map.has_key?(latency_analysis, :median_response_time)
      assert Map.has_key?(latency_analysis, :p95_response_time)
      assert Map.has_key?(latency_analysis, :response_time_by_provider)
      assert Map.has_key?(latency_analysis, :latency_trends)

      assert latency_analysis.average_response_time > 0
      assert is_number(latency_analysis.median_response_time)
      assert is_number(latency_analysis.p95_response_time)
      assert is_map(latency_analysis.response_time_by_provider)
      assert is_map(latency_analysis.latency_trends)
    end

    test "analyzes token efficiency", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      token_efficiency = analysis.token_efficiency

      assert Map.has_key?(token_efficiency, :input_tokens)
      assert Map.has_key?(token_efficiency, :output_tokens)
      assert Map.has_key?(token_efficiency, :efficiency_ratio)
      assert Map.has_key?(token_efficiency, :token_waste_indicators)

      assert is_integer(token_efficiency.input_tokens)
      assert is_integer(token_efficiency.output_tokens)
      assert is_number(token_efficiency.efficiency_ratio)
      assert is_list(token_efficiency.token_waste_indicators)
    end

    test "analyzes resource utilization", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      resource_utilization = analysis.resource_utilization

      assert Map.has_key?(resource_utilization, :cpu_usage)
      assert Map.has_key?(resource_utilization, :memory_usage)
      assert Map.has_key?(resource_utilization, :network_io)
      assert Map.has_key?(resource_utilization, :cache_hit_rate)

      assert is_number(resource_utilization.cpu_usage)
      assert is_number(resource_utilization.memory_usage)
      assert is_integer(resource_utilization.network_io)
      assert is_number(resource_utilization.cache_hit_rate)
    end

    test "identifies performance bottlenecks", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      bottleneck_analysis = analysis.bottleneck_analysis

      assert Map.has_key?(bottleneck_analysis, :identified_bottlenecks)
      assert Map.has_key?(bottleneck_analysis, :severity_scores)
      assert Map.has_key?(bottleneck_analysis, :resolution_priorities)

      assert is_list(bottleneck_analysis.identified_bottlenecks)
      assert is_map(bottleneck_analysis.severity_scores)
      assert is_list(bottleneck_analysis.resolution_priorities)
    end

    test "generates optimization recommendations", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      recommendations = analysis.optimization_recommendations

      assert is_list(recommendations)
      assert length(recommendations) > 0

      # Check that each recommendation is valid
      Enum.each(recommendations, fn recommendation ->
        assert %OptimizationSuggestion{} = recommendation
        assert is_binary(recommendation.suggestion_id)
        assert recommendation.optimization_type in [:token_efficiency, :response_time, :resource_usage, :caching, :architectural, :context_chunking, :batching, :token_optimization, :token_reduction]
        assert is_binary(recommendation.description)
        assert recommendation.predicted_impact in [:low, :medium, :high]
        assert recommendation.implementation_difficulty in [:easy, :moderate, :difficult, :hard]
        assert recommendation.risk_level in [:low, :medium, :high]
        assert is_number(recommendation.estimated_performance_gain)
        assert is_list(recommendation.code_changes_required)
        assert is_list(recommendation.validation_steps)
      end)
    end

    test "calculates performance score", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      assert is_number(analysis.performance_score)
      assert analysis.performance_score >= 0.0
      assert analysis.performance_score <= 1.0
    end

    test "provides historical comparison when data available", %{prompt: prompt, execution_context: execution_context, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, historical_data)

      historical_comparison = analysis.historical_comparison

      assert Map.has_key?(historical_comparison, :comparison_available)
      assert historical_comparison.comparison_available == true
      assert Map.has_key?(historical_comparison, :trend_analysis)
    end

    test "handles empty historical data", %{prompt: prompt, execution_context: execution_context} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, execution_context, [])

      assert %PerformanceAnalysis{} = analysis
      assert analysis.historical_comparison.comparison_available == false
      assert is_nil(analysis.historical_comparison.trend_analysis)
    end
  end

  describe "track_performance_metrics/2" do
    test "tracks performance metrics during execution" do
      prompt = "Analyze this code for potential issues."
      execution_options = %{real_time_tracking: true, detailed_metrics: true}

      metrics = PerformanceAnalyzer.track_performance_metrics(prompt, execution_options)

      assert %PerformanceMetrics{} = metrics
      assert is_binary(metrics.execution_id)
      assert %DateTime{} = metrics.start_time
      assert is_nil(metrics.duration_ms) or is_integer(metrics.duration_ms)
      assert is_map(metrics.token_count) or is_integer(metrics.token_count)
      assert is_nil(metrics.response_quality_score) or is_number(metrics.response_quality_score)
      assert is_map(metrics.resource_consumption)
      assert is_list(metrics.error_indicators)
      assert is_list(metrics.optimization_opportunities)
    end
  end

  describe "generate_optimization_suggestions/2" do
    test "generates comprehensive optimization suggestions" do
      analysis = %PerformanceAnalysis{
        prompt_id: "test_analysis",
        analysis_timestamp: DateTime.utc_now(),
        response_time_metrics: %{mean: 1000, median: 950, p95: 1500, p99: 2000, std_dev: 200},
        response_quality_metrics: %{average_quality_score: 0.85, consistency_score: 0.9},
        latency_analysis: %{average_response_time: 1000, median_response_time: 950, p95_response_time: 1500},
        success_rate_analysis: %{overall_success_rate: 0.9, success_rate_by_provider: %{}},
        token_efficiency: %{input_tokens: 50, output_tokens: 150, efficiency_ratio: 0.75, token_waste_indicators: []},
        resource_utilization: %{cpu_usage: 0.5, memory_usage: 0.3, network_io: 100, cache_hit_rate: 0.8},
        bottleneck_analysis: %{identified_bottlenecks: ["slow_response"], severity_scores: %{"slow_response" => 0.8}},
        optimization_recommendations: [],
        performance_score: 0.75,
        historical_comparison: %{comparison_available: false},
        real_time_monitoring: %{},
        scalability_assessment: %{},
        cost_analysis: %{},
        provider_comparison: %{}
      }

      constraints = %{priority: :performance, budget: :medium}

      suggestions = PerformanceAnalyzer.generate_optimization_suggestions(analysis, constraints)

      assert is_list(suggestions)
      assert length(suggestions) > 0

      # Check that each suggestion is valid
      Enum.each(suggestions, fn suggestion ->
        assert %OptimizationSuggestion{} = suggestion
        assert is_binary(suggestion.suggestion_id)
        assert suggestion.optimization_type in [:token_efficiency, :response_time, :resource_usage, :caching, :architectural, :context_chunking, :batching, :token_optimization, :token_reduction]
        assert is_binary(suggestion.description)
        assert suggestion.predicted_impact in [:low, :medium, :high]
        assert suggestion.implementation_difficulty in [:easy, :moderate, :difficult, :hard]
        assert suggestion.risk_level in [:low, :medium, :high]
        assert is_number(suggestion.estimated_performance_gain)
        assert is_list(suggestion.code_changes_required)
        assert is_list(suggestion.validation_steps)
      end)
    end
  end
end
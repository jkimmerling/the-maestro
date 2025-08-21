defmodule TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzer
  alias TheMaestro.Prompts.EngineeringTools.PerformanceAnalyzer.{
    PerformanceAnalysis,
    PerformanceDashboard,
    PerformanceMetrics
  }

  describe "analyze_prompt_performance/3" do
    setup do
      prompt = "You are a {{role | default: assistant}}. Help with {{task | required}}."
      
      historical_data = [
        %{
          timestamp: DateTime.utc_now() |> DateTime.add(-7, :day),
          provider: :openai,
          model: "gpt-4",
          response_time: 1200,
          token_usage: %{input: 50, output: 150, total: 200},
          quality_score: 0.85,
          user_satisfaction: 4.2,
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
          user_satisfaction: 4.5,
          success: true,
          parameters: %{"role" => "expert", "task" => "bug analysis"}
        },
        %{
          timestamp: DateTime.utc_now() |> DateTime.add(-5, :day),
          provider: :google,
          model: "gemini-pro",
          response_time: 1800,
          token_usage: %{input: 52, output: 120, total: 172},
          quality_score: 0.78,
          user_satisfaction: 3.9,
          success: false,
          error: "timeout",
          parameters: %{"role" => "specialist", "task" => "complex analysis"}
        }
      ]

      {:ok, prompt: prompt, historical_data: historical_data}
    end

    test "analyzes response quality metrics", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      quality_metrics = analysis.response_quality_metrics

      assert Map.has_key?(quality_metrics, :average_quality_score)
      assert Map.has_key?(quality_metrics, :quality_distribution)
      assert Map.has_key?(quality_metrics, :quality_trends)
      assert Map.has_key?(quality_metrics, :quality_by_provider)
      
      assert quality_metrics.average_quality_score > 0
      assert quality_metrics.average_quality_score <= 1
      
      # Should have quality scores for each provider
      assert Map.has_key?(quality_metrics.quality_by_provider, :openai)
      assert Map.has_key?(quality_metrics.quality_by_provider, :anthropic)
      assert Map.has_key?(quality_metrics.quality_by_provider, :google)
    end

    test "analyzes response latency", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      latency_analysis = analysis.latency_analysis

      assert Map.has_key?(latency_analysis, :average_response_time)
      assert Map.has_key?(latency_analysis, :median_response_time)
      assert Map.has_key?(latency_analysis, :p95_response_time)
      assert Map.has_key?(latency_analysis, :response_time_by_provider)
      assert Map.has_key?(latency_analysis, :latency_trends)
      
      assert latency_analysis.average_response_time > 0
      assert is_number(latency_analysis.median_response_time)
      assert is_number(latency_analysis.p95_response_time)
    end

    test "analyzes token efficiency", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      token_efficiency = analysis.token_efficiency

      assert Map.has_key?(token_efficiency, :average_tokens_per_request)
      assert Map.has_key?(token_efficiency, :input_output_ratio)
      assert Map.has_key?(token_efficiency, :token_usage_by_provider)
      assert Map.has_key?(token_efficiency, :efficiency_trends)
      assert Map.has_key?(token_efficiency, :cost_efficiency)
      
      assert token_efficiency.average_tokens_per_request > 0
      assert is_number(token_efficiency.input_output_ratio)
    end

    test "calculates success rates", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      success_rate_analysis = analysis.success_rate_analysis

      assert Map.has_key?(success_rate_analysis, :overall_success_rate)
      assert Map.has_key?(success_rate_analysis, :success_rate_by_provider)
      assert Map.has_key?(success_rate_analysis, :failure_reasons)
      assert Map.has_key?(success_rate_analysis, :success_trends)
      
      # Overall success rate should be 2/3 (2 successes out of 3 total)
      assert_in_delta success_rate_analysis.overall_success_rate, 0.667, 0.01
      
      # Should track failure reasons
      assert Map.has_key?(success_rate_analysis.failure_reasons, "timeout")
    end

    test "compares performance across providers", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      provider_comparison = analysis.provider_comparison

      assert Map.has_key?(provider_comparison, :response_time_comparison)
      assert Map.has_key?(provider_comparison, :quality_comparison)
      assert Map.has_key?(provider_comparison, :cost_comparison)
      assert Map.has_key?(provider_comparison, :reliability_comparison)
      assert Map.has_key?(provider_comparison, :best_provider_by_metric)
      
      # Should identify best providers for different metrics
      best_providers = provider_comparison.best_provider_by_metric
      assert Map.has_key?(best_providers, :response_time)
      assert Map.has_key?(best_providers, :quality)
      assert Map.has_key?(best_providers, :reliability)
    end

    test "analyzes cost effectiveness", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      cost_effectiveness = analysis.cost_effectiveness

      assert Map.has_key?(cost_effectiveness, :cost_per_request)
      assert Map.has_key?(cost_effectiveness, :cost_per_quality_point)
      assert Map.has_key?(cost_effectiveness, :cost_trends)
      assert Map.has_key?(cost_effectiveness, :cost_by_provider)
      assert Map.has_key?(cost_effectiveness, :roi_analysis)
      
      assert is_map(cost_effectiveness.cost_by_provider)
    end

    test "analyzes user satisfaction", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      user_satisfaction = analysis.user_satisfaction

      assert Map.has_key?(user_satisfaction, :average_satisfaction)
      assert Map.has_key?(user_satisfaction, :satisfaction_distribution)
      assert Map.has_key?(user_satisfaction, :satisfaction_by_provider)
      assert Map.has_key?(user_satisfaction, :satisfaction_trends)
      assert Map.has_key?(user_satisfaction, :correlation_with_quality)
      
      assert user_satisfaction.average_satisfaction > 0
      assert user_satisfaction.average_satisfaction <= 5
    end

    test "identifies improvement opportunities", %{prompt: prompt, historical_data: historical_data} do
      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data)

      improvement_opportunities = analysis.improvement_opportunities

      assert is_list(improvement_opportunities)
      assert length(improvement_opportunities) > 0
      
      assert Enum.all?(improvement_opportunities, fn opportunity ->
        Map.has_key?(opportunity, :type) &&
        Map.has_key?(opportunity, :description) &&
        Map.has_key?(opportunity, :potential_impact) &&
        Map.has_key?(opportunity, :difficulty)
      end)
    end

    test "handles empty historical data gracefully" do
      prompt = "Test prompt"
      empty_data = []

      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, empty_data)

      assert %PerformanceAnalysis{} = analysis
      assert analysis.response_quality_metrics.average_quality_score == 0
      assert analysis.latency_analysis.average_response_time == 0
      assert analysis.success_rate_analysis.overall_success_rate == 0
    end

    test "respects analysis options", %{prompt: prompt, historical_data: historical_data} do
      analysis_options = %{
        time_range: :last_7_days,
        providers: [:openai, :anthropic],
        include_failures: false,
        quality_threshold: 0.8
      }

      analysis = PerformanceAnalyzer.analyze_prompt_performance(prompt, historical_data, analysis_options)

      # Should filter out Google provider and failures
      provider_data = analysis.provider_comparison
      refute Map.has_key?(provider_data.response_time_comparison, :google)
      
      # Should only include high-quality results
      quality_metrics = analysis.response_quality_metrics
      assert quality_metrics.average_quality_score >= 0.8
    end
  end

  describe "generate_performance_dashboard/1" do
    setup do
      analysis_results = %PerformanceAnalysis{
        response_quality_metrics: %{
          average_quality_score: 0.85,
          quality_distribution: %{excellent: 0.4, good: 0.4, fair: 0.2},
          quality_trends: %{trend: :improving, change_rate: 0.05},
          quality_by_provider: %{openai: 0.82, anthropic: 0.88, google: 0.78}
        },
        latency_analysis: %{
          average_response_time: 1200,
          median_response_time: 1000,
          p95_response_time: 2000,
          response_time_by_provider: %{openai: 1100, anthropic: 950, google: 1650}
        },
        success_rate_analysis: %{
          overall_success_rate: 0.92,
          success_rate_by_provider: %{openai: 0.95, anthropic: 0.97, google: 0.85}
        },
        provider_comparison: %{
          best_provider_by_metric: %{
            response_time: :anthropic,
            quality: :anthropic,
            reliability: :anthropic
          }
        }
      }

      {:ok, analysis_results: analysis_results}
    end

    test "creates executive summary", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      executive_summary = dashboard.executive_summary

      assert Map.has_key?(executive_summary, :key_insights)
      assert Map.has_key?(executive_summary, :performance_status)
      assert Map.has_key?(executive_summary, :top_recommendations)
      assert Map.has_key?(executive_summary, :risk_assessment)
      
      assert is_list(executive_summary.key_insights)
      assert executive_summary.performance_status in [:excellent, :good, :needs_improvement, :poor]
      assert is_list(executive_summary.top_recommendations)
    end

    test "creates metrics visualizations", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      visualizations = dashboard.key_metrics_visualization

      assert Map.has_key?(visualizations, :quality_trend_chart)
      assert Map.has_key?(visualizations, :latency_distribution_chart)
      assert Map.has_key?(visualizations, :provider_comparison_chart)
      assert Map.has_key?(visualizations, :success_rate_chart)
      
      # Each visualization should have data and configuration
      quality_chart = visualizations.quality_trend_chart
      assert Map.has_key?(quality_chart, :data)
      assert Map.has_key?(quality_chart, :chart_config)
      assert Map.has_key?(quality_chart, :chart_type)
    end

    test "performs trend analysis", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      trend_analysis = dashboard.trend_analysis

      assert Map.has_key?(trend_analysis, :quality_trends)
      assert Map.has_key?(trend_analysis, :performance_trends)
      assert Map.has_key?(trend_analysis, :usage_trends)
      assert Map.has_key?(trend_analysis, :cost_trends)
      assert Map.has_key?(trend_analysis, :predictions)
      
      # Should include trend direction and confidence
      quality_trend = trend_analysis.quality_trends
      assert Map.has_key?(quality_trend, :direction)
      assert Map.has_key?(quality_trend, :confidence)
      assert quality_trend.direction in [:improving, :declining, :stable]
    end

    test "creates comparative analysis", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      comparative_analysis = dashboard.comparative_analysis

      assert Map.has_key?(comparative_analysis, :provider_rankings)
      assert Map.has_key?(comparative_analysis, :metric_comparisons)
      assert Map.has_key?(comparative_analysis, :cost_benefit_analysis)
      assert Map.has_key?(comparative_analysis, :trade_off_analysis)
      
      # Provider rankings should be ordered by overall performance
      provider_rankings = comparative_analysis.provider_rankings
      assert is_list(provider_rankings)
      assert length(provider_rankings) > 0
      assert Enum.all?(provider_rankings, fn ranking ->
        Map.has_key?(ranking, :provider) && Map.has_key?(ranking, :overall_score)
      end)
    end

    test "enables drill-down capabilities", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      drill_down = dashboard.drill_down_capabilities

      assert Map.has_key?(drill_down, :available_dimensions)
      assert Map.has_key?(drill_down, :filterable_fields)
      assert Map.has_key?(drill_down, :groupable_metrics)
      assert Map.has_key?(drill_down, :drill_down_queries)
      
      available_dimensions = drill_down.available_dimensions
      assert Enum.member?(available_dimensions, :provider)
      assert Enum.member?(available_dimensions, :time_period)
      assert Enum.member?(available_dimensions, :quality_range)
    end

    test "generates actionable insights", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      actionable_insights = dashboard.actionable_insights

      assert is_list(actionable_insights)
      assert length(actionable_insights) > 0
      
      assert Enum.all?(actionable_insights, fn insight ->
        Map.has_key?(insight, :insight) &&
        Map.has_key?(insight, :action_items) &&
        Map.has_key?(insight, :priority) &&
        Map.has_key?(insight, :expected_impact)
      end)
      
      # Should prioritize high-impact insights
      high_priority_insights = Enum.filter(actionable_insights, fn insight ->
        insight.priority == :high
      end)
      assert length(high_priority_insights) > 0
    end

    test "creates recommendation engine", %{analysis_results: analysis_results} do
      dashboard = PerformanceAnalyzer.generate_performance_dashboard(analysis_results)

      recommendation_engine = dashboard.recommendation_engine

      assert Map.has_key?(recommendation_engine, :immediate_actions)
      assert Map.has_key?(recommendation_engine, :short_term_improvements)
      assert Map.has_key?(recommendation_engine, :long_term_optimizations)
      assert Map.has_key?(recommendation_engine, :monitoring_suggestions)
      
      # Each recommendation category should have prioritized items
      immediate_actions = recommendation_engine.immediate_actions
      assert is_list(immediate_actions)
      assert Enum.all?(immediate_actions, fn action ->
        Map.has_key?(action, :action) &&
        Map.has_key?(action, :rationale) &&
        Map.has_key?(action, :effort_level)
      end)
    end
  end

  describe "performance metrics calculation" do
    test "calculates response time percentiles" do
      response_times = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

      metrics = PerformanceMetrics.calculate_response_time_metrics(response_times)

      assert metrics.average == 550
      assert metrics.median == 550
      assert metrics.p95 == 950
      assert metrics.p99 == 990
      assert metrics.min == 100
      assert metrics.max == 1000
    end

    test "calculates quality score distribution" do
      quality_scores = [0.9, 0.8, 0.85, 0.92, 0.75, 0.88, 0.91, 0.82, 0.87, 0.89]

      distribution = PerformanceMetrics.calculate_quality_distribution(quality_scores)

      assert Map.has_key?(distribution, :excellent)  # >= 0.9
      assert Map.has_key?(distribution, :good)       # 0.8-0.89
      assert Map.has_key?(distribution, :fair)       # 0.7-0.79
      assert Map.has_key?(distribution, :poor)       # < 0.7

      # Check that percentages sum to 1
      total = distribution.excellent + distribution.good + distribution.fair + distribution.poor
      assert_in_delta total, 1.0, 0.01
    end

    test "calculates token efficiency metrics" do
      token_data = [
        %{input: 50, output: 100, total: 150},
        %{input: 60, output: 120, total: 180},
        %{input: 45, output: 90, total: 135}
      ]

      efficiency = PerformanceMetrics.calculate_token_efficiency(token_data)

      assert Map.has_key?(efficiency, :average_input_tokens)
      assert Map.has_key?(efficiency, :average_output_tokens)
      assert Map.has_key?(efficiency, :average_total_tokens)
      assert Map.has_key?(efficiency, :input_output_ratio)
      assert Map.has_key?(efficiency, :efficiency_score)

      assert efficiency.average_input_tokens == 51.67
      assert efficiency.average_output_tokens == 103.33
      assert_in_delta efficiency.input_output_ratio, 0.5, 0.01
    end

    test "identifies performance anomalies" do
      performance_data = [
        %{response_time: 1000, quality_score: 0.9},
        %{response_time: 1100, quality_score: 0.85},
        %{response_time: 5000, quality_score: 0.5},  # Anomaly
        %{response_time: 950, quality_score: 0.88},
        %{response_time: 1200, quality_score: 0.92}
      ]

      anomalies = PerformanceMetrics.identify_anomalies(performance_data)

      assert is_list(anomalies)
      assert length(anomalies) > 0
      
      # Should detect the slow, low-quality response
      slow_response_anomaly = Enum.find(anomalies, fn anomaly ->
        anomaly.type == :slow_response
      end)
      assert slow_response_anomaly != nil
      
      low_quality_anomaly = Enum.find(anomalies, fn anomaly ->
        anomaly.type == :low_quality
      end)
      assert low_quality_anomaly != nil
    end
  end
end
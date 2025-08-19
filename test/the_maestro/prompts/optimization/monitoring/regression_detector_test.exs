defmodule TheMaestro.Prompts.Optimization.Monitoring.RegressionDetectorTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.Optimization.Monitoring.RegressionDetector
  alias TheMaestro.Prompts.Optimization.Monitoring.RegressionDetector.RegressionReport

  describe "detect_optimization_regression/2" do
    test "detects quality regression when quality drops significantly" do
      current_metrics = %{
        quality_score: 0.70,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85,
        provider_info: %{provider: :anthropic}
      }

      historical_baseline = %{
        quality_score: 0.90,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert length(regressions) == 1
      regression = List.first(regressions)
      assert regression.regression_type == :quality_regression
      assert regression.severity in [:high, :critical]
      assert regression.requires_immediate_attention == true
    end

    test "detects latency regression when response time increases significantly" do
      current_metrics = %{
        quality_score: 0.85,
        # 5x increase
        response_time: 5000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      historical_baseline = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert length(regressions) == 1
      regression = List.first(regressions)
      assert regression.regression_type == :latency_regression
      assert regression.severity == :critical
    end

    test "detects error rate regression when errors increase" do
      current_metrics = %{
        quality_score: 0.85,
        response_time: 1000,
        # 7.5x increase
        error_rate: 0.15,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      historical_baseline = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert length(regressions) == 1
      regression = List.first(regressions)
      assert regression.regression_type == :error_rate_regression
      assert regression.severity == :critical
    end

    test "detects token efficiency regression when token usage increases" do
      current_metrics = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        # 3x increase
        token_usage: 1500,
        user_satisfaction: 0.85
      }

      historical_baseline = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert length(regressions) == 1
      regression = List.first(regressions)
      assert regression.regression_type == :token_efficiency_regression
      assert regression.severity == :critical
    end

    test "detects user satisfaction regression when satisfaction drops" do
      current_metrics = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        # Significant drop
        user_satisfaction: 0.65
      }

      historical_baseline = %{
        quality_score: 0.85,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert length(regressions) == 1
      regression = List.first(regressions)
      assert regression.regression_type == :user_satisfaction_regression
      assert regression.severity == :critical
    end

    test "detects multiple regressions simultaneously" do
      current_metrics = %{
        # Moderate drop
        quality_score: 0.80,
        # 80% increase
        response_time: 1800,
        # 4x increase
        error_rate: 0.08,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      historical_baseline = %{
        quality_score: 0.90,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      # Should detect quality, latency, and error rate regressions
      assert length(regressions) == 3

      regression_types = Enum.map(regressions, & &1.regression_type)
      assert :quality_regression in regression_types
      assert :latency_regression in regression_types
      assert :error_rate_regression in regression_types
    end

    test "returns empty list when no regressions detected" do
      current_metrics = %{
        # Slight improvement
        quality_score: 0.91,
        # Slight improvement
        response_time: 950,
        # Slight improvement
        error_rate: 0.018,
        # Slight improvement
        token_usage: 480,
        user_satisfaction: 0.87
      }

      historical_baseline = %{
        quality_score: 0.90,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert regressions == []
    end

    test "handles missing baseline gracefully" do
      current_metrics = %{quality_score: 0.85}
      historical_baseline = %{}

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      assert is_list(regressions)
    end

    test "returns error on invalid input" do
      result = RegressionDetector.detect_optimization_regression("invalid", %{})

      assert {:error, error_message} = result
      assert String.contains?(error_message, "Regression detection failed")
    end
  end

  describe "regression report structure" do
    test "creates comprehensive regression report" do
      current_metrics = %{
        quality_score: 0.70,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85,
        provider_info: %{provider: :anthropic, model: "claude-3-5-sonnet"}
      }

      historical_baseline = %{
        quality_score: 0.90,
        response_time: 1000,
        error_rate: 0.02,
        token_usage: 500,
        user_satisfaction: 0.85
      }

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      regression = List.first(regressions)

      assert %RegressionReport{} = regression
      assert regression.regression_type == :quality_regression
      assert regression.severity in [:medium, :high, :critical]
      assert regression.current_metrics == current_metrics
      assert regression.historical_baseline == historical_baseline
      assert is_map(regression.regression_indicators)
      assert %DateTime{} = regression.detected_at
      assert regression.provider_info == current_metrics.provider_info
      assert is_list(regression.recommendations)
      assert length(regression.recommendations) > 0
      assert is_boolean(regression.requires_immediate_attention)
    end

    test "generates appropriate recommendations for quality regression" do
      current_metrics = %{quality_score: 0.70, provider_info: %{provider: :anthropic}}
      historical_baseline = %{quality_score: 0.90}

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      regression = List.first(regressions)

      assert is_list(regression.recommendations)
      assert length(regression.recommendations) > 3

      # Should contain quality-specific recommendations
      recommendations_text = Enum.join(regression.recommendations, " ")
      assert String.contains?(recommendations_text, "quality")
      assert String.contains?(recommendations_text, "optimization")
    end

    test "sets immediate attention flag for critical regressions" do
      current_metrics = %{
        # Critical drop
        quality_score: 0.50,
        provider_info: %{provider: :anthropic}
      }

      historical_baseline = %{quality_score: 0.90}

      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(current_metrics, historical_baseline)

      regression = List.first(regressions)

      assert regression.severity == :critical
      assert regression.requires_immediate_attention == true
    end
  end

  describe "analyze_performance_trends/2" do
    test "analyzes improving quality trend" do
      provider_info = %{provider: :anthropic}

      historical_data = [
        %{quality_score: 0.70, response_time: 1200, error_rate: 0.05, token_usage: 600},
        %{quality_score: 0.75, response_time: 1150, error_rate: 0.04, token_usage: 580},
        %{quality_score: 0.80, response_time: 1100, error_rate: 0.03, token_usage: 550},
        %{quality_score: 0.85, response_time: 1050, error_rate: 0.025, token_usage: 520},
        %{quality_score: 0.90, response_time: 1000, error_rate: 0.02, token_usage: 500}
      ]

      {:ok, trends} =
        RegressionDetector.analyze_performance_trends(provider_info, historical_data)

      assert trends.quality_trend.trend == :improving
      assert trends.quality_trend.slope > 0
      # Raw slope is negative (decreasing), but that's good for response time
      assert trends.response_time_trend.trend == :degrading
      assert trends.overall_performance_score > 0.7
      assert trends.trend_direction == :improving
      # Only 5 data points
      assert trends.confidence_level == :low
    end

    test "analyzes degrading performance trend" do
      provider_info = %{provider: :anthropic}

      historical_data = [
        %{quality_score: 0.90, response_time: 1000, error_rate: 0.02},
        %{quality_score: 0.85, response_time: 1100, error_rate: 0.03},
        %{quality_score: 0.80, response_time: 1200, error_rate: 0.04},
        %{quality_score: 0.75, response_time: 1300, error_rate: 0.05},
        %{quality_score: 0.70, response_time: 1400, error_rate: 0.06}
      ]

      {:ok, trends} =
        RegressionDetector.analyze_performance_trends(provider_info, historical_data)

      assert trends.quality_trend.trend == :degrading
      assert trends.quality_trend.slope < 0
      assert trends.trend_direction == :degrading
    end

    test "handles insufficient data gracefully" do
      provider_info = %{provider: :anthropic}
      historical_data = [%{quality_score: 0.85}]

      {:ok, trends} =
        RegressionDetector.analyze_performance_trends(provider_info, historical_data)

      assert trends.quality_trend.trend == :insufficient_data
      assert trends.quality_trend.slope == 0
      assert trends.confidence_level == :very_low
    end

    test "calculates overall performance score" do
      provider_info = %{provider: :anthropic}

      historical_data = [
        %{
          quality_score: 0.85,
          response_time: 1000,
          error_rate: 0.02,
          token_usage: 500,
          user_satisfaction: 0.80
        }
      ]

      {:ok, trends} =
        RegressionDetector.analyze_performance_trends(provider_info, historical_data)

      assert is_float(trends.overall_performance_score)
      assert trends.overall_performance_score > 0.0
      assert trends.overall_performance_score <= 1.0
    end

    test "returns error on invalid input" do
      result = RegressionDetector.analyze_performance_trends("invalid", "not a list")

      assert {:error, error_message} = result
      assert String.contains?(error_message, "historical_data must be a list")
    end
  end

  describe "setup_continuous_monitoring/2" do
    test "sets up continuous monitoring process" do
      provider_info = %{provider: :anthropic, model: "claude-3-5-sonnet"}
      monitoring_config = %{check_interval: 1000, quality_threshold: 0.9}

      {:ok, pid} =
        RegressionDetector.setup_continuous_monitoring(provider_info, monitoring_config)

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      Process.exit(pid, :kill)
    end

    test "uses default configuration when not provided" do
      provider_info = %{provider: :anthropic}

      {:ok, pid} = RegressionDetector.setup_continuous_monitoring(provider_info)

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      Process.exit(pid, :kill)
    end

    test "monitoring process responds to stop message" do
      provider_info = %{provider: :anthropic}

      {:ok, pid} =
        RegressionDetector.setup_continuous_monitoring(provider_info, %{check_interval: 50})

      assert Process.alive?(pid)

      # Send stop message
      send(pid, :stop)

      # Give it time to process the stop message
      :timer.sleep(10)

      refute Process.alive?(pid)
    end
  end

  describe "severity classification" do
    test "classifies quality regressions by severity levels" do
      baseline = %{quality_score: 1.0}

      # Critical: < 90% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{quality_score: 0.85}, baseline)

      assert List.first(regressions).severity == :critical

      # High: < 95% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{quality_score: 0.92}, baseline)

      assert List.first(regressions).severity == :high

      # Medium: < 98% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{quality_score: 0.96}, baseline)

      assert List.first(regressions).severity == :medium

      # No regression: >= 98% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{quality_score: 0.99}, baseline)

      assert regressions == []
    end

    test "classifies latency regressions by severity levels" do
      baseline = %{response_time: 1000}

      # Critical: > 200% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{response_time: 2500}, baseline)

      assert List.first(regressions).severity == :critical

      # High: > 150% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{response_time: 1600}, baseline)

      assert List.first(regressions).severity == :high

      # Medium: > 120% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{response_time: 1300}, baseline)

      assert List.first(regressions).severity == :medium

      # No regression: <= 120% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{response_time: 1100}, baseline)

      assert regressions == []
    end

    test "classifies error rate regressions by severity levels" do
      baseline = %{error_rate: 0.02}

      # Critical: > 300% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{error_rate: 0.08}, baseline)

      assert List.first(regressions).severity == :critical

      # High: > 200% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{error_rate: 0.05}, baseline)

      assert List.first(regressions).severity == :high

      # Medium: > 150% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{error_rate: 0.035}, baseline)

      assert List.first(regressions).severity == :medium

      # No regression: <= 150% of baseline
      {:ok, regressions} =
        RegressionDetector.detect_optimization_regression(%{error_rate: 0.025}, baseline)

      assert regressions == []
    end
  end

  describe "trend analysis" do
    test "calculates linear regression correctly" do
      provider_info = %{provider: :anthropic}
      # Perfect upward trend: y = x (slope = 1)
      historical_data = [
        %{quality_score: 1.0},
        %{quality_score: 2.0},
        %{quality_score: 3.0},
        %{quality_score: 4.0},
        %{quality_score: 5.0}
      ]

      {:ok, trends} =
        RegressionDetector.analyze_performance_trends(provider_info, historical_data)

      # Should have strong positive trend
      assert trends.quality_trend.trend == :improving
      # Close to 1.0
      assert trends.quality_trend.slope > 0.9
      # Very high correlation
      assert trends.quality_trend.r_squared > 0.9
    end

    test "determines confidence levels based on data points" do
      provider_info = %{provider: :anthropic}

      # Very low confidence (< 5 points)
      {:ok, trends1} =
        RegressionDetector.analyze_performance_trends(provider_info, [
          %{quality_score: 0.8},
          %{quality_score: 0.9}
        ])

      assert trends1.confidence_level == :very_low

      # Low confidence (5-9 points)
      data_5_points = Enum.map(1..5, fn i -> %{quality_score: i * 0.1 + 0.5} end)
      {:ok, trends2} = RegressionDetector.analyze_performance_trends(provider_info, data_5_points)
      assert trends2.confidence_level == :low

      # Medium confidence (10-29 points)
      data_15_points = Enum.map(1..15, fn i -> %{quality_score: i * 0.01 + 0.5} end)

      {:ok, trends3} =
        RegressionDetector.analyze_performance_trends(provider_info, data_15_points)

      assert trends3.confidence_level == :medium

      # High confidence (30+ points)
      data_35_points = Enum.map(1..35, fn i -> %{quality_score: i * 0.001 + 0.8} end)

      {:ok, trends4} =
        RegressionDetector.analyze_performance_trends(provider_info, data_35_points)

      assert trends4.confidence_level == :high
    end
  end
end

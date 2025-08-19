defmodule TheMaestro.Prompts.Optimization.Monitoring.RegressionDetector do
  @moduledoc """
  Performance regression detection for prompt optimization systems.

  Monitors optimization effectiveness over time and detects when
  performance degrades below acceptable thresholds, triggering
  alerts and optimization reviews.
  """

  defmodule RegressionReport do
    @moduledoc """
    Structure representing a detected performance regression.
    """

    defstruct [
      :regression_type,
      :severity,
      :current_metrics,
      :historical_baseline,
      :regression_indicators,
      :detected_at,
      :provider_info,
      :recommendations,
      :requires_immediate_attention
    ]

    @type regression_type ::
            :quality | :latency | :error_rate | :token_efficiency | :user_satisfaction
    @type severity :: :low | :medium | :high | :critical

    @type t :: %__MODULE__{
            regression_type: regression_type(),
            severity: severity(),
            current_metrics: map(),
            historical_baseline: map(),
            regression_indicators: map(),
            detected_at: DateTime.t(),
            provider_info: map(),
            recommendations: [String.t()],
            requires_immediate_attention: boolean()
          }
  end

  @doc """
  Detects optimization regression by comparing current metrics with historical baseline.

  Analyzes multiple performance dimensions and triggers alerts when significant
  degradation is detected.
  """
  @spec detect_optimization_regression(map(), map()) ::
          {:ok, [RegressionReport.t()]} | {:error, String.t()}
  def detect_optimization_regression(current_metrics, historical_baseline) do
    try do
      regression_indicators = %{
        quality_regression: detect_quality_regression(current_metrics, historical_baseline),
        latency_regression: detect_latency_regression(current_metrics, historical_baseline),
        error_rate_regression: detect_error_rate_regression(current_metrics, historical_baseline),
        token_efficiency_regression:
          detect_token_efficiency_regression(current_metrics, historical_baseline),
        user_satisfaction_regression:
          detect_user_satisfaction_regression(current_metrics, historical_baseline)
      }

      regressions =
        generate_regression_reports(current_metrics, historical_baseline, regression_indicators)

      if any_regression?(regression_indicators) do
        trigger_optimization_review(current_metrics, historical_baseline, regression_indicators)
      end

      {:ok, regressions}
    rescue
      error ->
        {:error, "Regression detection failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Analyzes long-term performance trends to identify gradual degradation.
  """
  @spec analyze_performance_trends(map(), [map()]) :: {:ok, map()} | {:error, String.t()}
  def analyze_performance_trends(_provider_info, historical_data) when is_list(historical_data) do
    try do
      trend_analysis = %{
        quality_trend: calculate_trend(:quality_score, historical_data),
        response_time_trend: calculate_trend(:response_time, historical_data),
        error_rate_trend: calculate_trend(:error_rate, historical_data),
        token_usage_trend: calculate_trend(:token_usage, historical_data),
        user_satisfaction_trend: calculate_trend(:user_satisfaction, historical_data),
        overall_performance_score: calculate_overall_performance_score(historical_data),
        trend_direction: determine_overall_trend_direction(historical_data),
        confidence_level: calculate_trend_confidence(historical_data)
      }

      {:ok, trend_analysis}
    rescue
      error ->
        {:error, "Trend analysis failed: #{Exception.message(error)}"}
    end
  end

  def analyze_performance_trends(_provider_info, _invalid_data) do
    {:error, "Trend analysis failed: historical_data must be a list"}
  end

  @doc """
  Performs continuous monitoring setup for a provider.
  """
  @spec setup_continuous_monitoring(map(), map()) :: {:ok, pid()} | {:error, String.t()}
  def setup_continuous_monitoring(provider_info, monitoring_config \\ %{}) do
    config = Map.merge(default_monitoring_config(), monitoring_config)

    monitoring_process =
      spawn_link(fn ->
        continuous_monitoring_loop(provider_info, config)
      end)

    {:ok, monitoring_process}
  end

  # Private functions for regression detection

  defp detect_quality_regression(current, baseline) do
    current_quality = current[:quality_score] || 0.0
    baseline_quality = baseline[:quality_score] || 0.0

    cond do
      baseline_quality == 0.0 -> false
      current_quality < baseline_quality * 0.90 -> :critical
      current_quality < baseline_quality * 0.95 -> :high
      current_quality < baseline_quality * 0.98 -> :medium
      true -> false
    end
  end

  defp detect_latency_regression(current, baseline) do
    current_latency = current[:response_time] || 0
    baseline_latency = baseline[:response_time] || 0

    cond do
      baseline_latency == 0 -> false
      current_latency > baseline_latency * 2.0 -> :critical
      current_latency > baseline_latency * 1.5 -> :high
      current_latency > baseline_latency * 1.2 -> :medium
      true -> false
    end
  end

  defp detect_error_rate_regression(current, baseline) do
    current_errors = current[:error_rate] || 0.0
    baseline_errors = baseline[:error_rate] || 0.0

    cond do
      current_errors > baseline_errors * 3.0 -> :critical
      current_errors > baseline_errors * 2.0 -> :high
      current_errors > baseline_errors * 1.5 -> :medium
      true -> false
    end
  end

  defp detect_token_efficiency_regression(current, baseline) do
    current_tokens = current[:token_usage] || 0
    baseline_tokens = baseline[:token_usage] || 0

    cond do
      baseline_tokens == 0 -> false
      current_tokens > baseline_tokens * 1.5 -> :critical
      current_tokens > baseline_tokens * 1.3 -> :high
      current_tokens > baseline_tokens * 1.15 -> :medium
      true -> false
    end
  end

  defp detect_user_satisfaction_regression(current, baseline) do
    current_satisfaction = current[:user_satisfaction] || 0.0
    baseline_satisfaction = baseline[:user_satisfaction] || 0.0

    cond do
      baseline_satisfaction == 0.0 -> false
      current_satisfaction < baseline_satisfaction * 0.85 -> :critical
      current_satisfaction < baseline_satisfaction * 0.90 -> :high
      current_satisfaction < baseline_satisfaction * 0.95 -> :medium
      true -> false
    end
  end

  defp any_regression?(indicators) do
    Enum.any?(indicators, fn {_type, result} -> result != false end)
  end

  defp generate_regression_reports(current_metrics, historical_baseline, regression_indicators) do
    regression_indicators
    |> Enum.filter(fn {_type, result} -> result != false end)
    |> Enum.map(fn {type, severity} ->
      %RegressionReport{
        regression_type: type,
        severity: severity,
        current_metrics: current_metrics,
        historical_baseline: historical_baseline,
        regression_indicators: regression_indicators,
        detected_at: DateTime.utc_now(),
        provider_info: current_metrics[:provider_info] || %{},
        recommendations:
          generate_recommendations(type, severity, current_metrics, historical_baseline),
        requires_immediate_attention: severity in [:high, :critical]
      }
    end)
  end

  defp generate_recommendations(
         :quality_regression,
         severity,
         _current_metrics,
         _historical_baseline
       ) do
    base_recommendations = [
      "Review recent prompt optimization changes",
      "Analyze quality scoring methodology",
      "Check for model version changes or provider updates",
      "Validate test data quality and relevance"
    ]

    case severity do
      :critical ->
        ["IMMEDIATE ACTION REQUIRED: Quality dropped significantly"] ++
          base_recommendations ++
          [
            "Consider rolling back recent optimization changes",
            "Escalate to optimization team immediately"
          ]

      :high ->
        ["HIGH PRIORITY: Significant quality degradation detected"] ++
          base_recommendations ++
          [
            "Schedule optimization review within 24 hours",
            "Implement additional quality gates"
          ]

      _ ->
        base_recommendations ++ ["Monitor closely and investigate if trend continues"]
    end
  end

  defp generate_recommendations(:latency_regression, severity, _current, _baseline) do
    base_recommendations = [
      "Profile optimization pipeline performance",
      "Check for resource constraints or bottlenecks",
      "Review recent infrastructure changes",
      "Analyze provider API response times"
    ]

    case severity do
      :critical ->
        ["CRITICAL: Response times severely degraded"] ++
          base_recommendations ++
          [
            "Implement emergency performance optimizations",
            "Consider provider failover if available"
          ]

      :high ->
        ["HIGH PRIORITY: Significant latency increase"] ++
          base_recommendations ++
          [
            "Optimize critical path operations",
            "Review caching strategies"
          ]

      _ ->
        base_recommendations ++ ["Monitor performance trends"]
    end
  end

  defp generate_recommendations(:error_rate_regression, severity, _current, _baseline) do
    base_recommendations = [
      "Analyze error logs and patterns",
      "Check provider API stability",
      "Review input validation and sanitization",
      "Validate optimization logic changes"
    ]

    case severity do
      :critical ->
        ["CRITICAL: Error rate spike detected"] ++
          base_recommendations ++
          [
            "Implement circuit breaker patterns",
            "Enable aggressive error monitoring"
          ]

      :high ->
        ["HIGH PRIORITY: Increased error rate"] ++
          base_recommendations ++
          [
            "Enhance error handling and retry logic",
            "Review recent code changes"
          ]

      _ ->
        base_recommendations ++ ["Continue monitoring error patterns"]
    end
  end

  defp generate_recommendations(:token_efficiency_regression, severity, _current, _baseline) do
    base_recommendations = [
      "Review token optimization algorithms",
      "Analyze prompt length and complexity trends",
      "Check compression and abbreviation strategies",
      "Validate token estimation accuracy"
    ]

    case severity do
      :critical ->
        ["CRITICAL: Token usage significantly increased"] ++
          base_recommendations ++
          [
            "Implement emergency token reduction measures",
            "Review cost implications immediately"
          ]

      :high ->
        ["HIGH PRIORITY: Token efficiency degraded"] ++
          base_recommendations ++
          [
            "Re-tune compression thresholds",
            "Optimize context selection"
          ]

      _ ->
        base_recommendations ++ ["Monitor token usage patterns"]
    end
  end

  defp generate_recommendations(:user_satisfaction_regression, severity, _current, _baseline) do
    base_recommendations = [
      "Analyze user feedback and ratings",
      "Review response quality and relevance",
      "Check for user experience degradation",
      "Validate satisfaction measurement methodology"
    ]

    case severity do
      :critical ->
        ["CRITICAL: User satisfaction severely impacted"] ++
          base_recommendations ++
          [
            "Conduct immediate user feedback analysis",
            "Consider temporary optimization rollback"
          ]

      :high ->
        ["HIGH PRIORITY: User satisfaction declining"] ++
          base_recommendations ++
          [
            "Enhance user experience optimizations",
            "Increase feedback collection"
          ]

      _ ->
        base_recommendations ++ ["Continue user satisfaction monitoring"]
    end
  end

  defp generate_recommendations(_, _, _, _), do: ["Monitor and investigate"]

  defp trigger_optimization_review(current_metrics, historical_baseline, regression_indicators) do
    review_data = %{
      triggered_at: DateTime.utc_now(),
      current_metrics: current_metrics,
      historical_baseline: historical_baseline,
      regression_indicators: regression_indicators,
      review_priority: determine_review_priority(regression_indicators),
      estimated_impact: estimate_regression_impact(current_metrics, historical_baseline)
    }

    # Send telemetry event for external monitoring systems
    :telemetry.execute(
      [:maestro, :optimization, :regression_detected],
      %{
        regression_count: count_regressions(regression_indicators),
        severity_score: calculate_severity_score(regression_indicators)
      },
      %{
        provider: current_metrics[:provider_info][:provider] || :unknown,
        review_priority: review_data.review_priority
      }
    )

    # Log the regression for analysis
    require Logger
    Logger.warning("Optimization regression detected", extra: review_data)

    review_data
  end

  defp determine_review_priority(regression_indicators) do
    critical_count = count_regressions_by_severity(regression_indicators, :critical)
    high_count = count_regressions_by_severity(regression_indicators, :high)

    cond do
      critical_count > 0 -> :immediate
      high_count > 1 -> :urgent
      high_count > 0 -> :high
      true -> :normal
    end
  end

  defp count_regressions(regression_indicators) do
    Enum.count(regression_indicators, fn {_type, result} -> result != false end)
  end

  defp count_regressions_by_severity(regression_indicators, target_severity) do
    Enum.count(regression_indicators, fn {_type, result} -> result == target_severity end)
  end

  defp calculate_severity_score(regression_indicators) do
    regression_indicators
    |> Enum.map(fn {_type, severity} ->
      case severity do
        :critical -> 10
        :high -> 7
        :medium -> 4
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp estimate_regression_impact(current_metrics, historical_baseline) do
    quality_impact = calculate_quality_impact(current_metrics, historical_baseline)
    performance_impact = calculate_performance_impact(current_metrics, historical_baseline)
    cost_impact = calculate_cost_impact(current_metrics, historical_baseline)

    %{
      quality_impact: quality_impact,
      performance_impact: performance_impact,
      cost_impact: cost_impact,
      overall_impact: (quality_impact + performance_impact + cost_impact) / 3
    }
  end

  defp calculate_quality_impact(current, baseline) do
    current_quality = current[:quality_score] || 0.0
    baseline_quality = baseline[:quality_score] || 1.0

    max(0.0, (baseline_quality - current_quality) / baseline_quality)
  end

  defp calculate_performance_impact(current, baseline) do
    current_latency = current[:response_time] || 0
    baseline_latency = baseline[:response_time] || 1

    max(0.0, (current_latency - baseline_latency) / baseline_latency)
  end

  defp calculate_cost_impact(current, baseline) do
    current_tokens = current[:token_usage] || 0
    baseline_tokens = baseline[:token_usage] || 1

    max(0.0, (current_tokens - baseline_tokens) / baseline_tokens)
  end

  # Trend analysis functions

  defp calculate_trend(metric_key, historical_data) do
    values =
      Enum.map(historical_data, & &1[metric_key])
      |> Enum.filter(&(&1 != nil))

    if length(values) < 2 do
      %{trend: :insufficient_data, slope: 0, r_squared: 0}
    else
      {slope, r_squared} = linear_regression(values)

      %{
        trend: determine_trend_direction(slope),
        slope: slope,
        r_squared: r_squared,
        data_points: length(values)
      }
    end
  end

  defp linear_regression(values) do
    n = length(values)
    indices = Enum.to_list(1..n)

    sum_x = Enum.sum(indices)
    sum_y = Enum.sum(values)
    sum_xy = Enum.zip(indices, values) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    sum_x2 = Enum.map(indices, &(&1 * &1)) |> Enum.sum()
    _sum_y2 = Enum.map(values, &(&1 * &1)) |> Enum.sum()

    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)

    # Calculate R-squared
    mean_y = sum_y / n
    ss_tot = Enum.map(values, fn y -> (y - mean_y) * (y - mean_y) end) |> Enum.sum()

    predicted_values = Enum.map(indices, fn x -> slope * x + (sum_y - slope * sum_x) / n end)

    ss_res =
      Enum.zip(values, predicted_values)
      |> Enum.map(fn {actual, predicted} -> (actual - predicted) * (actual - predicted) end)
      |> Enum.sum()

    r_squared = if ss_tot > 0, do: 1 - ss_res / ss_tot, else: 0

    {slope, r_squared}
  end

  defp determine_trend_direction(slope) when is_number(slope) do
    cond do
      slope > 0.03 -> :improving
      slope > 0.01 -> :slightly_improving
      slope < -0.03 -> :degrading
      slope < -0.01 -> :slightly_degrading
      true -> :stable
    end
  end

  defp determine_trend_direction(_), do: :unknown

  defp determine_overall_trend_direction(historical_data) do
    # Calculate trends for key metrics and determine overall direction
    quality_trend = calculate_trend(:quality_score, historical_data)
    response_time_trend = calculate_trend(:response_time, historical_data)
    error_rate_trend = calculate_trend(:error_rate, historical_data)

    # Weight the trends (quality is positive, response time and errors are negative when increasing)
    quality_direction = quality_trend.slope
    # Lower response time is better
    response_time_direction = -response_time_trend.slope
    # Lower error rate is better
    error_rate_direction = -error_rate_trend.slope

    overall_slope = (quality_direction + response_time_direction + error_rate_direction) / 3

    determine_trend_direction(overall_slope)
  end

  defp calculate_overall_performance_score(historical_data) do
    if length(historical_data) == 0 do
      0.0
    else
      latest_data = List.last(historical_data)

      quality_score = latest_data[:quality_score] || 0.0
      efficiency_score = calculate_efficiency_score(latest_data)
      reliability_score = calculate_reliability_score(latest_data)

      quality_score * 0.4 + efficiency_score * 0.3 + reliability_score * 0.3
    end
  end

  defp calculate_efficiency_score(data) do
    token_usage = data[:token_usage] || 0
    response_time = data[:response_time] || 0

    # Normalized efficiency score (lower usage/time = higher score)
    token_efficiency = max(0.0, 1.0 - token_usage / 10_000)
    time_efficiency = max(0.0, 1.0 - response_time / 5000)

    (token_efficiency + time_efficiency) / 2
  end

  defp calculate_reliability_score(data) do
    error_rate = data[:error_rate] || 0.0
    max(0.0, 1.0 - error_rate * 10)
  end

  defp calculate_trend_confidence(historical_data) do
    data_points = length(historical_data)

    cond do
      data_points >= 30 -> :high
      data_points >= 10 -> :medium
      data_points >= 5 -> :low
      true -> :very_low
    end
  end

  # Continuous monitoring

  defp default_monitoring_config do
    %{
      # 5 minutes
      check_interval: 300_000,
      quality_threshold: 0.95,
      latency_threshold: 1.2,
      error_rate_threshold: 1.5,
      token_usage_threshold: 1.3,
      trend_analysis_window: 50,
      # 15 minutes
      alert_cooldown: 900_000
    }
  end

  defp continuous_monitoring_loop(provider_info, config) do
    receive do
      :stop ->
        :ok
    after
      config.check_interval ->
        perform_regression_check(provider_info, config)
        continuous_monitoring_loop(provider_info, config)
    end
  end

  defp perform_regression_check(provider_info, _config) do
    # This would integrate with actual metrics collection
    # For now, we'll simulate the check
    require Logger
    Logger.debug("Performing regression check for provider: #{inspect(provider_info[:provider])}")

    # In a real implementation, this would:
    # 1. Fetch current metrics from the metrics store
    # 2. Compare with historical baseline
    # 3. Trigger alerts if regressions are detected
  end
end

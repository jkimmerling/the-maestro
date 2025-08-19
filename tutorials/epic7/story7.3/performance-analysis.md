# Performance Analysis Guide: Provider-Specific Prompt Optimization

This guide covers how to monitor, analyze, and optimize the performance of the Provider-Specific Prompt Optimization system using the built-in benchmarking and monitoring tools.

## Table of Contents

- [Performance Monitoring Overview](#performance-monitoring-overview)
- [Benchmarking Tools](#benchmarking-tools)
- [Key Performance Metrics](#key-performance-metrics)
- [Running Performance Analysis](#running-performance-analysis)
- [Interpreting Results](#interpreting-results)
- [Performance Optimization](#performance-optimization)
- [Monitoring in Production](#monitoring-in-production)
- [Troubleshooting Performance Issues](#troubleshooting-performance-issues)

## Performance Monitoring Overview

The system includes comprehensive performance monitoring at multiple levels:

```
Request Level → Provider Level → System Level → Historical Analysis
     ↓              ↓              ↓               ↓
Individual      Provider       Overall      Long-term
Optimization    Comparison     System       Trends
Metrics         Analysis       Health       Analysis
```

### Monitoring Components

1. **EffectivenessTracker** - Real-time optimization effectiveness measurement
2. **PerformanceBenchmark** - Comprehensive benchmarking system
3. **BenchmarkRunner** - Convenient benchmark execution utilities
4. **Telemetry Integration** - System-wide metrics collection
5. **Performance Alerts** - Automated issue detection

## Benchmarking Tools

### Quick Benchmark

For rapid performance assessment:

```elixir
# Run a quick benchmark with simplified test cases
results = BenchmarkRunner.run_quick_benchmark()

# Example output:
# 🚀 Running Quick Provider Optimization Benchmark
# 📊 Key Metrics:
#   • Token Reduction: 15.3%
#   • Quality Improvement: 8.2%
#   • Best Provider: anthropic
# 💡 Quick Insights:
#   • anthropic: Highly effective - recommend using optimization
#   • google: Moderately effective - optimize selectively
#   • openai: Low effectiveness - consider disabling optimization
```

### Provider-Specific Benchmark

Test a single provider in detail:

```elixir
# Test specific provider performance
anthropic_results = BenchmarkRunner.run_provider_benchmark(:anthropic)

# Detailed provider analysis
google_results = BenchmarkRunner.run_provider_benchmark(:google)
openai_results = BenchmarkRunner.run_provider_benchmark(:openai)

# Compare providers
comparison = BenchmarkComparator.compare_providers([
  {:anthropic, anthropic_results},
  {:google, google_results},
  {:openai, openai_results}
])
```

### Comprehensive Benchmark

Full system analysis (may take several minutes):

```elixir
# Run complete benchmark suite
comprehensive_results = PerformanceBenchmark.run_comprehensive_benchmark()

# Results include:
# - Baseline metrics for all providers
# - Optimization effectiveness across all test cases
# - Provider comparison analysis
# - Performance recommendations
# - Configuration suggestions
```

### Custom Benchmark

Test with your specific use cases:

```elixir
# Define custom test cases
custom_test_cases = [
  %{
    name: "code_review_task",
    prompt: "Review this Python code for security issues and performance problems...",
    complexity: :high,
    expected_provider: :anthropic  # Which provider should excel
  },
  %{
    name: "ui_component_generation",
    prompt: "Create a responsive React component with TypeScript...",
    complexity: :medium,
    expected_provider: :google
  }
]

# Run custom benchmark
custom_results = BenchmarkRunner.run_targeted_benchmark(custom_test_cases)
```

## Key Performance Metrics

### Optimization Effectiveness Metrics

```elixir
effectiveness_metrics = %{
  # Token efficiency
  token_reduction: 0.15,              # 15% reduction in tokens used
  token_efficiency_gain: 0.12,        # 12% better quality per token
  
  # Quality improvements  
  response_quality_improvement: 0.08,  # 8% quality improvement
  coherence_improvement: 0.06,         # 6% better coherence
  relevance_improvement: 0.09,         # 9% better relevance
  completeness_improvement: 0.07,      # 7% more complete responses
  
  # Performance impact
  latency_impact: -0.05,              # 5% latency reduction (negative is good)
  optimization_time_ms: 1250,         # Time spent optimizing
  total_time_impact: 0.02,            # 2% total time increase
  
  # Reliability metrics
  error_rate_change: -0.03,           # 3% error rate reduction
  consistency_improvement: 0.11,      # 11% consistency improvement
  
  # Cost efficiency
  cost_reduction: 0.018,              # $0.018 cost reduction per request
  cost_efficiency_ratio: 1.15,       # 15% better value for cost
  
  # User satisfaction
  user_satisfaction_delta: 0.4,      # 0.4 point satisfaction increase
  task_completion_improvement: 0.06   # 6% better task completion
}
```

### Provider Comparison Metrics

```elixir
provider_comparison = %{
  anthropic: %{
    avg_token_reduction: 0.18,       # Best token reduction
    avg_quality_improvement: 0.12,    # Best quality improvement
    avg_latency_impact: -0.02,       # Minimal latency impact
    best_for: [:reasoning, :analysis, :large_context],
    optimization_score: 0.85         # Overall optimization effectiveness
  },
  
  google: %{
    avg_token_reduction: 0.14,
    avg_quality_improvement: 0.09,
    avg_latency_impact: 0.03,
    best_for: [:multimodal, :code_generation, :function_calling],
    optimization_score: 0.78
  },
  
  openai: %{
    avg_token_reduction: 0.11,
    avg_quality_improvement: 0.07,
    avg_latency_impact: -0.04,       # Best latency improvement
    best_for: [:structured_output, :consistency, :creative_tasks],
    optimization_score: 0.72
  }
}
```

## Running Performance Analysis

### Basic Performance Analysis

```elixir
defmodule BasicPerformanceAnalysis do
  def analyze_optimization_performance(time_window \\ :last_24_hours) do
    # Collect metrics from the specified time window
    metrics = PerformanceCollector.collect_metrics(time_window)
    
    analysis = %{
      # Overall system performance
      system_health: calculate_system_health(metrics),
      
      # Provider-specific analysis
      provider_performance: analyze_provider_performance(metrics),
      
      # Trend analysis
      performance_trends: analyze_trends(metrics),
      
      # Issue identification
      identified_issues: identify_performance_issues(metrics),
      
      # Recommendations
      recommendations: generate_recommendations(metrics)
    }
    
    # Generate report
    generate_performance_report(analysis)
    
    analysis
  end
  
  defp calculate_system_health(metrics) do
    health_indicators = %{
      avg_optimization_time: calculate_average(metrics, :optimization_time_ms),
      avg_quality_improvement: calculate_average(metrics, :response_quality_improvement),
      avg_token_efficiency: calculate_average(metrics, :token_reduction),
      error_rate: calculate_error_rate(metrics),
      optimization_success_rate: calculate_success_rate(metrics)
    }
    
    # Calculate overall health score (0.0 - 1.0)
    health_score = calculate_health_score(health_indicators)
    
    %{
      score: health_score,
      status: health_status(health_score),
      indicators: health_indicators
    }
  end
  
  defp health_status(score) when score > 0.8, do: :excellent
  defp health_status(score) when score > 0.6, do: :good  
  defp health_status(score) when score > 0.4, do: :fair
  defp health_status(_), do: :poor
end
```

### Advanced Performance Analysis

```elixir
defmodule AdvancedPerformanceAnalysis do
  def deep_performance_analysis(providers, time_window \\ :last_week) do
    analysis = %{}
    
    # Provider-specific deep dive
    provider_analyses = Enum.map(providers, fn provider ->
      {provider, analyze_provider_deeply(provider, time_window)}
    end) |> Map.new()
    
    # Cross-provider comparison
    cross_provider_analysis = compare_providers_deeply(provider_analyses)
    
    # Performance regression analysis
    regression_analysis = analyze_performance_regressions(providers, time_window)
    
    # Optimization opportunity identification
    optimization_opportunities = identify_optimization_opportunities(provider_analyses)
    
    # Cost-benefit analysis
    cost_benefit_analysis = analyze_cost_benefits(provider_analyses)
    
    %{
      provider_analyses: provider_analyses,
      cross_provider_comparison: cross_provider_analysis,
      regression_analysis: regression_analysis,
      optimization_opportunities: optimization_opportunities,
      cost_benefit_analysis: cost_benefit_analysis,
      generated_at: DateTime.utc_now()
    }
  end
  
  defp analyze_provider_deeply(provider, time_window) do
    raw_metrics = PerformanceCollector.collect_provider_metrics(provider, time_window)
    
    %{
      # Performance metrics
      performance_stats: calculate_performance_stats(raw_metrics),
      
      # Quality analysis
      quality_analysis: analyze_quality_metrics(raw_metrics),
      
      # Efficiency analysis  
      efficiency_analysis: analyze_efficiency_metrics(raw_metrics),
      
      # Reliability analysis
      reliability_analysis: analyze_reliability_metrics(raw_metrics),
      
      # Usage patterns
      usage_patterns: analyze_usage_patterns(raw_metrics),
      
      # Anomaly detection
      anomalies: detect_anomalies(raw_metrics),
      
      # Performance trends
      trends: calculate_performance_trends(raw_metrics)
    }
  end
end
```

### Real-Time Performance Monitoring

```elixir
defmodule RealTimePerformanceMonitor do
  use GenServer
  
  # Monitor performance in real-time
  def start_monitoring(interval_seconds \\ 60) do
    GenServer.start_link(__MODULE__, %{interval: interval_seconds * 1000}, name: __MODULE__)
  end
  
  def init(state) do
    schedule_monitoring(state.interval)
    {:ok, Map.put(state, :metrics_buffer, [])}
  end
  
  def handle_info(:monitor_performance, state) do
    # Collect current metrics
    current_metrics = collect_current_performance_metrics()
    
    # Add to buffer
    updated_buffer = [current_metrics | state.metrics_buffer] |> Enum.take(100)
    
    # Analyze for immediate issues
    immediate_issues = analyze_immediate_performance_issues(current_metrics, updated_buffer)
    
    # Alert if necessary
    handle_performance_alerts(immediate_issues)
    
    # Schedule next monitoring cycle
    schedule_monitoring(state.interval)
    
    {:noreply, %{state | metrics_buffer: updated_buffer}}
  end
  
  defp collect_current_performance_metrics do
    providers = [:anthropic, :google, :openai]
    
    Enum.map(providers, fn provider ->
      recent_metrics = PerformanceCollector.get_recent_metrics(provider, :last_5_minutes)
      
      %{
        provider: provider,
        timestamp: DateTime.utc_now(),
        avg_response_time: calculate_average(recent_metrics, :response_time_ms),
        avg_quality_score: calculate_average(recent_metrics, :response_quality_improvement),
        error_rate: calculate_error_rate(recent_metrics),
        request_count: length(recent_metrics)
      }
    end)
  end
  
  defp handle_performance_alerts(issues) do
    Enum.each(issues, fn issue ->
      case issue.severity do
        :critical ->
          Logger.error("Critical performance issue detected", issue)
          # Could trigger paging, disable provider, etc.
          
        :warning ->
          Logger.warning("Performance warning", issue)
          # Could adjust configuration, send notifications
          
        :info ->
          Logger.info("Performance notice", issue)
      end
    end)
  end
end
```

## Interpreting Results

### Understanding Benchmark Results

```elixir
# Example comprehensive benchmark results interpretation
defmodule ResultsInterpreter do
  def interpret_benchmark_results(results) do
    %{
      # Overall assessment
      overall_assessment: assess_overall_performance(results),
      
      # Provider rankings
      provider_rankings: rank_providers(results),
      
      # Optimization effectiveness
      optimization_effectiveness: assess_optimization_effectiveness(results),
      
      # Performance bottlenecks
      bottlenecks: identify_bottlenecks(results),
      
      # Recommendations
      actionable_recommendations: generate_actionable_recommendations(results)
    }
  end
  
  defp assess_overall_performance(results) do
    summary = results.performance_summary
    
    assessment = %{
      token_efficiency: assess_metric(summary.overall_token_reduction, 
                                    [excellent: 0.2, good: 0.1, fair: 0.05]),
      quality_improvement: assess_metric(summary.overall_quality_improvement,
                                       [excellent: 0.15, good: 0.08, fair: 0.03]),
      system_impact: assess_system_impact(summary),
      roi_assessment: assess_return_on_investment(summary)
    }
    
    overall_score = calculate_overall_score(assessment)
    
    %{
      score: overall_score,
      grade: assign_grade(overall_score),
      individual_assessments: assessment,
      key_insights: generate_key_insights(assessment)
    }
  end
  
  defp assess_system_impact(summary) do
    cond do
      summary.overall_latency_impact < -0.1 ->
        %{impact: :very_positive, description: "Significant performance improvement"}
      
      summary.overall_latency_impact < 0 ->
        %{impact: :positive, description: "Performance improvement"}
      
      summary.overall_latency_impact < 0.1 ->
        %{impact: :neutral, description: "Minimal performance impact"}
      
      true ->
        %{impact: :negative, description: "Performance degradation detected"}
    end
  end
end
```

### Performance Thresholds and Alerts

```elixir
defmodule PerformanceThresholds do
  # Define performance thresholds for different metrics
  @thresholds %{
    optimization_time_ms: %{
      excellent: 0..1000,
      good: 1001..3000,
      warning: 3001..5000,
      critical: 5001..99999
    },
    
    token_reduction: %{
      excellent: 0.15..1.0,
      good: 0.08..0.14,
      fair: 0.03..0.07,
      poor: -1.0..0.02
    },
    
    quality_improvement: %{
      excellent: 0.12..1.0,
      good: 0.06..0.11,
      fair: 0.02..0.05,
      poor: -1.0..0.01
    },
    
    error_rate: %{
      excellent: 0.0..0.01,
      good: 0.011..0.03,
      warning: 0.031..0.05,
      critical: 0.051..1.0
    }
  }
  
  def assess_metric(value, metric_type) do
    thresholds = @thresholds[metric_type]
    
    cond do
      value in thresholds.excellent -> :excellent
      value in thresholds.good -> :good
      value in thresholds.warning -> :warning
      value in thresholds.critical -> :critical
      true -> :unknown
    end
  end
  
  def check_all_thresholds(metrics) do
    assessments = Enum.map(@thresholds, fn {metric, _thresholds} ->
      value = Map.get(metrics, metric)
      assessment = assess_metric(value, metric)
      {metric, %{value: value, assessment: assessment}}
    end) |> Map.new()
    
    # Identify issues requiring attention
    issues = assessments
    |> Enum.filter(fn {_metric, %{assessment: assessment}} ->
      assessment in [:warning, :critical]
    end)
    |> Map.new()
    
    %{
      assessments: assessments,
      issues: issues,
      overall_status: determine_overall_status(assessments)
    }
  end
end
```

## Performance Optimization

### Configuration Optimization Based on Results

```elixir
defmodule ConfigurationOptimizer do
  def optimize_configuration_from_results(provider, benchmark_results) do
    current_config = OptimizationConfig.get_provider_config(provider)
    performance_issues = identify_performance_issues(benchmark_results)
    
    optimizations = %{}
    
    # Optimize based on specific performance issues
    optimizations = optimizations
    |> maybe_optimize_for_latency(performance_issues, current_config)
    |> maybe_optimize_for_quality(performance_issues, current_config)
    |> maybe_optimize_for_token_efficiency(performance_issues, current_config)
    |> maybe_optimize_for_reliability(performance_issues, current_config)
    
    if map_size(optimizations) > 0 do
      new_config = Map.merge(current_config, optimizations)
      
      # Validate new configuration
      case OptimizationConfig.validate_provider_config(new_config, provider) do
        {:ok, validated_config} ->
          # Apply configuration
          OptimizationConfig.update_provider_config(provider, validated_config)
          
          Logger.info("Applied performance-based configuration optimizations", %{
            provider: provider,
            optimizations: optimizations
          })
          
          {:ok, validated_config}
          
        {:error, reason} ->
          Logger.error("Configuration optimization failed validation: #{reason}")
          {:error, reason}
      end
    else
      Logger.info("No configuration optimizations needed for #{provider}")
      {:ok, current_config}
    end
  end
  
  defp maybe_optimize_for_latency(optimizations, issues, current_config) do
    if :high_latency in issues do
      Map.merge(optimizations, %{
        optimization_timeout_ms: max(current_config.optimization_timeout_ms - 1000, 1000),
        parallel_processing: true,
        cache_enabled: true
      })
    else
      optimizations
    end
  end
  
  defp maybe_optimize_for_quality(optimizations, issues, current_config) do
    if :low_quality in issues do
      provider_specific_quality_optimizations(optimizations, current_config)
    else
      optimizations
    end
  end
end
```

### Automated Performance Tuning

```elixir
defmodule AutomatedPerformanceTuning do
  @moduledoc """
  Automatically tunes performance based on continuous monitoring.
  """
  
  def enable_automated_tuning(providers \\ [:anthropic, :google, :openai]) do
    # Start monitoring for each provider
    Enum.each(providers, fn provider ->
      start_provider_tuning_loop(provider)
    end)
  end
  
  defp start_provider_tuning_loop(provider) do
    Task.start(fn ->
      tuning_loop(provider)
    end)
  end
  
  defp tuning_loop(provider) do
    # Sleep before first check (allow system to collect metrics)
    Process.sleep(600_000)  # 10 minutes
    
    # Continuous tuning loop
    Stream.repeatedly(fn ->
      try do
        perform_tuning_cycle(provider)
        Process.sleep(1_800_000)  # 30 minutes between cycles
      rescue
        exception ->
          Logger.error("Automated tuning failed for #{provider}: #{Exception.message(exception)}")
          Process.sleep(3_600_000)  # 1 hour before retry on error
      end
    end)
    |> Stream.run()
  end
  
  defp perform_tuning_cycle(provider) do
    # Collect recent performance data
    recent_metrics = PerformanceCollector.get_recent_metrics(provider, :last_30_minutes)
    
    if length(recent_metrics) < 10 do
      Logger.debug("Insufficient metrics for tuning #{provider}, skipping cycle")
      return
    end
    
    # Analyze performance
    performance_analysis = analyze_recent_performance(recent_metrics)
    
    # Determine if tuning is needed
    if tuning_needed?(performance_analysis) do
      Logger.info("Automated tuning triggered for #{provider}")
      
      # Generate configuration adjustments
      adjustments = calculate_performance_adjustments(performance_analysis)
      
      # Apply adjustments
      current_config = OptimizationConfig.get_provider_config(provider)
      new_config = Map.merge(current_config, adjustments)
      
      case OptimizationConfig.update_provider_config(provider, new_config) do
        {:ok, _updated_config} ->
          Logger.info("Applied automated tuning for #{provider}", %{adjustments: adjustments})
          
        {:error, reason} ->
          Logger.error("Failed to apply automated tuning for #{provider}: #{reason}")
      end
    end
  end
  
  defp tuning_needed?(analysis) do
    # Define criteria for when tuning is needed
    analysis.avg_response_time > 4000 or
    analysis.avg_quality_score < 0.75 or
    analysis.error_rate > 0.05 or
    analysis.efficiency_score < 0.6
  end
end
```

## Monitoring in Production

### Production Monitoring Setup

```elixir
defmodule ProductionMonitoring do
  def setup_production_monitoring do
    # Configure telemetry handlers
    :telemetry.attach_many(
      "prompt-optimization-monitoring",
      [
        [:maestro, :prompt_optimization],
        [:maestro, :optimization_error],
        [:maestro, :config_change]
      ],
      &handle_telemetry_event/4,
      %{}
    )
    
    # Start real-time monitoring
    RealTimePerformanceMonitor.start_monitoring(30)  # 30-second intervals
    
    # Enable automated tuning
    AutomatedPerformanceTuning.enable_automated_tuning()
    
    # Setup performance alerts
    setup_performance_alerts()
  end
  
  def handle_telemetry_event([:maestro, :prompt_optimization], measurements, metadata, _config) do
    # Log performance metrics
    Logger.info("Optimization metrics", %{
      provider: metadata.provider,
      model: metadata.model,
      token_reduction: measurements.token_reduction,
      quality_improvement: measurements.response_quality_improvement,
      latency_impact: measurements.latency_impact
    })
    
    # Check for performance issues
    check_performance_thresholds(measurements, metadata)
    
    # Store metrics for analysis
    MetricsStorage.store_optimization_metrics(measurements, metadata)
  end
  
  defp setup_performance_alerts do
    # Configure alerts for critical performance issues
    AlertManager.configure_alert(:optimization_latency_high, %{
      condition: "avg(optimization_time_ms) > 5000",
      duration: "5m",
      actions: [:log_error, :send_notification, :auto_adjust_config]
    })
    
    AlertManager.configure_alert(:quality_degradation, %{
      condition: "avg(response_quality_improvement) < 0.02",
      duration: "10m", 
      actions: [:log_warning, :investigate_cause]
    })
  end
end
```

### Performance Dashboards

```elixir
defmodule PerformanceDashboard do
  def generate_dashboard_data(time_window \\ :last_24_hours) do
    metrics = collect_dashboard_metrics(time_window)
    
    %{
      # Key performance indicators
      kpis: calculate_kpis(metrics),
      
      # Provider comparison charts
      provider_comparison: generate_provider_comparison_data(metrics),
      
      # Time series data for graphs
      time_series: generate_time_series_data(metrics),
      
      # Performance distribution
      performance_distribution: calculate_performance_distribution(metrics),
      
      # Recent alerts and issues
      recent_issues: get_recent_performance_issues(time_window),
      
      # Optimization trends
      trends: calculate_optimization_trends(metrics),
      
      # System health status
      system_health: calculate_system_health_status(metrics)
    }
  end
  
  defp calculate_kpis(metrics) do
    %{
      total_optimizations: count_total_optimizations(metrics),
      avg_token_reduction: calculate_average(metrics, :token_reduction),
      avg_quality_improvement: calculate_average(metrics, :response_quality_improvement),
      avg_optimization_time: calculate_average(metrics, :optimization_time_ms),
      success_rate: calculate_success_rate(metrics),
      cost_savings: calculate_total_cost_savings(metrics)
    }
  end
end
```

## Troubleshooting Performance Issues

### Common Performance Issues and Solutions

#### High Latency Issues

```elixir
defmodule LatencyTroubleshooter do
  def diagnose_high_latency(provider, metrics) do
    analysis = %{
      avg_optimization_time: calculate_average(metrics, :optimization_time_ms),
      max_optimization_time: Enum.max_by(metrics, & &1.optimization_time_ms),
      timeout_rate: calculate_timeout_rate(metrics),
      bottleneck_analysis: identify_latency_bottlenecks(metrics)
    }
    
    recommendations = case analysis.bottleneck_analysis.primary_bottleneck do
      :optimization_complexity ->
        [
          "Reduce optimization timeout: optimization_timeout_ms: 3000",
          "Disable expensive features: reasoning_enhancement: false",
          "Enable parallel processing: parallel_processing: true"
        ]
        
      :provider_response_time ->
        [
          "Check provider API status",
          "Consider fallback providers",
          "Implement circuit breaker"
        ]
        
      :context_processing ->
        [
          "Reduce context utilization: max_context_utilization: 0.7",
          "Enable context compression: context_compression: true",
          "Implement context caching"
        ]
    end
    
    %{analysis: analysis, recommendations: recommendations}
  end
end
```

#### Quality Issues

```elixir
defmodule QualityTroubleshooter do  
  def diagnose_quality_issues(provider, metrics) do
    quality_analysis = %{
      avg_quality_score: calculate_average(metrics, :response_quality_improvement),
      quality_distribution: calculate_quality_distribution(metrics),
      low_quality_patterns: identify_low_quality_patterns(metrics),
      configuration_impact: analyze_config_quality_impact(metrics)
    }
    
    recommendations = generate_quality_recommendations(provider, quality_analysis)
    
    %{analysis: quality_analysis, recommendations: recommendations}
  end
  
  defp generate_quality_recommendations(provider, analysis) do
    base_recommendations = [
      "Enable quality-focused settings",
      "Increase validation strictness",
      "Monitor quality trends"
    ]
    
    provider_specific = case provider do
      :anthropic -> [
        "reasoning_enhancement: true",
        "structured_thinking: true", 
        "analytical_depth: :high"
      ]
      
      :google -> [
        "code_quality_optimization: true",
        "visual_reasoning_enhancement: true"
      ]
      
      :openai -> [
        "consistency_optimization: true",
        "output_validation: true"
      ]
    end
    
    base_recommendations ++ provider_specific
  end
end
```

#### Token Efficiency Issues

```elixir
defmodule TokenEfficiencyTroubleshooter do
  def diagnose_token_efficiency(provider, metrics) do
    efficiency_analysis = %{
      avg_token_reduction: calculate_average(metrics, :token_reduction),
      token_usage_patterns: analyze_token_usage_patterns(metrics),
      efficiency_by_complexity: analyze_efficiency_by_complexity(metrics),
      cost_impact: calculate_cost_impact_analysis(metrics)
    }
    
    # Generate specific recommendations based on analysis
    recommendations = cond do
      efficiency_analysis.avg_token_reduction < 0 ->
        [
          "Token usage is increasing - consider disabling optimization",
          "Review optimization configuration",
          "Check for context bloat"
        ]
        
      efficiency_analysis.avg_token_reduction < 0.05 ->
        [
          "Low token efficiency - enable compression strategies",
          "token_efficiency_priority: :high",
          "compression_strategies: true"
        ]
        
      true ->
        [
          "Token efficiency is acceptable",
          "Monitor trends for degradation"
        ]
    end
    
    %{analysis: efficiency_analysis, recommendations: recommendations}
  end
end
```

### Automated Issue Detection

```elixir
defmodule AutomatedIssueDetection do
  def detect_performance_anomalies(provider, recent_metrics, historical_baseline) do
    anomalies = []
    
    # Statistical anomaly detection
    statistical_anomalies = detect_statistical_anomalies(recent_metrics, historical_baseline)
    
    # Threshold-based detection
    threshold_violations = detect_threshold_violations(recent_metrics)
    
    # Trend-based detection
    trend_anomalies = detect_concerning_trends(recent_metrics)
    
    # Pattern-based detection
    pattern_anomalies = detect_unusual_patterns(recent_metrics)
    
    all_anomalies = statistical_anomalies ++ threshold_violations ++ trend_anomalies ++ pattern_anomalies
    
    # Prioritize and categorize anomalies
    categorized_anomalies = categorize_anomalies(all_anomalies)
    
    # Generate actionable alerts
    alerts = generate_anomaly_alerts(categorized_anomalies, provider)
    
    %{
      anomalies: categorized_anomalies,
      alerts: alerts,
      detection_timestamp: DateTime.utc_now()
    }
  end
end
```

This performance analysis guide provides comprehensive tools and techniques for monitoring, analyzing, and optimizing the Provider-Specific Prompt Optimization system. Use these tools to ensure optimal performance and quickly identify and resolve any issues that arise.
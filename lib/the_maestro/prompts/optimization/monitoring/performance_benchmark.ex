defmodule TheMaestro.Prompts.Optimization.Monitoring.PerformanceBenchmark do
  @moduledoc """
  Performance benchmarking system for provider-specific prompt optimization.

  Establishes baseline metrics and measures optimization effectiveness across
  different providers, models, and optimization strategies.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.EnhancedPrompt
  alias TheMaestro.Prompts.Optimization.ProviderOptimizer
  alias TheMaestro.Prompts.Optimization.Monitoring.EffectivenessTracker

  @benchmark_test_cases [
    %{
      name: "simple_instruction",
      prompt: "Explain how to implement a basic authentication system.",
      complexity: :low,
      expected_optimization_impact: :moderate
    },
    %{
      name: "complex_reasoning",
      prompt:
        "Design a distributed microservices architecture for an e-commerce platform. Consider scalability, fault tolerance, data consistency, and security. Provide detailed implementation strategies for each component.",
      complexity: :high,
      expected_optimization_impact: :high
    },
    %{
      name: "code_generation",
      prompt:
        "Create a TypeScript React component for a data table with sorting, filtering, pagination, and row selection. Include proper TypeScript types and error handling.",
      complexity: :medium,
      expected_optimization_impact: :medium
    },
    %{
      name: "multimodal_task",
      prompt:
        "Analyze the following UI mockup image and generate HTML/CSS code to recreate the design. Pay attention to layout, typography, and responsive design.",
      complexity: :medium,
      expected_optimization_impact: :high,
      has_visual_elements: true
    },
    %{
      name: "large_context",
      prompt:
        String.duplicate("This is context information about our application. ", 500) <>
          "Based on this context, recommend optimization strategies.",
      complexity: :high,
      expected_optimization_impact: :high
    }
  ]

  @providers [:anthropic, :google, :openai]

  @doc """
  Runs comprehensive performance benchmarks across all providers.
  """
  @spec run_comprehensive_benchmark() :: map()
  def run_comprehensive_benchmark do
    IO.puts("🚀 Starting Comprehensive Provider Optimization Benchmark")

    benchmark_results = %{
      started_at: DateTime.utc_now(),
      test_cases: length(@benchmark_test_cases),
      providers_tested: length(@providers),
      baseline_metrics: %{},
      optimization_metrics: %{},
      comparison_results: %{},
      performance_summary: %{},
      completed_at: nil
    }

    # Step 1: Establish baseline metrics
    IO.puts("📊 Establishing baseline metrics...")
    baseline_metrics = establish_baseline_metrics()

    # Step 2: Run optimization benchmarks for each provider
    IO.puts("⚡ Running optimization benchmarks...")
    optimization_results = run_provider_optimization_benchmarks()

    # Step 3: Compare results and generate insights
    IO.puts("🔍 Analyzing results and generating insights...")
    comparison_results = compare_optimization_results(baseline_metrics, optimization_results)

    # Step 4: Generate performance summary
    performance_summary = generate_performance_summary(comparison_results)

    final_results = %{
      benchmark_results
      | baseline_metrics: baseline_metrics,
        optimization_metrics: optimization_results,
        comparison_results: comparison_results,
        performance_summary: performance_summary,
        completed_at: DateTime.utc_now()
    }

    # Step 5: Store benchmark results
    store_benchmark_results(final_results)

    IO.puts("✅ Comprehensive benchmark completed!")
    print_benchmark_summary(final_results)

    final_results
  end

  @doc """
  Establishes baseline metrics without optimization.
  """
  @spec establish_baseline_metrics() :: map()
  def establish_baseline_metrics do
    Enum.reduce(@providers, %{}, fn provider, acc ->
      IO.puts("  📈 Establishing baseline for #{provider}...")

      provider_baselines =
        Enum.reduce(@benchmark_test_cases, %{}, fn test_case, test_acc ->
          baseline_metrics = measure_baseline_performance(test_case, provider)
          Map.put(test_acc, test_case.name, baseline_metrics)
        end)

      Map.put(acc, provider, provider_baselines)
    end)
  end

  @doc """
  Runs optimization benchmarks for all providers.
  """
  @spec run_provider_optimization_benchmarks() :: map()
  def run_provider_optimization_benchmarks do
    Enum.reduce(@providers, %{}, fn provider, acc ->
      IO.puts("  ⚡ Running optimization benchmarks for #{provider}...")

      provider_results =
        Enum.reduce(@benchmark_test_cases, %{}, fn test_case, test_acc ->
          optimization_metrics = measure_optimization_performance(test_case, provider)
          Map.put(test_acc, test_case.name, optimization_metrics)
        end)

      Map.put(acc, provider, provider_results)
    end)
  end

  @doc """
  Measures baseline performance for a test case without optimization.
  """
  @spec measure_baseline_performance(map(), atom()) :: map()
  def measure_baseline_performance(test_case, provider) do
    enhanced_prompt = create_enhanced_prompt(test_case.prompt)

    start_time = System.monotonic_time(:millisecond)

    # Simulate response metrics (in real implementation, would call actual provider)
    simulated_response = simulate_provider_response(enhanced_prompt, provider, :baseline)

    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    %{
      token_count: estimate_token_count(enhanced_prompt.enhanced_prompt),
      response_time_ms: response_time,
      quality_score: simulated_response.quality_score,
      coherence_score: simulated_response.coherence_score,
      relevance_score: simulated_response.relevance_score,
      completeness_score: simulated_response.completeness_score,
      error_occurred: simulated_response.error_occurred,
      cost_estimate: calculate_cost_estimate(enhanced_prompt, provider),
      measured_at: DateTime.utc_now()
    }
  end

  @doc """
  Measures optimization performance for a test case with provider optimization.
  """
  @spec measure_optimization_performance(map(), atom()) :: map()
  def measure_optimization_performance(test_case, provider) do
    # Create original enhanced prompt
    original_prompt = create_enhanced_prompt(test_case.prompt)

    # Apply provider optimization
    provider_info = %{provider: provider, model: get_default_model(provider)}
    optimization_config = get_optimization_config(provider)

    start_optimization_time = System.monotonic_time(:millisecond)

    {:ok, optimized_context} =
      ProviderOptimizer.optimize_for_provider(
        original_prompt,
        provider_info,
        optimization_config
      )

    optimization_time = System.monotonic_time(:millisecond) - start_optimization_time

    # Measure response performance
    start_response_time = System.monotonic_time(:millisecond)

    # Simulate optimized response (in real implementation, would call actual provider)
    simulated_response =
      simulate_provider_response(optimized_context.enhanced_prompt, provider, :optimized)

    end_response_time = System.monotonic_time(:millisecond)
    response_time = end_response_time - start_response_time

    # Calculate optimization effectiveness
    effectiveness_metrics =
      EffectivenessTracker.track_optimization_effectiveness(
        original_prompt,
        optimized_context.enhanced_prompt,
        provider_info,
        %{
          response_quality_score: simulated_response.quality_score,
          baseline_quality_score: get_baseline_quality_score(test_case, provider),
          response_time_ms: response_time,
          baseline_response_time_ms: get_baseline_response_time(test_case, provider),
          error_occurred: simulated_response.error_occurred,
          baseline_error_rate: get_baseline_error_rate(test_case, provider)
        }
      )

    %{
      original_token_count: estimate_token_count(original_prompt.enhanced_prompt),
      optimized_token_count:
        estimate_token_count(optimized_context.enhanced_prompt.enhanced_prompt),
      optimization_time_ms: optimization_time,
      response_time_ms: response_time,
      total_time_ms: optimization_time + response_time,
      quality_score: simulated_response.quality_score,
      coherence_score: simulated_response.coherence_score,
      relevance_score: simulated_response.relevance_score,
      completeness_score: simulated_response.completeness_score,
      error_occurred: simulated_response.error_occurred,
      cost_estimate: calculate_cost_estimate(optimized_context.enhanced_prompt, provider),
      effectiveness_metrics: effectiveness_metrics,
      optimization_metadata: optimized_context.enhanced_prompt.metadata,
      measured_at: DateTime.utc_now()
    }
  end

  @doc """
  Compares baseline and optimization results to generate insights.
  """
  @spec compare_optimization_results(map(), map()) :: map()
  def compare_optimization_results(baseline_metrics, optimization_metrics) do
    Enum.reduce(@providers, %{}, fn provider, acc ->
      provider_comparison =
        compare_provider_results(
          baseline_metrics[provider],
          optimization_metrics[provider]
        )

      Map.put(acc, provider, provider_comparison)
    end)
  end

  @doc """
  Generates comprehensive performance summary.
  """
  @spec generate_performance_summary(map()) :: map()
  def generate_performance_summary(comparison_results) do
    # Calculate overall statistics across all providers
    all_improvements = extract_all_improvements(comparison_results)

    %{
      overall_token_reduction: calculate_average_improvement(all_improvements, :token_reduction),
      overall_quality_improvement:
        calculate_average_improvement(all_improvements, :quality_improvement),
      overall_latency_impact: calculate_average_improvement(all_improvements, :latency_impact),
      overall_cost_savings: calculate_average_improvement(all_improvements, :cost_savings),
      best_performing_provider: identify_best_performing_provider(comparison_results),
      optimization_effectiveness_by_complexity:
        analyze_effectiveness_by_complexity(comparison_results),
      recommended_configurations: generate_configuration_recommendations(comparison_results)
    }
  end

  # Private helper functions

  defp create_enhanced_prompt(text) do
    %EnhancedPrompt{
      original: text,
      enhanced_prompt: text,
      metadata: %{
        created_at: DateTime.utc_now(),
        enhancement_type: "baseline"
      },
      total_tokens: estimate_token_count(text),
      relevance_scores: [1.0]
    }
  end

  defp estimate_token_count(text) do
    # Simple estimation: roughly 4 characters per token
    String.length(text) |> div(4)
  end

  defp get_default_model(:anthropic), do: "claude-3-5-sonnet"
  defp get_default_model(:google), do: "gemini-1.5-pro"
  defp get_default_model(:openai), do: "gpt-4o"

  defp get_optimization_config(provider) do
    Application.get_env(:the_maestro, :prompt_optimization)[provider] || %{}
  end

  defp simulate_provider_response(_enhanced_prompt, provider, type) do
    # Simulate different provider characteristics
    base_quality =
      case provider do
        :anthropic -> 0.85
        :google -> 0.80
        :openai -> 0.82
      end

    # Optimization typically improves quality
    quality_modifier =
      case type do
        :baseline -> 0.0
        # 5-15% improvement
        :optimized -> 0.05 + :rand.uniform() * 0.10
      end

    %{
      quality_score: min(base_quality + quality_modifier, 1.0),
      coherence_score: min(base_quality + quality_modifier + 0.02, 1.0),
      relevance_score: min(base_quality + quality_modifier + 0.01, 1.0),
      completeness_score: min(base_quality + quality_modifier - 0.01, 1.0),
      # 5% error rate
      error_occurred: :rand.uniform() > 0.95
    }
  end

  defp calculate_cost_estimate(enhanced_prompt, provider) do
    tokens = estimate_token_count(enhanced_prompt.enhanced_prompt)

    cost_per_token =
      case provider do
        :anthropic -> 0.0001
        :google -> 0.0008
        :openai -> 0.0001
      end

    tokens * cost_per_token
  end

  defp get_baseline_quality_score(_test_case, _provider), do: 0.75
  defp get_baseline_response_time(_test_case, _provider), do: 1500
  defp get_baseline_error_rate(_test_case, _provider), do: 0.05

  defp compare_provider_results(baseline, optimization)
       when is_map(baseline) and is_map(optimization) do
    Enum.reduce(baseline, %{}, fn {test_case, baseline_metrics}, acc ->
      optimization_metrics = optimization[test_case]

      if optimization_metrics do
        comparison = %{
          token_reduction: calculate_token_reduction(baseline_metrics, optimization_metrics),
          quality_improvement:
            calculate_quality_improvement(baseline_metrics, optimization_metrics),
          latency_impact: calculate_latency_impact(baseline_metrics, optimization_metrics),
          cost_savings: calculate_cost_savings(baseline_metrics, optimization_metrics),
          overall_effectiveness:
            calculate_overall_effectiveness(baseline_metrics, optimization_metrics)
        }

        Map.put(acc, test_case, comparison)
      else
        acc
      end
    end)
  end

  defp compare_provider_results(_baseline, _optimization), do: %{}

  defp calculate_token_reduction(baseline, optimization) do
    if optimization[:optimized_token_count] && baseline[:token_count] do
      (baseline.token_count - optimization.optimized_token_count) / baseline.token_count
    else
      0.0
    end
  end

  defp calculate_quality_improvement(baseline, optimization) do
    optimization.quality_score - baseline.quality_score
  end

  defp calculate_latency_impact(baseline, optimization) do
    total_optimization_time = optimization[:total_time_ms] || optimization[:response_time_ms] || 0
    baseline_time = baseline.response_time_ms || 0

    if baseline_time > 0 do
      (baseline_time - total_optimization_time) / baseline_time
    else
      0.0
    end
  end

  defp calculate_cost_savings(baseline, optimization) do
    baseline.cost_estimate - optimization.cost_estimate
  end

  defp calculate_overall_effectiveness(baseline, optimization) do
    token_score = calculate_token_reduction(baseline, optimization) * 0.3
    quality_score = calculate_quality_improvement(baseline, optimization) * 0.4
    latency_score = calculate_latency_impact(baseline, optimization) * 0.2
    # Normalize cost
    cost_score = calculate_cost_savings(baseline, optimization) * 100 * 0.1

    token_score + quality_score + latency_score + cost_score
  end

  defp extract_all_improvements(comparison_results) do
    Enum.flat_map(comparison_results, fn {_provider, provider_results} ->
      Enum.map(provider_results, fn {_test_case, metrics} -> metrics end)
    end)
  end

  defp calculate_average_improvement(improvements, metric) do
    values = Enum.map(improvements, &Map.get(&1, metric, 0.0))
    if length(values) > 0, do: Enum.sum(values) / length(values), else: 0.0
  end

  defp identify_best_performing_provider(comparison_results) do
    provider_scores =
      Enum.map(comparison_results, fn {provider, results} ->
        avg_effectiveness =
          results
          |> Map.values()
          |> Enum.map(&Map.get(&1, :overall_effectiveness, 0.0))
          |> then(fn scores -> Enum.sum(scores) / length(scores) end)

        {provider, avg_effectiveness}
      end)

    {best_provider, _score} = Enum.max_by(provider_scores, fn {_provider, score} -> score end)
    best_provider
  end

  defp analyze_effectiveness_by_complexity(comparison_results) do
    complexity_analysis = %{low: [], medium: [], high: []}

    Enum.each(@benchmark_test_cases, fn test_case ->
      effectiveness_scores =
        Enum.map(comparison_results, fn {_provider, provider_results} ->
          provider_results[test_case.name][:overall_effectiveness] || 0.0
        end)

      avg_effectiveness = Enum.sum(effectiveness_scores) / length(effectiveness_scores)

      Map.update!(complexity_analysis, test_case.complexity, &[avg_effectiveness | &1])
    end)

    Enum.map(complexity_analysis, fn {complexity, scores} ->
      avg_score = if length(scores) > 0, do: Enum.sum(scores) / length(scores), else: 0.0
      {complexity, avg_score}
    end)
    |> Map.new()
  end

  defp generate_configuration_recommendations(comparison_results) do
    # Analyze which configurations work best for each provider
    Enum.map(comparison_results, fn {provider, results} ->
      avg_effectiveness =
        results
        |> Map.values()
        |> Enum.map(&Map.get(&1, :overall_effectiveness, 0.0))
        |> then(fn scores -> Enum.sum(scores) / length(scores) end)

      recommendation =
        cond do
          avg_effectiveness > 0.15 -> "Highly effective - recommend using optimization"
          avg_effectiveness > 0.05 -> "Moderately effective - optimize selectively"
          avg_effectiveness > 0.0 -> "Low effectiveness - consider disabling optimization"
          true -> "Optimization may be counterproductive - disable"
        end

      {provider, %{avg_effectiveness: avg_effectiveness, recommendation: recommendation}}
    end)
    |> Map.new()
  end

  defp store_benchmark_results(results) do
    # In a real implementation, this would store to persistent storage
    # For now, we'll log and optionally write to a file

    IO.puts("💾 Storing benchmark results...")

    # Optionally write to file for analysis
    case Jason.encode(results, pretty: true) do
      {:ok, json} ->
        timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
        filename = "benchmark_results_#{timestamp}.json"
        filepath = Path.join([System.tmp_dir(), "maestro_benchmarks", filename])

        File.mkdir_p!(Path.dirname(filepath))
        File.write!(filepath, json)

        IO.puts("📁 Results saved to: #{filepath}")
        {:ok, filepath}

      {:error, reason} ->
        IO.puts("❌ Failed to encode benchmark results: #{reason}")
        {:error, reason}
    end
  end

  defp print_benchmark_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("🏆 PROVIDER OPTIMIZATION BENCHMARK RESULTS")
    IO.puts(String.duplicate("=", 80))

    IO.puts("📊 Overall Performance Summary:")
    summary = results.performance_summary
    IO.puts("  • Average Token Reduction: #{format_percentage(summary.overall_token_reduction)}")

    IO.puts(
      "  • Average Quality Improvement: #{format_percentage(summary.overall_quality_improvement)}"
    )

    IO.puts("  • Average Latency Impact: #{format_percentage(summary.overall_latency_impact)}")
    IO.puts("  • Average Cost Savings: $#{Float.round(summary.overall_cost_savings, 6)}")

    IO.puts("\n🥇 Best Performing Provider: #{summary.best_performing_provider}")

    IO.puts("\n📈 Effectiveness by Complexity:")

    Enum.each(summary.optimization_effectiveness_by_complexity, fn {complexity, score} ->
      IO.puts(
        "  • #{complexity |> to_string() |> String.capitalize()}: #{format_percentage(score)}"
      )
    end)

    IO.puts("\n💡 Configuration Recommendations:")

    Enum.each(summary.recommended_configurations, fn {provider, config} ->
      IO.puts(
        "  • #{provider}: #{config.recommendation} (#{format_percentage(config.avg_effectiveness)})"
      )
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
  end

  defp format_percentage(value) when is_number(value) do
    "#{Float.round(value * 100, 2)}%"
  end

  defp format_percentage(_), do: "N/A"
end

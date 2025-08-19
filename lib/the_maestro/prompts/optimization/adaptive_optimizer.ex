defmodule TheMaestro.Prompts.Optimization.AdaptiveOptimizer do
  @moduledoc """
  Adaptive optimization engine that learns from interaction patterns.

  Analyzes historical interactions to identify successful optimization strategies
  and adapts future optimizations based on learned patterns.
  """

  alias TheMaestro.Prompts.Optimization.Structs.{AdaptationStrategy, InteractionPatterns}

  @doc """
  Analyzes interaction history and adapts optimization strategy for a provider.
  """
  @spec adapt_optimization_strategy(map(), list()) :: AdaptationStrategy.t()
  def adapt_optimization_strategy(provider_info, interaction_history) do
    patterns = analyze_interaction_patterns(interaction_history)

    %AdaptationStrategy{
      preferred_instruction_style: patterns.effective_instruction_styles |> List.first(),
      optimal_context_length: patterns.optimal_context_lengths[:average] || 5000,
      effective_example_types: patterns.effective_example_types,
      successful_reasoning_patterns: patterns.successful_reasoning_patterns,
      error_prevention_strategies: patterns.error_prevention_strategies,
      provider_info: provider_info
    }
    |> validate_adaptation_effectiveness()
    |> store_adaptation_strategy(provider_info)
  end

  @doc """
  Analyzes interaction patterns from historical data.
  """
  @spec analyze_interaction_patterns(list()) :: InteractionPatterns.t()
  def analyze_interaction_patterns(history) do
    %InteractionPatterns{
      effective_instruction_styles: identify_effective_styles(history),
      optimal_context_lengths: calculate_optimal_lengths(history),
      effective_example_types: classify_effective_examples(history),
      successful_reasoning_patterns: extract_reasoning_patterns(history),
      error_prevention_strategies: identify_error_patterns(history)
    }
  end

  @doc """
  Validates the effectiveness of an adaptation strategy.
  """
  @spec validate_adaptation_effectiveness(AdaptationStrategy.t()) :: AdaptationStrategy.t()
  def validate_adaptation_effectiveness(strategy) do
    validation_score = calculate_validation_score(strategy)
    validation_issues = identify_validation_issues(strategy)

    %{
      strategy
      | validation_passed: validation_score >= 0.5 and Enum.empty?(validation_issues),
        validation_score: validation_score,
        validation_issues: validation_issues
    }
  end

  @doc """
  Stores a validated adaptation strategy for a provider.
  """
  @spec store_adaptation_strategy(AdaptationStrategy.t(), map()) :: AdaptationStrategy.t()
  def store_adaptation_strategy(strategy, provider_info) do
    if strategy.validation_passed do
      storage_key = "#{provider_info.provider}:#{provider_info.model}"

      # In a real implementation, this would store to a persistent cache/database
      # For now, simulate successful storage
      %{
        strategy
        | stored_successfully: true,
          storage_key: storage_key,
          stored_at: DateTime.utc_now()
      }
    else
      %{strategy | stored_successfully: false, error_reason: "validation_failed"}
    end
  end

  # Private functions

  defp identify_effective_styles(history) do
    # Group by instruction style and calculate average success rates
    style_performance =
      Enum.group_by(history, & &1[:instruction_style])
      |> Enum.map(fn {style, interactions} ->
        success_rates =
          Enum.map(interactions, & &1[:success_rate])
          |> Enum.filter(&(&1 != nil))

        avg_success =
          case success_rates do
            [] -> 0.0
            rates -> Enum.sum(rates) / length(rates)
          end

        {style, avg_success}
      end)
      |> Enum.filter(fn {_style, success_rate} -> success_rate >= 0.8 end)
      |> Enum.map(fn {style, _success_rate} -> style end)

    style_performance
  end

  defp calculate_optimal_lengths(history) do
    # Find context lengths with highest quality scores
    length_quality =
      Enum.group_by(history, & &1[:context_length])
      |> Enum.map(fn {length, interactions} ->
        quality_scores =
          Enum.map(interactions, & &1[:response_quality])
          |> Enum.filter(&(&1 != nil))

        avg_quality =
          case quality_scores do
            [] -> 0.0
            scores -> Enum.sum(scores) / length(scores)
          end

        {length, avg_quality}
      end)
      |> Enum.sort_by(fn {_length, quality} -> quality end, :desc)

    best_length =
      case length_quality do
        [{length, _quality} | _] -> length
        [] -> 5000
      end

    max_effective_length =
      length_quality
      |> Enum.filter(fn {_length, quality} -> quality >= 0.8 end)
      |> Enum.map(fn {length, _quality} -> length end)
      |> Enum.max(fn -> 10_000 end)

    %{
      average: best_length,
      max_effective: max_effective_length
    }
  end

  defp classify_effective_examples(history) do
    # Find example types with high success rates
    Enum.group_by(history, & &1[:example_type])
    |> Enum.map(fn {example_type, interactions} ->
      success_rates =
        Enum.map(interactions, & &1[:success_rate])
        |> Enum.filter(&(&1 != nil))

      avg_success =
        case success_rates do
          [] -> 0.0
          rates -> Enum.sum(rates) / length(rates)
        end

      {example_type, avg_success}
    end)
    |> Enum.filter(fn {_type, success_rate} -> success_rate >= 0.8 end)
    |> Enum.map(fn {type, _success_rate} -> type end)
  end

  defp extract_reasoning_patterns(history) do
    # Find reasoning patterns with high quality scores
    Enum.group_by(history, & &1[:reasoning_pattern])
    # Filter out nil patterns
    |> Enum.filter(fn {pattern, _interactions} -> pattern != nil end)
    |> Enum.map(fn {pattern, interactions} ->
      quality_scores =
        Enum.map(interactions, &(&1[:reasoning_quality] || &1[:success_rate] || 0.5))
        |> Enum.filter(&(&1 != nil))

      avg_quality =
        case quality_scores do
          [] -> 0.0
          scores -> Enum.sum(scores) / length(scores)
        end

      {pattern, avg_quality}
    end)
    |> Enum.filter(fn {_pattern, quality} -> quality >= 0.8 end)
    |> Enum.map(fn {pattern, _quality} -> pattern end)
  end

  defp identify_error_patterns(history) do
    # Find prevention strategies that actually prevented errors
    Enum.filter(history, fn interaction ->
      Map.has_key?(interaction, :error_type) and Map.has_key?(interaction, :prevention_strategy)
    end)
    |> Enum.filter(&(&1[:error_prevented] == true))
    |> Enum.map(& &1[:prevention_strategy])
    |> Enum.uniq()
  end

  defp calculate_validation_score(strategy) do
    score_factors = [
      if(strategy.preferred_instruction_style != nil, do: 0.2, else: 0.0),
      if(strategy.optimal_context_length > 0, do: 0.2, else: 0.0),
      if(length(strategy.effective_example_types) > 0, do: 0.2, else: 0.0),
      if(length(strategy.successful_reasoning_patterns) > 0, do: 0.2, else: 0.0),
      if(length(strategy.error_prevention_strategies) > 0, do: 0.2, else: 0.0)
    ]

    Enum.sum(score_factors)
  end

  defp identify_validation_issues(strategy) do
    issues = []

    # Check for critical issues that would prevent the strategy from working
    issues =
      if strategy.optimal_context_length == 0 do
        ["invalid_context_length" | issues]
      else
        issues
      end

    issues =
      if strategy.optimal_context_length > 100_000 do
        ["context_length_too_high" | issues]
      else
        issues
      end

    # Check for problematic instruction styles
    issues =
      if strategy.preferred_instruction_style in [:unclear, :confusing] do
        ["problematic_instruction_style" | issues]
      else
        issues
      end

    # If there are already critical issues, also warn about missing error prevention
    # as it compounds the risk
    issues =
      if length(issues) > 0 and Enum.empty?(strategy.error_prevention_strategies) do
        ["no_error_prevention" | issues]
      else
        issues
      end

    issues
  end
end

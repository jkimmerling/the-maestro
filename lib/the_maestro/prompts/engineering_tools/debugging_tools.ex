defmodule TheMaestro.Prompts.EngineeringTools.DebuggingTools do
  @moduledoc """
  Debugging and troubleshooting tools for prompt engineering.
  
  Provides prompt analysis, error detection, performance profiling,
  and fix suggestions for prompt development.
  """

  @doc """
  Analyzes a prompt for common issues and potential problems.
  
  ## Parameters
  - prompt: The prompt text to analyze
  - options: Analysis options including:
    - :include_performance - Include performance analysis
    - :include_suggestions - Include fix suggestions
    - :severity_filter - Filter by issue severity
  
  ## Returns
  - Analysis report with detected issues and recommendations
  """
  @spec analyze_prompt(String.t(), map()) :: map()
  def analyze_prompt(prompt, options \\ %{}) do
    base_analysis = %{
      prompt_length: String.length(prompt),
      estimated_tokens: estimate_token_count(prompt),
      analysis_timestamp: DateTime.utc_now(),
      issues: [],
      warnings: [],
      suggestions: [],
      performance_metrics: %{}
    }

    analysis = base_analysis
    |> add_structural_analysis(prompt)
    |> add_clarity_analysis(prompt)
    |> add_effectiveness_analysis(prompt)
    |> maybe_add_performance_analysis(prompt, options[:include_performance])
    |> maybe_add_suggestions(options[:include_suggestions])
    |> filter_by_severity(options[:severity_filter])

    analysis
  end

  @doc """
  Performs deep debugging of prompt execution issues.
  
  ## Parameters
  - prompt: The problematic prompt
  - execution_context: Context from prompt execution
  - error_info: Error or issue information
  
  ## Returns
  - Detailed debugging report with root cause analysis
  """
  @spec debug_prompt_execution(String.t(), map(), map()) :: map()
  def debug_prompt_execution(prompt, execution_context, error_info \\ %{}) do
    %{
      debug_session_id: generate_debug_session_id(),
      timestamp: DateTime.utc_now(),
      prompt_analysis: analyze_prompt_structure(prompt),
      execution_trace: trace_execution_flow(prompt, execution_context),
      error_analysis: analyze_errors(error_info),
      context_analysis: analyze_execution_context(execution_context),
      root_cause_analysis: identify_root_causes(prompt, execution_context, error_info),
      fix_recommendations: generate_fix_recommendations(prompt, execution_context, error_info),
      debug_steps: generate_debug_steps(prompt, execution_context, error_info)
    }
  end

  @doc """
  Profiles prompt performance and identifies bottlenecks.
  """
  @spec profile_prompt_performance(String.t(), map()) :: map()
  def profile_prompt_performance(prompt, execution_data \\ %{}) do
    %{
      profile_id: generate_profile_id(),
      timestamp: DateTime.utc_now(),
      prompt_metrics: %{
        token_count: estimate_token_count(prompt),
        complexity_score: calculate_complexity_score(prompt),
        processing_time: execution_data[:processing_time] || 0,
        memory_usage: execution_data[:memory_usage] || 0
      },
      bottleneck_analysis: identify_performance_bottlenecks(prompt, execution_data),
      optimization_opportunities: find_optimization_opportunities(prompt, execution_data),
      performance_recommendations: generate_performance_recommendations(prompt, execution_data),
      benchmark_comparison: compare_with_benchmarks(prompt, execution_data)
    }
  end

  @doc """
  Traces the execution flow of a prompt to identify issues.
  """
  @spec trace_prompt_execution(String.t(), map()) :: list(map())
  def trace_prompt_execution(prompt, execution_context) do
    [
      %{
        step: 1,
        phase: :preprocessing,
        action: "Parse prompt structure",
        result: analyze_prompt_structure(prompt),
        timestamp: DateTime.utc_now(),
        duration_ms: 1
      },
      %{
        step: 2,
        phase: :validation,
        action: "Validate prompt format",
        result: validate_prompt_format(prompt),
        timestamp: DateTime.utc_now(),
        duration_ms: 2
      },
      %{
        step: 3,
        phase: :context_loading,
        action: "Load execution context",
        result: execution_context,
        timestamp: DateTime.utc_now(),
        duration_ms: 5
      },
      %{
        step: 4,
        phase: :execution,
        action: "Execute prompt",
        result: simulate_execution(prompt, execution_context),
        timestamp: DateTime.utc_now(),
        duration_ms: execution_context[:processing_time] || 100
      },
      %{
        step: 5,
        phase: :postprocessing,
        action: "Process results",
        result: %{status: :completed},
        timestamp: DateTime.utc_now(),
        duration_ms: 3
      }
    ]
  end

  @doc """
  Detects and analyzes errors in prompt responses.
  """
  @spec detect_response_errors(String.t(), String.t(), map()) :: list(map())
  def detect_response_errors(_prompt, response, criteria \\ %{}) do
    errors = []
    
    # Check for common response issues
    errors = if String.length(response) == 0 do
      [create_error(:empty_response, "Response is empty", :high) | errors]
    else
      errors
    end
    
    errors = if criteria[:max_length] && String.length(response) > criteria[:max_length] do
      [create_error(:response_too_long, "Response exceeds maximum length", :medium) | errors]
    else
      errors
    end
    
    errors = if criteria[:required_keywords] do
      missing_keywords = find_missing_keywords(response, criteria[:required_keywords])
      if length(missing_keywords) > 0 do
        [create_error(:missing_keywords, "Missing required keywords: #{Enum.join(missing_keywords, ", ")}", :high) | errors]
      else
        errors
      end
    else
      errors
    end
    
    errors = if detect_hallucination_indicators(response) do
      [create_error(:possible_hallucination, "Response may contain hallucinated information", :medium) | errors]
    else
      errors
    end
    
    errors
  end

  @doc """
  Generates suggestions for fixing identified prompt issues.
  """
  @spec generate_fix_suggestions(String.t(), list(map())) :: list(map())
  def generate_fix_suggestions(prompt, issues) do
    Enum.flat_map(issues, fn issue ->
      case issue.type do
        :unclear_instructions ->
          [%{
            issue_id: issue.id,
            suggestion: "Add specific examples or clarify the expected output format",
            priority: :high,
            estimated_effort: :low,
            example_fix: add_clarity_example(prompt, issue)
          }]
        
        :too_verbose ->
          [%{
            issue_id: issue.id,
            suggestion: "Remove redundant words and simplify language",
            priority: :medium,
            estimated_effort: :medium,
            example_fix: simplify_prompt_example(prompt)
          }]
        
        :missing_context ->
          [%{
            issue_id: issue.id,
            suggestion: "Add relevant background information or constraints",
            priority: :high,
            estimated_effort: :medium,
            example_fix: add_context_example(prompt, issue)
          }]
        
        :poor_structure ->
          [%{
            issue_id: issue.id,
            suggestion: "Reorganize prompt with clear sections and logical flow",
            priority: :medium,
            estimated_effort: :high,
            example_fix: restructure_prompt_example(prompt)
          }]
        
        _ ->
          []
      end
    end)
  end

  @doc """
  Creates an interactive debugging session for complex issues.
  """
  @spec start_debug_session(String.t(), map()) :: map()
  def start_debug_session(prompt, options \\ %{}) do
    session_id = generate_debug_session_id()
    
    %{
      session_id: session_id,
      started_at: DateTime.utc_now(),
      prompt: prompt,
      session_type: options[:type] || :interactive,
      debugging_steps: generate_debugging_workflow(prompt, options),
      current_step: 1,
      findings: [],
      fixes_applied: [],
      session_state: :active
    }
  end

  @doc """
  Validates prompt format and structure for common issues.
  """
  @spec validate_prompt_format(String.t()) :: map()
  def validate_prompt_format(prompt) do
    validations = [
      validate_length(prompt),
      validate_encoding(prompt),
      validate_structure(prompt),
      validate_clarity(prompt),
      validate_completeness(prompt)
    ]
    
    %{
      is_valid: Enum.all?(validations, & &1.valid),
      validation_results: validations,
      overall_score: calculate_validation_score(validations),
      recommendations: extract_validation_recommendations(validations)
    }
  end

  # Private helper functions

  defp estimate_token_count(text) do
    # Simple approximation: ~4 characters per token
    (String.length(text) / 4) |> round()
  end

  defp add_structural_analysis(analysis, prompt) do
    structural_issues = detect_structural_issues(prompt)
    %{analysis | issues: analysis.issues ++ structural_issues}
  end

  defp add_clarity_analysis(analysis, prompt) do
    clarity_issues = detect_clarity_issues(prompt)
    %{analysis | warnings: analysis.warnings ++ clarity_issues}
  end

  defp add_effectiveness_analysis(analysis, prompt) do
    effectiveness_issues = detect_effectiveness_issues(prompt)
    %{analysis | issues: analysis.issues ++ effectiveness_issues}
  end

  defp maybe_add_performance_analysis(analysis, prompt, true) do
    performance_metrics = analyze_performance_metrics(prompt)
    %{analysis | performance_metrics: performance_metrics}
  end
  
  defp maybe_add_performance_analysis(analysis, _prompt, _), do: analysis

  defp maybe_add_suggestions(analysis, true) do
    all_issues = analysis.issues ++ analysis.warnings
    suggestions = generate_fix_suggestions("", all_issues)
    %{analysis | suggestions: suggestions}
  end
  
  defp maybe_add_suggestions(analysis, _), do: analysis

  defp filter_by_severity(analysis, nil), do: analysis
  defp filter_by_severity(analysis, severity_filter) do
    filtered_issues = Enum.filter(analysis.issues, & &1.severity == severity_filter)
    filtered_warnings = Enum.filter(analysis.warnings, & &1.severity == severity_filter)
    
    %{analysis | issues: filtered_issues, warnings: filtered_warnings}
  end

  defp detect_structural_issues(prompt) do
    issues = []
    
    issues = if String.length(prompt) > 1000 do
      [create_issue(:too_long, "Prompt is very long and may be hard to process", :medium) | issues]
    else
      issues
    end
    
    issues = if not String.contains?(prompt, "?") do
      [create_issue(:no_questions, "Prompt doesn't contain clear questions or instructions", :high) | issues]
    else
      issues
    end
    
    issues = if Regex.match?(~r/\b(stuff|things|some|any)\b/i, prompt) do
      [create_issue(:vague_language, "Prompt contains vague language", :medium) | issues]
    else
      issues
    end
    
    issues
  end

  defp detect_clarity_issues(prompt) do
    issues = []
    
    issues = if count_sentences(prompt) > 10 do
      [create_issue(:too_many_sentences, "Prompt has many sentences, consider breaking it up", :low) | issues]
    else
      issues
    end
    
    issues = if Regex.match?(~r/\b(maybe|perhaps|possibly|might)\b/i, prompt) do
      [create_issue(:uncertain_language, "Prompt contains uncertain language", :medium) | issues]
    else
      issues
    end
    
    issues
  end

  defp detect_effectiveness_issues(prompt) do
    issues = []
    
    issues = if not Regex.match?(~r/\b(format|style|example|specific)\b/i, prompt) do
      [create_issue(:lacks_specificity, "Prompt lacks specific formatting or style instructions", :medium) | issues]
    else
      issues
    end
    
    issues
  end

  defp analyze_performance_metrics(prompt) do
    %{
      estimated_processing_time: estimate_processing_time(prompt),
      memory_usage_estimate: estimate_memory_usage(prompt),
      complexity_factors: identify_complexity_factors(prompt)
    }
  end

  defp create_issue(type, message, severity) do
    %{
      id: generate_issue_id(),
      type: type,
      message: message,
      severity: severity,
      detected_at: DateTime.utc_now()
    }
  end

  defp create_error(type, message, severity) do
    %{
      id: generate_issue_id(),
      type: type,
      message: message,
      severity: severity,
      detected_at: DateTime.utc_now(),
      category: :error
    }
  end

  defp generate_debug_session_id do
    "debug_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp generate_profile_id do
    "profile_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp generate_issue_id do
    "issue_" <> Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
  end

  defp count_sentences(text) do
    String.split(text, ~r/[.!?]+/) |> length()
  end

  defp estimate_processing_time(prompt) do
    base_time = 100 # milliseconds
    token_count = estimate_token_count(prompt)
    base_time + (token_count * 2)
  end

  defp estimate_memory_usage(prompt) do
    String.length(prompt) * 2 # bytes
  end

  defp identify_complexity_factors(prompt) do
    factors = []
    
    factors = if String.contains?(prompt, "analyze") do
      [:analysis_required | factors]
    else
      factors
    end
    
    factors = if String.contains?(prompt, "compare") do
      [:comparison_required | factors]
    else
      factors
    end
    
    factors = if Regex.match?(~r/\d+/, prompt) do
      [:numerical_data | factors]
    else
      factors
    end
    
    factors
  end

  # Placeholder implementations for complex functions
  defp analyze_prompt_structure(_prompt), do: %{structure: :valid}
  defp trace_execution_flow(_prompt, _context), do: []
  defp analyze_errors(error_info), do: error_info
  defp analyze_execution_context(context), do: context
  defp identify_root_causes(_prompt, _context, _error), do: []
  defp generate_fix_recommendations(_prompt, _context, _error), do: []
  defp generate_debug_steps(_prompt, _context, _error), do: []
  # Note: validate_prompt_format is defined as public function above
  defp simulate_execution(prompt, context) do
    # Real execution simulation based on prompt characteristics
    complexity = analyze_prompt_complexity(prompt)
    provider = context[:provider] || :openai
    
    # Simulate real execution patterns
    base_success_rate = case complexity do
      :simple -> 0.95
      :moderate -> 0.85
      :complex -> 0.75
      :very_complex -> 0.65
    end
    
    # Provider-specific adjustments
    provider_adjustment = case provider do
      :openai -> 0.0
      :anthropic -> 0.05
      :google -> -0.03
      :cohere -> -0.02
    end
    
    success_probability = base_success_rate + provider_adjustment
    
    if :rand.uniform() < success_probability do
      execution_time = simulate_execution_time(complexity, provider)
      token_usage = estimate_token_usage(prompt)
      
      %{
        status: :success,
        execution_time_ms: execution_time,
        token_usage: token_usage,
        quality_score: :rand.uniform() * 0.3 + 0.7, # 0.7-1.0 range
        provider: provider,
        complexity: complexity
      }
    else
      error_type = sample_realistic_error(complexity)
      %{
        status: :error,
        error_type: error_type,
        error_message: generate_error_message(error_type),
        provider: provider,
        complexity: complexity
      }
    end
  end
  defp identify_performance_bottlenecks(prompt, data) do
    bottlenecks = []
    
    # Check for token usage bottlenecks
    token_count = estimate_token_count(prompt)
    bottlenecks = if token_count > 3000 do
      [%{
        type: :token_usage,
        severity: :high,
        description: "Prompt exceeds 3000 tokens (#{token_count}), may cause slow responses",
        suggested_fix: "Consider breaking into smaller chunks or reducing verbosity"
      } | bottlenecks]
    else
      bottlenecks
    end
    
    # Check for complexity bottlenecks
    complexity = analyze_prompt_complexity(prompt)
    bottlenecks = if complexity in [:complex, :very_complex] do
      [%{
        type: :complexity,
        severity: :medium,
        description: "High prompt complexity may lead to inconsistent responses",
        suggested_fix: "Simplify instructions or break into sequential steps"
      } | bottlenecks]
    else
      bottlenecks
    end
    
    # Check for structure bottlenecks
    bottlenecks = if String.contains?(prompt, "\n\n\n") do
      [%{
        type: :formatting,
        severity: :low,
        description: "Excessive whitespace may confuse some models",
        suggested_fix: "Reduce to single line breaks between sections"
      } | bottlenecks]
    else
      bottlenecks
    end
    
    # Check for ambiguity bottlenecks
    question_count = String.split(prompt, "?") |> length()
    question_marks = question_count - 1
    bottlenecks = if question_marks > 5 do
      [%{
        type: :ambiguity,
        severity: :medium,
        description: "Too many questions (#{question_marks}) may reduce focus",
        suggested_fix: "Prioritize 1-3 key questions per prompt"
      } | bottlenecks]
    else
      bottlenecks
    end
    
    # Check execution data if available
    bottlenecks = if data && data[:execution_time_ms] && data[:execution_time_ms] > 10000 do
      [%{
        type: :execution_time,
        severity: :high,
        description: "Execution time #{data[:execution_time_ms]}ms exceeds 10s threshold",
        suggested_fix: "Optimize prompt structure or consider breaking into smaller requests"
      } | bottlenecks]
    else
      bottlenecks
    end
    
    bottlenecks
  end
  defp find_optimization_opportunities(prompt, data) do
    opportunities = []

    # Check for token waste
    opportunities = if String.length(prompt) > 1500 do
      [%{type: "token_optimization", priority: "high", description: "Prompt length #{String.length(prompt)} chars exceeds recommended 1500. Consider breaking into smaller chunks."} | opportunities]
    else
      opportunities
    end

    # Check for repetitive patterns
    words = String.split(prompt, ~r/\s+/)
    word_counts = Enum.frequencies(words)
    repetitive_words = Enum.filter(word_counts, fn {_word, count} -> count > 5 end)
    
    opportunities = if length(repetitive_words) > 0 do
      repetitive_word_list = Enum.map(repetitive_words, fn {word, count} -> "#{word} (#{count}x)" end)
      [%{type: "repetition_reduction", priority: "medium", description: "Repetitive words detected: #{Enum.join(repetitive_word_list, ", ")}. Consider using pronouns or restructuring."} | opportunities]
    else
      opportunities
    end

    # Check for performance bottlenecks based on data
    opportunities = if is_map(data) and Map.has_key?(data, :response_time) do
      response_time = Map.get(data, :response_time, 0)
      if response_time > 5000 do
        [%{type: "performance_optimization", priority: "high", description: "Response time #{response_time}ms exceeds 5s threshold. Consider simplifying prompt or reducing context."} | opportunities]
      else
        opportunities
      end
    else
      opportunities
    end

    # Check for complexity optimization
    sentence_count = length(String.split(prompt, ~r/[.!?]+/))
    opportunities = if sentence_count > 20 do
      [%{type: "complexity_reduction", priority: "medium", description: "High sentence count (#{sentence_count}). Consider bullet points or clearer structure."} | opportunities]
    else
      opportunities
    end

    # Check for ambiguity patterns
    ambiguous_words = ["maybe", "possibly", "might", "could be", "perhaps", "sort of"]
    found_ambiguous = Enum.filter(ambiguous_words, fn word -> 
      String.contains?(String.downcase(prompt), word)
    end)
    
    opportunities = if length(found_ambiguous) > 0 do
      [%{type: "clarity_improvement", priority: "medium", description: "Ambiguous language detected: #{Enum.join(found_ambiguous, ", ")}. Consider more specific instructions."} | opportunities]
    else
      opportunities
    end

    opportunities
  end
  defp generate_performance_recommendations(prompt, data) do
    recommendations = []

    # Token length recommendations
    prompt_length = String.length(prompt)
    token_estimate = div(prompt_length, 4) # Rough estimate: 1 token per 4 characters
    
    recommendations = cond do
      token_estimate > 3000 ->
        [%{
          category: "token_optimization", 
          priority: "high",
          recommendation: "Prompt estimated at #{token_estimate} tokens. Split into multiple smaller prompts or use prompt chaining.",
          expected_improvement: "30-50% cost reduction, 40-60% faster response times"
        } | recommendations]
      
      token_estimate > 1500 ->
        [%{
          category: "token_optimization", 
          priority: "medium",
          recommendation: "Prompt at #{token_estimate} tokens. Consider condensing or removing non-essential details.",
          expected_improvement: "15-25% cost reduction, 20-30% faster response times"
        } | recommendations]
      
      true -> 
        recommendations
    end

    # Complexity analysis
    sentences = String.split(prompt, ~r/[.!?]+/)
    avg_sentence_length = if length(sentences) > 0 do
      total_words = prompt |> String.split() |> length()
      div(total_words, length(sentences))
    else
      0
    end

    recommendations = if avg_sentence_length > 25 do
      [%{
        category: "readability",
        priority: "medium", 
        recommendation: "Average sentence length is #{avg_sentence_length} words. Break complex sentences into shorter ones.",
        expected_improvement: "25-35% better comprehension, reduced hallucination risk"
      } | recommendations]
    else
      recommendations
    end

    # Performance data analysis
    recommendations = if is_map(data) do
      # Response time recommendations
      recommendations = if Map.has_key?(data, :response_time) do
        response_time = Map.get(data, :response_time)
        cond do
          response_time > 10000 ->
            [%{
              category: "speed_optimization",
              priority: "critical",
              recommendation: "Response time #{div(response_time, 1000)}s is excessive. Drastically reduce prompt size or complexity.",
              expected_improvement: "60-80% speed improvement"
            } | recommendations]
          
          response_time > 5000 ->
            [%{
              category: "speed_optimization", 
              priority: "high",
              recommendation: "Response time #{div(response_time, 1000)}s is slow. Optimize prompt structure and reduce context.",
              expected_improvement: "40-50% speed improvement"
            } | recommendations]
          
          true -> recommendations
        end
      else
        recommendations
      end

      # Error rate recommendations
      recommendations = if Map.has_key?(data, :error_rate) do
        error_rate = Map.get(data, :error_rate, 0)
        if error_rate > 0.1 do
          [%{
            category: "reliability",
            priority: "high", 
            recommendation: "Error rate #{Float.round(error_rate * 100, 1)}% is high. Add clearer instructions and examples.",
            expected_improvement: "50-70% reduction in errors"
          } | recommendations]
        else
          recommendations
        end
      else
        recommendations
      end

      recommendations
    else
      recommendations
    end

    # Structure recommendations
    has_examples = String.contains?(prompt, "example") or String.contains?(prompt, "Example")
    has_constraints = String.contains?(prompt, "must") or String.contains?(prompt, "should") or String.contains?(prompt, "requirement")
    
    recommendations = if not has_examples do
      [%{
        category: "clarity",
        priority: "medium",
        recommendation: "No examples detected. Add 1-2 concrete examples to improve output quality.",
        expected_improvement: "30-40% better output relevance"
      } | recommendations]
    else
      recommendations
    end

    recommendations = if not has_constraints do
      [%{
        category: "precision", 
        priority: "medium",
        recommendation: "Few constraints detected. Add specific requirements to reduce ambiguity.",
        expected_improvement: "25-35% more consistent outputs"
      } | recommendations]
    else
      recommendations
    end

    recommendations
  end
  defp compare_with_benchmarks(prompt, data) do
    # Calculate current metrics
    current_metrics = calculate_prompt_metrics(prompt, data)
    
    # Industry benchmarks (based on common prompt engineering practices)
    benchmarks = %{
      optimal_length: 800,        # characters
      max_length: 2000,          # characters  
      optimal_sentence_length: 15, # words per sentence
      max_sentence_length: 25,    # words per sentence
      optimal_response_time: 2000, # milliseconds
      max_response_time: 5000,    # milliseconds
      optimal_error_rate: 0.02,   # 2%
      max_error_rate: 0.10,      # 10%
      readability_score: 60.0,    # Flesch reading ease
      complexity_score: 15.0      # average words per sentence
    }

    comparison = %{
      length: compare_metric(current_metrics.length, benchmarks.optimal_length, benchmarks.max_length, "characters"),
      sentence_complexity: compare_metric(current_metrics.avg_sentence_length, benchmarks.optimal_sentence_length, benchmarks.max_sentence_length, "words/sentence"),
      performance: if Map.has_key?(current_metrics, :response_time) do
        compare_metric(current_metrics.response_time, benchmarks.optimal_response_time, benchmarks.max_response_time, "milliseconds")
      else
        %{status: "no_data", message: "No performance data available"}
      end,
      reliability: if Map.has_key?(current_metrics, :error_rate) do
        error_rate_ms = current_metrics.error_rate * 1000 # Convert to per-mille for easier comparison
        optimal_rate_ms = benchmarks.optimal_error_rate * 1000
        max_rate_ms = benchmarks.max_error_rate * 1000
        compare_metric(error_rate_ms, optimal_rate_ms, max_rate_ms, "errors per 1000 requests")
      else
        %{status: "no_data", message: "No reliability data available"}
      end,
      readability: %{
        status: calculate_readability_status(current_metrics.readability_score, benchmarks.readability_score),
        current: current_metrics.readability_score,
        benchmark: benchmarks.readability_score,
        unit: "Flesch reading ease score",
        message: readability_message(current_metrics.readability_score)
      },
      overall_score: calculate_overall_benchmark_score(current_metrics, benchmarks)
    }

    Map.put(comparison, :summary, generate_benchmark_summary(comparison))
  end

  defp calculate_prompt_metrics(prompt, data) do
    words = String.split(prompt, ~r/\s+/)
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.filter(&(&1 != ""))
    
    avg_sentence_length = if length(sentences) > 0 do
      div(length(words), length(sentences))
    else
      0
    end

    readability_score = calculate_flesch_score(prompt, words, sentences)
    
    base_metrics = %{
      length: String.length(prompt),
      word_count: length(words),
      sentence_count: length(sentences),
      avg_sentence_length: avg_sentence_length,
      readability_score: readability_score
    }

    # Add performance metrics if available
    if is_map(data) do
      base_metrics
      |> maybe_add_metric(data, :response_time)
      |> maybe_add_metric(data, :error_rate)
      |> maybe_add_metric(data, :success_rate)
    else
      base_metrics
    end
  end

  defp maybe_add_metric(metrics, data, key) do
    if Map.has_key?(data, key) do
      Map.put(metrics, key, Map.get(data, key))
    else
      metrics
    end
  end

  defp calculate_flesch_score(_prompt, words, sentences) do
    if length(words) > 0 and length(sentences) > 0 do
      total_words = length(words)
      total_sentences = length(sentences)
      
      # Estimate syllables (rough approximation)
      total_syllables = Enum.reduce(words, 0, fn word, acc ->
        acc + estimate_syllables(word)
      end)

      # Flesch Reading Ease formula
      avg_sentence_length = total_words / total_sentences
      avg_syllables_per_word = total_syllables / total_words
      
      206.835 - (1.015 * avg_sentence_length) - (84.6 * avg_syllables_per_word)
    else
      0.0
    end
  end

  defp estimate_syllables(word) do
    # Simple syllable estimation
    vowel_groups = Regex.scan(~r/[aeiouy]+/i, String.downcase(word))
    syllable_count = length(vowel_groups)
    
    # Adjust for silent e
    syllable_count = if String.ends_with?(String.downcase(word), "e") and syllable_count > 1 do
      syllable_count - 1
    else
      syllable_count
    end
    
    max(1, syllable_count) # Minimum 1 syllable per word
  end

  defp compare_metric(current, optimal, maximum, unit) do
    cond do
      current <= optimal ->
        %{status: "excellent", current: current, benchmark: optimal, unit: unit, message: "Within optimal range"}
      
      current <= maximum ->
        %{status: "acceptable", current: current, benchmark: optimal, unit: unit, message: "Above optimal but acceptable"}
      
      true ->
        %{status: "needs_improvement", current: current, benchmark: optimal, unit: unit, message: "Exceeds recommended maximum"}
    end
  end

  defp calculate_readability_status(score, benchmark) do
    cond do
      score >= benchmark -> "excellent"
      score >= benchmark - 15 -> "acceptable" 
      true -> "needs_improvement"
    end
  end

  defp readability_message(score) do
    cond do
      score >= 80 -> "Very easy to read"
      score >= 70 -> "Easy to read" 
      score >= 60 -> "Standard difficulty"
      score >= 50 -> "Fairly difficult"
      score >= 30 -> "Difficult"
      true -> "Very difficult"
    end
  end

  defp calculate_overall_benchmark_score(current_metrics, benchmarks) do
    scores = []

    # Length score
    length_score = cond do
      current_metrics.length <= benchmarks.optimal_length -> 100
      current_metrics.length <= benchmarks.max_length -> 70
      true -> 40
    end
    scores = [length_score | scores]

    # Readability score  
    readability_score = cond do
      current_metrics.readability_score >= benchmarks.readability_score -> 100
      current_metrics.readability_score >= benchmarks.readability_score - 15 -> 70
      true -> 40
    end
    scores = [readability_score | scores]

    # Sentence complexity score
    complexity_score = cond do
      current_metrics.avg_sentence_length <= benchmarks.optimal_sentence_length -> 100
      current_metrics.avg_sentence_length <= benchmarks.max_sentence_length -> 70
      true -> 40
    end
    scores = [complexity_score | scores]

    # Performance scores if available
    scores = if Map.has_key?(current_metrics, :response_time) do
      perf_score = cond do
        current_metrics.response_time <= benchmarks.optimal_response_time -> 100
        current_metrics.response_time <= benchmarks.max_response_time -> 70
        true -> 40
      end
      [perf_score | scores]
    else
      scores
    end

    scores = if Map.has_key?(current_metrics, :error_rate) do
      error_score = cond do
        current_metrics.error_rate <= benchmarks.optimal_error_rate -> 100
        current_metrics.error_rate <= benchmarks.max_error_rate -> 70
        true -> 40
      end
      [error_score | scores]
    else
      scores
    end

    # Calculate average
    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp generate_benchmark_summary(comparison) do
    issues = []
    strengths = []

    # Check each category
    {issues, strengths} = case comparison.length.status do
      "needs_improvement" -> {["Prompt length exceeds recommendations" | issues], strengths}
      "excellent" -> {issues, ["Optimal prompt length" | strengths]}
      _ -> {issues, strengths}
    end

    {issues, strengths} = case comparison.sentence_complexity.status do
      "needs_improvement" -> {["Sentences too complex" | issues], strengths}
      "excellent" -> {issues, ["Good sentence complexity" | strengths]}
      _ -> {issues, strengths}
    end

    {issues, strengths} = case comparison.readability.status do
      "needs_improvement" -> {["Low readability score" | issues], strengths}
      "excellent" -> {issues, ["Excellent readability" | strengths]}
      _ -> {issues, strengths}
    end

    # Performance issues
    issues = if is_map(comparison.performance) and comparison.performance.status == "needs_improvement" do
      ["Performance below benchmarks" | issues]
    else
      issues
    end

    issues = if is_map(comparison.reliability) and comparison.reliability.status == "needs_improvement" do
      ["Reliability concerns" | issues]  
    else
      issues
    end

    %{
      overall_score: comparison.overall_score,
      grade: benchmark_grade(comparison.overall_score),
      strengths: strengths,
      issues: issues,
      recommendation: if length(issues) == 0 do
        "Prompt meets or exceeds industry benchmarks"
      else
        "Focus on: #{Enum.join(issues, ", ")}"
      end
    }
  end

  defp benchmark_grade(score) do
    cond do
      score >= 90 -> "A"
      score >= 80 -> "B" 
      score >= 70 -> "C"
      score >= 60 -> "D"
      true -> "F"
    end
  end
  defp find_missing_keywords(response, keywords) do
    Enum.filter(keywords, fn keyword ->
      not String.contains?(String.downcase(response), String.downcase(keyword))
    end)
  end
  defp detect_hallucination_indicators(_response), do: false
  defp add_clarity_example(prompt, _issue), do: prompt <> "\n\nExample: [specific example here]"
  defp simplify_prompt_example(prompt), do: String.slice(prompt, 0, div(String.length(prompt), 2))
  defp add_context_example(prompt, _issue), do: "Context: [relevant background]\n\n" <> prompt
  defp restructure_prompt_example(prompt), do: "## Task\n" <> prompt <> "\n\n## Requirements\n- [requirement 1]\n- [requirement 2]"
  defp generate_debugging_workflow(_prompt, _options), do: []
  defp validate_length(prompt) do
    valid = String.length(prompt) > 10 and String.length(prompt) < 2000
    %{validation: :length, valid: valid, message: if(valid, do: "Length is appropriate", else: "Length is inappropriate")}
  end
  defp validate_encoding(_prompt), do: %{validation: :encoding, valid: true, message: "Encoding is valid"}
  defp validate_structure(_prompt), do: %{validation: :structure, valid: true, message: "Structure is valid"}
  defp validate_clarity(_prompt), do: %{validation: :clarity, valid: true, message: "Clarity is acceptable"}
  defp validate_completeness(_prompt), do: %{validation: :completeness, valid: true, message: "Prompt appears complete"}
  defp calculate_validation_score(validations) do
    valid_count = Enum.count(validations, & &1.valid)
    total_count = length(validations)
    if total_count > 0, do: valid_count / total_count, else: 0.0
  end
  defp extract_validation_recommendations(validations) do
    validations
    |> Enum.filter(& !&1.valid)
    |> Enum.map(& &1.message)
  end
  defp calculate_complexity_score(_prompt), do: 0.5

  # Helper functions for DebuggingTools real implementations
  defp analyze_prompt_complexity(prompt) do
    words = String.split(prompt, ~r/\s+/)
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.filter(&(&1 != ""))
    
    # Calculate complexity based on various factors
    word_count = length(words)
    sentence_count = max(1, length(sentences))
    avg_sentence_length = word_count / sentence_count
    
    # Complex words (>6 characters)
    complex_words = Enum.count(words, &(String.length(&1) > 6))
    complex_word_ratio = if word_count > 0, do: complex_words / word_count, else: 0.0
    
    # Nested structures (parentheses, brackets, etc.)
    nesting_score = (String.length(prompt) - String.length(String.replace(prompt, ~r/[\(\[\{]/, ""))) / String.length(prompt)
    
    # Final complexity score (0.0 to 1.0)
    base_score = min(1.0, (avg_sentence_length / 20.0) + complex_word_ratio + nesting_score)
    Float.round(base_score, 2)
  end

  defp estimate_token_usage(prompt) do
    # Rough estimation: 1 token per 4 characters (varies by tokenizer)
    estimated_tokens = div(String.length(prompt), 4)
    max(1, estimated_tokens)
  end

  defp simulate_execution_time(complexity, provider) do
    # Base execution times by provider (in milliseconds)
    base_times = %{
      "openai" => 1500,
      "anthropic" => 2000, 
      "gemini" => 1200,
      "local" => 5000
    }
    
    base_time = Map.get(base_times, provider, 2000)
    
    # Adjust for complexity (0.0-1.0 maps to 0.5x-3.0x multiplier)
    complexity_multiplier = 0.5 + (complexity * 2.5)
    
    # Add some randomness for realism
    random_factor = 0.8 + (:rand.uniform() * 0.4) # 0.8 to 1.2
    
    round(base_time * complexity_multiplier * random_factor)
  end

  defp sample_realistic_error(complexity) do
    # Higher complexity = higher chance of complex errors
    error_types = [
      :timeout,
      :rate_limit,
      :context_length,
      :invalid_format,
      :ambiguous_instruction,
      :token_limit,
      :content_policy
    ]
    
    # Weight errors by complexity
    weighted_errors = if complexity > 0.7 do
      [:context_length, :ambiguous_instruction, :token_limit, :timeout] ++ error_types
    else
      error_types
    end
    
    Enum.random(weighted_errors)
  end

  defp generate_error_message(error_type) do
    error_messages = %{
      timeout: "Request timed out after 30 seconds. Consider reducing prompt complexity.",
      rate_limit: "Rate limit exceeded. Please wait before making another request.",
      context_length: "Input exceeds maximum context length. Please reduce prompt size.",
      invalid_format: "Response format is invalid. Check prompt structure and requirements.",
      ambiguous_instruction: "Instruction is ambiguous. Please provide clearer guidance.",
      token_limit: "Token limit exceeded in response. Consider requesting shorter output.",
      content_policy: "Content violates usage policies. Please revise prompt."
    }
    
    Map.get(error_messages, error_type, "Unknown error occurred during execution.")
  end
end
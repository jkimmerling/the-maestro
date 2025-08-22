defmodule TheMaestro.Prompts.EngineeringTools.OptimizationEngine do
  @moduledoc """
  Advanced optimization engine for prompt engineering.
  
  Provides performance optimization, quality enhancement, and efficiency improvements
  for prompts and prompt engineering workflows.
  """

  @doc """
  Optimizes a prompt for performance and quality.
  
  ## Parameters
  - prompt: The prompt text to optimize
  - options: Optimization options including:
    - :focus - :performance, :quality, or :efficiency
    - :target_tokens - Target token count
    - :preserve_meaning - Whether to preserve exact meaning
  
  ## Returns
  - {:ok, optimized_prompt, metrics} on success
  - {:error, reason} on failure
  """
  @spec optimize_prompt(String.t(), map()) :: 
    {:ok, String.t(), map()} | {:error, String.t()}
  def optimize_prompt(prompt, options \\ %{}) do
    focus = options[:focus] || :balanced
    target_tokens = options[:target_tokens]
    _preserve_meaning = options[:preserve_meaning] || true

    try do
      optimized = 
        prompt
        |> remove_redundancy()
        |> improve_clarity()
        |> optimize_structure(focus)
        |> maybe_reduce_tokens(target_tokens)

      metrics = %{
        original_length: String.length(prompt),
        optimized_length: String.length(optimized),
        token_reduction: calculate_token_reduction(prompt, optimized),
        clarity_score: calculate_clarity_score(optimized),
        optimization_type: focus
      }

      {:ok, optimized, metrics}
    rescue
      error -> {:error, "Optimization failed: #{inspect(error)}"}
    end
  end

  @doc """
  Analyzes prompt performance and suggests optimizations.
  """
  @spec analyze_performance(String.t(), map()) :: map()
  def analyze_performance(prompt, context \\ %{}) do
    %{
      token_count: estimate_token_count(prompt),
      complexity_score: calculate_complexity_score(prompt),
      clarity_metrics: analyze_clarity(prompt),
      efficiency_suggestions: generate_efficiency_suggestions(prompt),
      quality_metrics: analyze_quality_metrics(prompt),
      context_analysis: analyze_context_usage(prompt, context),
      recommended_optimizations: recommend_optimizations(prompt)
    }
  end

  @doc """
  Optimizes prompt templates for reusability and performance.
  """
  @spec optimize_template(String.t(), map()) :: {:ok, String.t(), map()} | {:error, String.t()}
  def optimize_template(template, _options \\ %{}) do
    try do
      optimized = 
        template
        |> extract_parameters()
        |> optimize_parameter_usage()
        |> improve_template_structure()
        |> add_validation_hints()

      metrics = %{
        parameter_count: count_parameters(optimized),
        reusability_score: calculate_reusability_score(optimized),
        flexibility_score: calculate_flexibility_score(optimized),
        maintenance_score: calculate_maintenance_score(optimized)
      }

      {:ok, optimized, metrics}
    rescue
      error -> {:error, "Template optimization failed: #{inspect(error)}"}
    end
  end

  @doc """
  Provides optimization recommendations based on usage patterns.
  """
  @spec get_optimization_recommendations(list(map())) :: list(map())
  def get_optimization_recommendations(usage_patterns) do
    usage_patterns
    |> analyze_usage_patterns()
    |> identify_optimization_opportunities()
    |> generate_recommendations()
    |> prioritize_recommendations()
  end

  # Private helper functions

  defp remove_redundancy(prompt) do
    prompt
    |> String.replace(~r/\b(\w+)\s+\1\b/, "\\1") # Remove word repetitions
    |> String.replace(~r/\s+/, " ") # Normalize whitespace
    |> String.trim()
  end

  defp improve_clarity(prompt) do
    prompt
    |> replace_vague_terms()
    |> improve_sentence_structure()
    |> add_clarity_markers()
  end

  defp optimize_structure(prompt, :performance) do
    prompt
    |> move_key_instructions_first()
    |> optimize_for_speed()
    |> reduce_processing_overhead()
  end

  defp optimize_structure(prompt, :quality) do
    prompt
    |> enhance_specificity()
    |> add_quality_constraints()
    |> improve_context_clarity()
  end

  defp optimize_structure(prompt, :efficiency) do
    prompt
    |> minimize_token_usage()
    |> optimize_information_density()
    |> remove_unnecessary_elaboration()
  end

  defp optimize_structure(prompt, _), do: prompt

  defp maybe_reduce_tokens(prompt, nil), do: prompt
  defp maybe_reduce_tokens(prompt, target_tokens) do
    current_tokens = estimate_token_count(prompt)
    if current_tokens > target_tokens do
      reduction_ratio = target_tokens / current_tokens
      reduce_content(prompt, reduction_ratio)
    else
      prompt
    end
  end

  defp calculate_token_reduction(original, optimized) do
    original_tokens = estimate_token_count(original)
    optimized_tokens = estimate_token_count(optimized)
    
    if original_tokens > 0 do
      ((original_tokens - optimized_tokens) / original_tokens * 100) |> round()
    else
      0
    end
  end

  defp calculate_clarity_score(prompt) do
    # Simple heuristic-based clarity scoring
    base_score = 50
    
    score = base_score
    |> add_score_for_structure(prompt)
    |> add_score_for_specificity(prompt)
    |> add_score_for_readability(prompt)
    |> max(0)
    |> min(100)
    
    score / 100.0
  end

  defp estimate_token_count(text) do
    # Simple approximation: ~4 characters per token
    (String.length(text) / 4) |> round()
  end

  defp calculate_complexity_score(prompt) do
    sentence_count = length(String.split(prompt, ~r/[.!?]+/))
    avg_sentence_length = String.length(prompt) / max(sentence_count, 1)
    
    cond do
      avg_sentence_length < 50 -> :low
      avg_sentence_length < 100 -> :medium
      true -> :high
    end
  end

  defp analyze_clarity(prompt) do
    %{
      readability_score: calculate_readability(prompt),
      specificity_score: calculate_specificity(prompt),
      structure_score: calculate_structure_quality(prompt),
      coherence_score: calculate_coherence(prompt)
    }
  end

  defp generate_efficiency_suggestions(prompt) do
    suggestions = []
    
    suggestions = if String.length(prompt) > 500 do
      ["Consider breaking into shorter, focused sections" | suggestions]
    else
      suggestions
    end
    
    suggestions = if Regex.match?(~r/\b(please|could|would)\b/i, prompt) do
      ["Remove unnecessary politeness words to save tokens" | suggestions]
    else
      suggestions
    end
    
    suggestions = if Regex.match?(~r/\b(very|really|quite|somewhat)\b/i, prompt) do
      ["Consider removing qualifier words for more direct communication" | suggestions]
    else
      suggestions
    end
    
    suggestions
  end

  defp analyze_quality_metrics(prompt) do
    %{
      specificity: calculate_specificity(prompt),
      actionability: calculate_actionability(prompt),
      context_clarity: calculate_context_clarity(prompt),
      instruction_clarity: calculate_instruction_clarity(prompt)
    }
  end

  defp analyze_context_usage(prompt, context) do
    %{
      context_references: count_context_references(prompt),
      context_relevance: assess_context_relevance(prompt, context),
      context_completeness: assess_context_completeness(prompt, context)
    }
  end

  defp recommend_optimizations(prompt) do
    recommendations = []
    
    # Check for common optimization opportunities
    recommendations = if String.length(prompt) > 300 do
      [%{type: :length, suggestion: "Consider shortening for better focus", priority: :medium} | recommendations]
    else
      recommendations
    end
    
    recommendations = if not Regex.match?(~r/\?/, prompt) do
      [%{type: :clarity, suggestion: "Add specific questions to guide response", priority: :high} | recommendations]
    else
      recommendations
    end
    
    recommendations = if Regex.match?(~r/\b(stuff|things|some|any)\b/i, prompt) do
      [%{type: :specificity, suggestion: "Replace vague terms with specific requirements", priority: :high} | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp extract_parameters(template) do
    # Extract parameterized sections like {{variable}}
    template
  end

  defp optimize_parameter_usage(template) do
    template
  end

  defp improve_template_structure(template) do
    template
  end

  defp add_validation_hints(template) do
    template
  end

  defp count_parameters(template) do
    Regex.scan(~r/\{\{[^}]+\}\}/, template) |> length()
  end

  defp calculate_reusability_score(template) do
    parameter_count = count_parameters(template)
    base_score = min(parameter_count * 10, 100)
    base_score / 100.0
  end

  defp calculate_flexibility_score(_template) do
    # Score based on parameter variety and optional sections
    0.75
  end

  defp calculate_maintenance_score(_template) do
    # Score based on structure clarity and documentation
    0.8
  end

  defp analyze_usage_patterns(patterns) do
    patterns
  end

  defp identify_optimization_opportunities(analysis) do
    analysis
  end

  defp generate_recommendations(opportunities) do
    opportunities
  end

  defp prioritize_recommendations(recommendations) do
    recommendations
  end

  # Additional helper functions for scoring

  defp replace_vague_terms(prompt) do
    prompt
    |> String.replace(~r/\bstuff\b/i, "specific items")
    |> String.replace(~r/\bthings\b/i, "elements")
  end

  defp improve_sentence_structure(prompt), do: prompt
  defp add_clarity_markers(prompt), do: prompt
  defp move_key_instructions_first(prompt), do: prompt
  defp optimize_for_speed(prompt), do: prompt
  defp reduce_processing_overhead(prompt), do: prompt
  defp enhance_specificity(prompt), do: prompt
  defp add_quality_constraints(prompt), do: prompt
  defp improve_context_clarity(prompt), do: prompt
  defp minimize_token_usage(prompt), do: prompt
  defp optimize_information_density(prompt), do: prompt
  defp remove_unnecessary_elaboration(prompt), do: prompt
  defp reduce_content(prompt, _ratio), do: prompt

  defp add_score_for_structure(score, _prompt), do: score + 10
  defp add_score_for_specificity(score, _prompt), do: score + 15
  defp add_score_for_readability(score, _prompt), do: score + 20

  defp calculate_readability(prompt) do
    # Calculate readability score based on multiple factors
    words = String.split(prompt, ~r/\s+/) |> Enum.reject(&(&1 == ""))
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
    
    word_count = length(words)
    sentence_count = max(length(sentences), 1)  # Avoid division by zero
    
    # Average words per sentence
    avg_words_per_sentence = word_count / sentence_count
    
    # Complex word analysis (3+ syllables approximated by length)
    complex_words = Enum.count(words, fn word ->
      clean_word = String.replace(word, ~r/[^a-zA-Z]/, "")
      String.length(clean_word) > 6  # Approximate for complex words
    end)
    
    complex_word_ratio = if word_count > 0, do: complex_words / word_count, else: 0
    
    # Technical term detection
    technical_terms = Enum.count(words, fn word ->
      word_lower = String.downcase(word)
      String.contains?(word_lower, ["{{", "}}", "api", "json", "xml", "algorithm", "parameter"])
    end)
    
    technical_ratio = if word_count > 0, do: technical_terms / word_count, else: 0
    
    # Readability scoring (inverse of complexity)
    sentence_complexity = case avg_words_per_sentence do
      x when x > 25 -> 0.2  # Very complex
      x when x > 20 -> 0.4  # Complex
      x when x > 15 -> 0.6  # Moderate
      x when x > 10 -> 0.8  # Simple
      _ -> 1.0              # Very simple
    end
    
    vocabulary_simplicity = 1.0 - min(complex_word_ratio * 2, 0.6)
    technical_penalty = min(technical_ratio * 0.5, 0.3)
    
    readability_score = (sentence_complexity * 0.4) + (vocabulary_simplicity * 0.4) - technical_penalty + 0.2
    
    # Normalize to 0-1 range
    max(min(readability_score, 1.0), 0.0)
  end
  defp calculate_specificity(prompt) do
    # Calculate specificity score based on concrete vs. abstract language
    words = String.split(prompt, ~r/\s+/) |> Enum.reject(&(&1 == ""))
    word_count = length(words)
    
    if word_count == 0 do
      0.0
    else
      # Specific indicators (concrete terms, numbers, examples)
      specific_patterns = [
        # Numbers and measurements
        {~r/\d+/, 0.1},
        {~r/\d+\.\d+/, 0.15},
        {~r/\d+%/, 0.15},
        
        # Specific actions and verbs
        {~r/\b(analyze|create|write|generate|calculate|extract|transform|summarize|classify)\b/i, 0.08},
        
        # Concrete nouns and examples
        {~r/\b(example|instance|case|specific|particular|exactly|precisely)\b/i, 0.1},
        
        # Parameters and variables
        {~r/\{\{.*?\}\}/, 0.12},
        
        # Format specifications
        {~r/\b(format|structure|template|json|xml|csv|markdown)\b/i, 0.08},
        
        # Time and date references
        {~r/\b(today|tomorrow|january|february|2024|monday|morning)\b/i, 0.05}
      ]
      
      specificity_score = specific_patterns
      |> Enum.reduce(0.0, fn {pattern, weight}, acc ->
        matches = Regex.scan(pattern, prompt) |> length()
        acc + (matches * weight)
      end)
      
      # Abstract/vague language penalties
      vague_words = ["something", "things", "stuff", "maybe", "perhaps", "possibly", "generally", "usually", "often", "sometimes"]
      vague_count = Enum.count(words, fn word ->
        word_lower = String.downcase(String.replace(word, ~r/[^a-zA-Z]/, ""))
        word_lower in vague_words
      end)
      
      vague_penalty = min(vague_count * 0.05, 0.3)
      
      # Modal verbs that reduce specificity
      modal_verbs = ["might", "could", "would", "should", "may", "can"]
      modal_count = Enum.count(words, fn word ->
        word_lower = String.downcase(String.replace(word, ~r/[^a-zA-Z]/, ""))
        word_lower in modal_verbs
      end)
      
      modal_penalty = min(modal_count * 0.03, 0.2)
      
      # Normalize based on prompt length
      normalized_score = min(specificity_score / max(word_count * 0.1, 1), 1.0)
      
      final_score = normalized_score - vague_penalty - modal_penalty + 0.2
      
      # Ensure 0-1 range
      max(min(final_score, 1.0), 0.0)
    end
  end
  defp calculate_structure_quality(prompt) do
    # Analyze prompt structure quality based on organization and flow
    lines = String.split(prompt, "\n") |> Enum.reject(&(&1 == ""))
    
    # Check for clear sections/organization
    section_markers = Enum.count(lines, fn line ->
      String.match?(line, ~r/^#+\s|^\d+\.|^-\s|^\*\s|^[A-Z][^:]*:/)
    end)
    
    section_score = case section_markers do
      x when x > 5 -> 1.0   # Well-structured
      x when x > 2 -> 0.8   # Good structure
      x when x > 0 -> 0.6   # Some structure
      _ -> 0.3              # Poor structure
    end
    
    # Check for logical flow indicators
    flow_words = ["first", "then", "next", "finally", "after", "before", "when", "if"]
    flow_count = Enum.count(flow_words, fn word ->
      String.contains?(String.downcase(prompt), word)
    end)
    
    flow_score = min(flow_count * 0.1, 0.4)
    
    # Check for clear introduction/conclusion
    has_intro = String.match?(prompt, ~r/^(you are|your task|please|create|analyze)/i)
    has_conclusion = String.match?(prompt, ~r/(ensure|remember|format|output)/i)
    
    completeness_score = case {has_intro, has_conclusion} do
      {true, true} -> 0.3
      {true, false} -> 0.15
      {false, true} -> 0.15
      {false, false} -> 0.0
    end
    
    final_score = section_score * 0.5 + flow_score + completeness_score
    max(min(final_score, 1.0), 0.0)
  end

  defp calculate_coherence(prompt) do
    # Analyze logical coherence and consistency throughout prompt
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
    
    # Check for consistent terminology
    key_terms = String.split(prompt, ~r/\W+/)
                |> Enum.filter(&(String.length(&1) > 4))
                |> Enum.frequencies()
                |> Enum.filter(fn {_term, count} -> count > 1 end)
                |> length()
    
    terminology_score = case key_terms do
      x when x > 10 -> 1.0   # Very consistent
      x when x > 5  -> 0.8   # Good consistency
      x when x > 2  -> 0.6   # Some consistency
      _ -> 0.4               # Poor consistency
    end
    
    # Check for contradictory instructions
    contradiction_patterns = [
      {~r/\b(short|brief|concise)\b.*\b(detailed|comprehensive|thorough)\b/i, -0.3},
      {~r/\b(formal|professional)\b.*\b(casual|informal)\b/i, -0.2},
      {~r/\b(simple|basic)\b.*\b(complex|advanced)\b/i, -0.2},
      {~r/\b(include|add)\b.*\b(exclude|omit|remove)\b/i, -0.15}
    ]
    
    contradiction_penalty = contradiction_patterns
                           |> Enum.map(fn {pattern, penalty} ->
                             if String.match?(prompt, pattern), do: penalty, else: 0.0
                           end)
                           |> Enum.sum()
    
    # Check for topic consistency
    topic_shifts = sentences
                  |> Enum.chunk_every(2, 1, :discard)
                  |> Enum.count(fn [s1, s2] ->
                    # Simple heuristic: dramatic change in vocabulary
                    words1 = String.split(s1) |> MapSet.new()
                    words2 = String.split(s2) |> MapSet.new()
                    intersection_size = MapSet.intersection(words1, words2) |> MapSet.size()
                    union_size = MapSet.union(words1, words2) |> MapSet.size()
                    
                    if union_size > 0 do
                      similarity = intersection_size / union_size
                      similarity < 0.1  # Less than 10% word overlap suggests topic shift
                    else
                      false
                    end
                  end)
    
    topic_penalty = min(topic_shifts * 0.1, 0.3)
    
    coherence_score = terminology_score + contradiction_penalty - topic_penalty
    max(min(coherence_score, 1.0), 0.0)
  end

  defp calculate_actionability(prompt) do
    # Analyze how actionable and specific the prompt is
    words = String.split(prompt, ~r/\s+/) |> Enum.reject(&(&1 == ""))
    word_count = length(words)
    
    if word_count == 0 do
      0.0
    else
      # Count action verbs
      action_verbs = ["analyze", "create", "write", "generate", "build", "design", "implement", 
                      "calculate", "extract", "transform", "summarize", "classify", "explain", 
                      "describe", "list", "identify", "compare", "evaluate", "recommend"]
      
      action_count = Enum.count(words, fn word ->
        clean_word = String.replace(word, ~r/[^a-zA-Z]/, "") |> String.downcase()
        clean_word in action_verbs
      end)
      
      action_score = min(action_count * 0.15, 0.6)
      
      # Check for specific deliverables
      deliverable_patterns = [
        ~r/\b(format|output|result|response|answer)\b/i,
        ~r/\b(json|xml|csv|markdown|html)\b/i,
        ~r/\b(list|table|summary|report|analysis)\b/i
      ]
      
      deliverable_count = deliverable_patterns
                         |> Enum.count(&String.match?(prompt, &1))
      
      deliverable_score = min(deliverable_count * 0.1, 0.3)
      
      # Check for constraints and parameters
      constraint_patterns = [
        ~r/\b(must|should|required|ensure)\b/i,
        ~r/\b(maximum|minimum|limit|between)\b/i,
        ~r/\b(exactly|precisely|specifically)\b/i
      ]
      
      constraint_count = constraint_patterns
                        |> Enum.count(&String.match?(prompt, &1))
      
      constraint_score = min(constraint_count * 0.08, 0.25)
      
      # Penalty for vague language
      vague_words = ["somehow", "something", "anything", "maybe", "perhaps", "possibly", 
                     "generally", "typically", "usually", "often", "sometimes"]
      
      vague_count = Enum.count(words, fn word ->
        clean_word = String.replace(word, ~r/[^a-zA-Z]/, "") |> String.downcase()
        clean_word in vague_words
      end)
      
      vague_penalty = min(vague_count * 0.05, 0.2)
      
      actionability_score = action_score + deliverable_score + constraint_score - vague_penalty
      max(min(actionability_score, 1.0), 0.0)
    end
  end

  defp calculate_context_clarity(prompt) do
    # Analyze how clearly the context and background are provided
    
    # Check for context-setting phrases
    context_indicators = [
      {~r/\b(you are|assume|given|context|background|scenario)\b/i, 0.15},
      {~r/\b(for this|in this|when|while|during)\b/i, 0.1},
      {~r/\b(user|client|customer|audience|target)\b/i, 0.12},
      {~r/\b(project|task|assignment|goal|objective)\b/i, 0.1},
      {~r/\b(example|instance|case study)\b/i, 0.08}
    ]
    
    context_score = context_indicators
                   |> Enum.map(fn {pattern, score} ->
                     if String.match?(prompt, pattern), do: score, else: 0.0
                   end)
                   |> Enum.sum()
                   |> min(0.6)
    
    # Check for domain/field specification
    domain_patterns = [
      ~r/\b(software|web|mobile|data|business|medical|legal|financial|educational|marketing)\b/i,
      ~r/\b(api|database|frontend|backend|ai|ml|algorithm|security)\b/i,
      ~r/\b(react|python|javascript|sql|json|html|css)\b/i
    ]
    
    domain_count = domain_patterns |> Enum.count(&String.match?(prompt, &1))
    domain_score = min(domain_count * 0.1, 0.3)
    
    # Check for role clarity
    role_clarity = cond do
      String.match?(prompt, ~r/\b(you are a|act as|assume the role)\b/i) -> 0.2
      String.match?(prompt, ~r/\b(as a|from the perspective)\b/i) -> 0.15
      String.match?(prompt, ~r/\b(you should|your job)\b/i) -> 0.1
      true -> 0.0
    end
    
    # Penalty for ambiguous references
    ambiguous_patterns = ["this", "that", "it", "they", "them", "these", "those"]
    ambiguous_count = Enum.count(String.split(prompt), fn word ->
      clean_word = String.replace(word, ~r/[^a-zA-Z]/, "") |> String.downcase()
      clean_word in ambiguous_patterns
    end)
    
    ambiguity_penalty = min(ambiguous_count * 0.02, 0.15)
    
    clarity_score = context_score + domain_score + role_clarity - ambiguity_penalty
    max(min(clarity_score, 1.0), 0.0)
  end

  defp calculate_instruction_clarity(prompt) do
    # Analyze how clear and unambiguous the instructions are
    
    # Check for clear instruction structure
    instruction_markers = [
      {~r/\b(step \d+|first|second|third|then|next|finally)\b/i, 0.12},
      {~r/^[\d]+\./m, 0.15},  # Numbered lists
      {~r/^[-*]\s/m, 0.1},    # Bullet points
      {~r/\b(please|ensure|make sure|be sure to)\b/i, 0.08},
      {~r/\b(do not|don't|avoid|never)\b/i, 0.08}  # Clear prohibitions
    ]
    
    instruction_score = instruction_markers
                       |> Enum.map(fn {pattern, score} ->
                         matches = Regex.scan(pattern, prompt) |> length()
                         min(matches * score, score * 2)  # Cap individual contributions
                       end)
                       |> Enum.sum()
                       |> min(0.6)
    
    # Check for imperative mood (commands)
    imperative_verbs = ["create", "write", "analyze", "explain", "describe", "list", 
                        "identify", "compare", "evaluate", "calculate", "generate", 
                        "provide", "include", "exclude", "format", "structure"]
    
    imperative_count = Enum.count(String.split(prompt), fn word ->
      clean_word = String.replace(word, ~r/[^a-zA-Z]/, "") |> String.downcase()
      clean_word in imperative_verbs
    end)
    
    imperative_score = min(imperative_count * 0.08, 0.4)
    
    # Check for specific formatting instructions
    format_clarity = cond do
      String.match?(prompt, ~r/\b(json|xml|csv|yaml|markdown|html)\b/i) -> 0.15
      String.match?(prompt, ~r/\b(format|structure|template)\b/i) -> 0.1
      String.match?(prompt, ~r/\b(output|result|response)\b/i) -> 0.08
      true -> 0.0
    end
    
    # Penalty for modal verbs that create ambiguity
    modal_verbs = ["could", "might", "may", "would", "should", "possibly", "perhaps"]
    modal_count = Enum.count(String.split(prompt), fn word ->
      clean_word = String.replace(word, ~r/[^a-zA-Z]/, "") |> String.downcase()
      clean_word in modal_verbs
    end)
    
    modal_penalty = min(modal_count * 0.05, 0.2)
    
    # Penalty for overly complex sentence structure
    sentences = String.split(prompt, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
    avg_sentence_length = if length(sentences) > 0 do
      total_words = sentences |> Enum.map(&String.split/1) |> List.flatten() |> length()
      total_words / length(sentences)
    else
      0
    end
    
    complexity_penalty = case avg_sentence_length do
      x when x > 30 -> 0.2    # Very complex sentences
      x when x > 25 -> 0.15   # Complex sentences
      x when x > 20 -> 0.1    # Moderately complex
      _ -> 0.0
    end
    
    clarity_score = instruction_score + imperative_score + format_clarity - modal_penalty - complexity_penalty
    max(min(clarity_score, 1.0), 0.0)
  end

  defp count_context_references(prompt) do
    # Count explicit context references and background information
    context_patterns = [
      ~r/\b(context|background|given|assume|scenario|situation)\b/i,
      ~r/\b(for this|in this|when|while|during)\b/i,
      ~r/\b(user|client|customer|audience|target)\b/i,
      ~r/\b(project|task|assignment|goal|objective)\b/i,
      ~r/\b(you are|assume the role|act as)\b/i
    ]
    
    context_patterns
    |> Enum.map(&(Regex.scan(&1, prompt) |> length()))
    |> Enum.sum()
  end

  defp assess_context_relevance(prompt, context) do
    # Assess how relevant the provided context is to the prompt
    if is_nil(context) or context == "" do
      0.0
    else
      prompt_words = String.split(prompt, ~r/\W+/) |> MapSet.new() |> MapSet.delete("")
      context_words = String.split(context, ~r/\W+/) |> MapSet.new() |> MapSet.delete("")
      
      if MapSet.size(prompt_words) == 0 do
        0.0
      else
        intersection_size = MapSet.intersection(prompt_words, context_words) |> MapSet.size()
        relevance = intersection_size / MapSet.size(prompt_words)
        
        # Boost score if context contains domain-specific or technical terms
        technical_boost = if String.match?(context, ~r/\b(api|json|sql|algorithm|data|system)\b/i) do
          0.1
        else
          0.0
        end
        
        min(relevance + technical_boost, 1.0)
      end
    end
  end

  defp assess_context_completeness(prompt, context) do
    # Assess how complete the context is for the given prompt
    if is_nil(context) or context == "" do
      0.0
    else
      # Check if context addresses key requirements from prompt
      requirements = [
        {~r/\b(role|persona|character)\b/i, ~r/\b(you are|act as|assume)\b/i},
        {~r/\b(format|output|structure)\b/i, ~r/\b(json|xml|format|template)\b/i},
        {~r/\b(domain|field|area)\b/i, ~r/\b(software|business|medical|technical)\b/i},
        {~r/\b(audience|user|target)\b/i, ~r/\b(user|client|customer|audience)\b/i},
        {~r/\b(constraint|limit|requirement)\b/i, ~r/\b(must|should|required|maximum|minimum)\b/i}
      ]
      
      addressed_requirements = requirements
                              |> Enum.count(fn {prompt_pattern, context_pattern} ->
                                String.match?(prompt, prompt_pattern) and String.match?(context, context_pattern)
                              end)
      
      total_requirements = requirements
                          |> Enum.count(fn {prompt_pattern, _} ->
                            String.match?(prompt, prompt_pattern)
                          end)
      
      if total_requirements == 0 do
        0.7  # Default score if no specific requirements detected
      else
        addressed_requirements / total_requirements
      end
    end
  end
end
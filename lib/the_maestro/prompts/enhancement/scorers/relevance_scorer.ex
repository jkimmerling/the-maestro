defmodule TheMaestro.Prompts.Enhancement.Scorers.RelevanceScorer do
  @moduledoc """
  Intelligent context relevance scoring and prioritization system.

  This module evaluates context items for their relevance to the user's prompt
  and intent, providing prioritized context for integration.
  """

  alias TheMaestro.Prompts.Enhancement.Structs.{
    ContextAnalysis,
    ContextItem
  }

  @base_relevance_scores %{
    environmental: 0.3,
    project_structure: 0.7,
    code_analysis: 0.8,
    tool_availability: 0.4,
    mcp_integration: 0.4,
    session_history: 0.5,
    user_preferences: 0.3,
    documentation: 0.6,
    security_context: 0.5,
    performance_context: 0.4
  }

  @doc """
  Scores context relevance and returns prioritized context items.

  ## Parameters

  - `context_data` - Map of context data organized by source
  - `prompt_analysis` - ContextAnalysis struct with prompt analysis results

  ## Returns

  List of ContextItem structs sorted by relevance score (highest first).
  """
  @spec score_context_relevance(map(), ContextAnalysis.t()) :: [ContextItem.t()]
  def score_context_relevance(context_data, %ContextAnalysis{} = prompt_analysis) do
    if is_map(context_data) do
      context_data
      |> Enum.map(&score_context_item(&1, prompt_analysis))
      |> Enum.filter(&meets_relevance_threshold?/1)
      |> Enum.sort_by(& &1.relevance_score, :desc)
    else
      []
    end
  end

  @doc """
  Scores a single context item against the prompt analysis.

  ## Parameters

  - `context_item` - Tuple of {context_type, context_value}
  - `prompt_analysis` - ContextAnalysis struct

  ## Returns

  A ContextItem struct with relevance score and contributing factors.
  """
  @spec score_context_item({atom(), any()}, ContextAnalysis.t()) :: ContextItem.t()
  def score_context_item({context_type, context_value}, %ContextAnalysis{} = prompt_analysis) do
    base_score = get_base_relevance_score(context_type)

    intent_alignment = calculate_intent_alignment(context_type, prompt_analysis.user_intent)
    entity_overlap = calculate_entity_overlap(context_value, prompt_analysis.mentioned_entities)
    domain_relevance = calculate_domain_relevance(context_type, prompt_analysis.domain_indicators)
    freshness_factor = calculate_freshness_factor(context_value)
    complexity_adjustment = adjust_for_complexity(context_type, prompt_analysis.complexity_level)
    urgency_adjustment = adjust_for_urgency(context_type, prompt_analysis.urgency_level)

    # Calculate final relevance score
    relevance_score =
      base_score *
        (1 +
           intent_alignment +
           entity_overlap +
           domain_relevance +
           freshness_factor +
           complexity_adjustment +
           urgency_adjustment)

    # Clamp score between 0.0 and 1.0
    final_score = max(0.0, min(relevance_score, 1.0))

    %ContextItem{
      type: context_type,
      value: context_value,
      relevance_score: final_score,
      contributing_factors: %{
        base_score: base_score,
        intent_alignment: intent_alignment,
        entity_overlap: entity_overlap,
        domain_relevance: domain_relevance,
        freshness_factor: freshness_factor,
        complexity_adjustment: complexity_adjustment,
        urgency_adjustment: urgency_adjustment
      }
    }
  end

  @doc """
  Calculates a dynamic relevance threshold based on available context.

  ## Parameters

  - `context_budget` - Maximum number of context items to include
  - `available_context` - List of available context items

  ## Returns

  Float representing the dynamic threshold for inclusion.
  """
  @spec calculate_dynamic_threshold(integer(), [ContextItem.t()]) :: float()
  def calculate_dynamic_threshold(context_budget, available_context) do
    total_context_value =
      available_context
      |> Enum.map(& &1.relevance_score)
      |> Enum.sum()

    context_density = length(available_context) / max(context_budget, 1)

    base_threshold = 0.3
    density_adjustment = min(context_density * 0.1, 0.4)
    value_adjustment = min(total_context_value / 100, 0.2)

    base_threshold + density_adjustment + value_adjustment
  end

  # Private helper functions

  defp get_base_relevance_score(context_type) do
    Map.get(@base_relevance_scores, context_type, 0.3)
  end

  defp calculate_intent_alignment(context_type, user_intent) do
    intent_context_alignment = %{
      bug_fix: %{
        code_analysis: 0.4,
        project_structure: 0.3,
        tool_availability: 0.2
      },
      feature_implementation: %{
        code_analysis: 0.3,
        project_structure: 0.4,
        documentation: 0.3
      },
      refactoring: %{
        code_analysis: 0.4,
        project_structure: 0.2,
        performance_context: 0.2
      },
      optimization: %{
        performance_context: 0.4,
        code_analysis: 0.3,
        system_resources: 0.2
      },
      read_file: %{
        environmental: 0.3,
        project_structure: 0.4,
        security_context: 0.2
      },
      write_file: %{
        environmental: 0.3,
        project_structure: 0.3,
        security_context: 0.3
      },
      information_seeking: %{
        documentation: 0.4,
        session_history: 0.2,
        project_structure: 0.2
      },
      deployment: %{
        project_structure: 0.3,
        environmental: 0.3,
        security_context: 0.2
      },
      testing: %{
        code_analysis: 0.3,
        project_structure: 0.3,
        tool_availability: 0.2
      }
    }

    alignments = Map.get(intent_context_alignment, user_intent, %{})
    Map.get(alignments, context_type, 0.0)
  end

  defp calculate_entity_overlap(context_value, mentioned_entities) do
    if Enum.empty?(mentioned_entities) do
      0.0
    else
      context_string = stringify_context_value(context_value)

      overlap_count =
        Enum.count(mentioned_entities, fn entity ->
          String.contains?(String.downcase(context_string), String.downcase(entity))
        end)

      # Normalize by the number of entities mentioned
      overlap_ratio = overlap_count / length(mentioned_entities)

      # Scale to reasonable boost range
      min(overlap_ratio * 0.3, 0.3)
    end
  end

  defp calculate_domain_relevance(context_type, domain_indicators) do
    domain_context_relevance = %{
      software_development: [:code_analysis, :project_structure, :tool_availability],
      web_development: [:project_structure, :documentation, :performance_context],
      devops: [:environmental, :security_context, :performance_context],
      database: [:code_analysis, :project_structure, :performance_context],
      file_system: [:environmental, :project_structure, :security_context],
      monitoring: [:performance_context, :environmental, :tool_availability],
      deployment: [:environmental, :security_context, :project_structure]
    }

    relevant_domains =
      Enum.filter(domain_indicators, fn domain ->
        relevant_contexts = Map.get(domain_context_relevance, domain, [])
        context_type in relevant_contexts
      end)

    # Each relevant domain contributes 0.1 boost
    length(relevant_domains) * 0.1
  end

  defp calculate_freshness_factor(context_value) do
    case extract_timestamp(context_value) do
      nil ->
        0.0

      timestamp ->
        age_hours = DateTime.diff(DateTime.utc_now(), timestamp, :hour)

        cond do
          # Very fresh
          age_hours < 1 -> 0.2
          # Recent
          age_hours < 24 -> 0.1
          # This week
          age_hours < 168 -> 0.05
          # Older
          true -> 0.0
        end
    end
  end

  defp adjust_for_complexity(context_type, complexity_level) do
    complexity_adjustments = %{
      high: %{
        code_analysis: 0.2,
        project_structure: 0.15,
        documentation: 0.15,
        performance_context: 0.1
      },
      medium: %{
        code_analysis: 0.1,
        project_structure: 0.1,
        tool_availability: 0.05
      },
      low: %{
        environmental: 0.05,
        session_history: 0.05
      }
    }

    adjustments = Map.get(complexity_adjustments, complexity_level, %{})
    Map.get(adjustments, context_type, 0.0)
  end

  defp adjust_for_urgency(context_type, urgency_level) do
    urgency_adjustments = %{
      high: %{
        code_analysis: 0.1,
        environmental: 0.1,
        tool_availability: 0.05
      },
      medium: %{
        project_structure: 0.05,
        documentation: 0.05
      },
      low: %{
        session_history: 0.05,
        user_preferences: 0.05
      }
    }

    adjustments = Map.get(urgency_adjustments, urgency_level, %{})
    Map.get(adjustments, context_type, 0.0)
  end

  defp meets_relevance_threshold?(%ContextItem{relevance_score: score}) do
    # Minimum threshold for inclusion
    score >= 0.2
  end

  defp stringify_context_value(value) when is_binary(value), do: value

  # Handle specific context structs with special formatting
  defp stringify_context_value(%{__struct__: struct_name} = value) do
    case struct_name do
      TheMaestro.Prompts.Enhancement.Structs.EnvironmentalContext ->
        parts = []

        parts =
          if value.operating_system, do: ["OS: #{value.operating_system}" | parts], else: parts

        parts =
          if value.working_directory, do: ["Dir: #{value.working_directory}" | parts], else: parts

        parts = if value.project_type, do: ["Project: #{value.project_type}" | parts], else: parts
        Enum.reverse(parts) |> Enum.join(", ")

      TheMaestro.Prompts.Enhancement.Structs.ProjectStructureContext ->
        parts = []
        parts = if value.project_type, do: ["Type: #{value.project_type}" | parts], else: parts

        parts =
          if value.language_detection && length(value.language_detection) > 0,
            do: ["Languages: #{Enum.join(value.language_detection, ", ")}" | parts],
            else: parts

        parts =
          if value.framework_detection && length(value.framework_detection) > 0,
            do: ["Frameworks: #{Enum.join(value.framework_detection, ", ")}" | parts],
            else: parts

        Enum.reverse(parts) |> Enum.join(", ")

      TheMaestro.Prompts.Enhancement.Structs.CodeAnalysisContext ->
        parts = []

        parts =
          if value.relevant_files && length(value.relevant_files) > 0,
            do: ["Files: #{length(value.relevant_files)} found" | parts],
            else: parts

        parts =
          if value.dependencies && length(value.dependencies) > 0,
            do: ["Deps: #{length(value.dependencies)} found" | parts],
            else: parts

        Enum.reverse(parts) |> Enum.join(", ")

      _ ->
        # Fallback for other structs - just use inspect
        inspect(value)
    end
  end

  defp stringify_context_value(value) when is_map(value) do
    # Convert regular map values to searchable string (avoid DateTime enumeration)
    value
    |> Enum.filter(fn {_k, v} -> not match?(%DateTime{}, v) end)
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(" ")
  end

  defp stringify_context_value(value) when is_list(value) do
    value
    |> Enum.map(&inspect/1)
    |> Enum.join(" ")
  end

  defp stringify_context_value(value), do: inspect(value)

  defp extract_timestamp(%{timestamp: timestamp}) when is_struct(timestamp, DateTime) do
    timestamp
  end

  defp extract_timestamp(%{created_at: timestamp}) when is_struct(timestamp, DateTime) do
    timestamp
  end

  defp extract_timestamp(%{updated_at: timestamp}) when is_struct(timestamp, DateTime) do
    timestamp
  end

  defp extract_timestamp(_), do: nil
end

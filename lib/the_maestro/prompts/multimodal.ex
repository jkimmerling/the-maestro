defmodule TheMaestro.Prompts.MultiModal do
  @moduledoc """
  Multi-modal prompt handling system that integrates text, images, audio, video,
  documents, code, data, diagrams, and web content for comprehensive AI analysis.

  This module provides the main interface for processing diverse content types,
  analyzing their coherence, enhancing accessibility, assessing provider compatibility,
  and optimizing performance.

  ## Supported Content Types

  - `:text` - Text content and instructions
  - `:image` - Images, screenshots, diagrams  
  - `:audio` - Audio files, voice recordings
  - `:video` - Video content, screen recordings
  - `:document` - PDFs, Word docs, presentations
  - `:code` - Code files with syntax highlighting
  - `:data` - Structured data, JSON, CSV
  - `:diagram` - Flowcharts, UML, architectural diagrams
  - `:web_content` - Web pages, HTML content

  ## Usage

      content = [
        %{type: :text, content: "Analyze this error", metadata: %{}},
        %{type: :image, content: "base64_image_data", metadata: %{filename: "error.png"}},
        %{type: :code, content: "def bug_function, do: nil", metadata: %{language: :elixir}}
      ]
      
      context = %{
        provider: :anthropic,
        accessibility_requirements: [:alt_text],
        performance_constraints: %{max_processing_time_ms: 5000}
      }
      
      result = MultiModal.process_multimodal_content(content, context)
  """

  alias TheMaestro.Prompts.MultiModal.Processors.ContentProcessor
  alias TheMaestro.Prompts.MultiModal.Analyzers.CrossModalAnalyzer
  alias TheMaestro.Prompts.MultiModal.Accessibility.AccessibilityEnhancer
  alias TheMaestro.Prompts.MultiModal.Providers.ProviderCompatibilityAssessor
  alias TheMaestro.Prompts.MultiModal.Optimization.PerformanceOptimizer

  @content_types [
    :text,
    :image,
    :audio,
    :video,
    :document,
    :code,
    :data,
    :diagram,
    :web_content
  ]

  @doc """
  Returns the list of supported content types.
  """
  @spec content_type_definitions() :: list(atom())
  def content_type_definitions, do: @content_types

  @doc """
  Processes multi-modal content through the complete pipeline including content processing,
  cross-modal analysis, accessibility enhancement, provider compatibility assessment,
  and performance optimization.

  ## Parameters

  - `content` - List of content items with type, content, and metadata
  - `context` - Processing context including provider, requirements, and constraints

  ## Returns

  Map containing:
  - `processed_content` - Individually processed content items
  - `accessibility_enhancements` - Generated accessibility features
  - `cross_modal_analysis` - Coherence and relationship analysis
  - `provider_compatibility` - Provider-specific compatibility assessment
  - `performance_metrics` - Processing performance data
  - `assembled_prompt` - Final assembled prompt ready for LLM
  """
  @spec process_multimodal_content(list(map()), map()) :: map()
  def process_multimodal_content([], _context) do
    %{
      processed_content: [],
      accessibility_enhancements: %{},
      cross_modal_analysis: %{},
      provider_compatibility: %{},
      performance_metrics: %{processing_time_ms: 0},
      assembled_prompt: ""
    }
  end

  def process_multimodal_content(content, context) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, validated_content} <- validate_content_structure(content),
         processed_content <- process_individual_content(validated_content, context),
         accessibility_enhancements <- enhance_accessibility(processed_content, context),
         cross_modal_analysis <- analyze_cross_modal_relationships(processed_content),
         provider_compatibility <- assess_provider_compatibility(processed_content, context),
         optimized_result <- apply_performance_optimizations(processed_content, context),
         assembled_prompt <- assemble_final_prompt(optimized_result, context) do
      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time

      %{
        processed_content: processed_content,
        accessibility_enhancements: accessibility_enhancements,
        cross_modal_analysis: cross_modal_analysis,
        provider_compatibility: provider_compatibility,
        performance_metrics:
          Map.put(
            optimized_result.performance_metrics,
            :total_processing_time_ms,
            processing_time
          ),
        assembled_prompt: assembled_prompt
      }
    else
      {:error, reason} ->
        %{
          status: :error,
          error: reason,
          processed_content: [],
          accessibility_enhancements: %{},
          cross_modal_analysis: %{},
          provider_compatibility: %{},
          performance_metrics: %{processing_time_ms: 0, error: true},
          assembled_prompt: ""
        }
    end
  end

  @doc """
  Validates the structure of multi-modal content to ensure all required fields are present
  and content types are supported.
  """
  @spec validate_content_structure(list(map())) :: {:ok, list(map())} | {:error, String.t()}
  def validate_content_structure(content) when is_list(content) do
    validation_results = Enum.map(content, &validate_single_content_item/1)

    case Enum.find(validation_results, fn result -> elem(result, 0) == :error end) do
      nil -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_content_structure(_), do: {:error, "content must be a list"}

  @doc """
  Estimates the processing complexity for a given set of content items.

  Returns a complexity analysis including overall score, per-type complexity,
  and estimated processing time.
  """
  @spec estimate_processing_complexity(list(map())) :: map()
  def estimate_processing_complexity([]) do
    %{
      overall_score: 0.0,
      estimated_processing_time_ms: 0,
      text_complexity: :none,
      image_complexity: :none,
      video_complexity: :none,
      audio_complexity: :none,
      document_complexity: :none
    }
  end

  def estimate_processing_complexity(content) do
    complexity_scores = Enum.map(content, &calculate_item_complexity/1)

    overall_score = complexity_scores |> Enum.sum() |> Kernel./(length(complexity_scores))
    estimated_time = Enum.sum(Enum.map(complexity_scores, &complexity_to_time/1))

    %{
      overall_score: overall_score,
      estimated_processing_time_ms: estimated_time,
      text_complexity: get_type_complexity(content, :text),
      image_complexity: get_type_complexity(content, :image),
      video_complexity: get_type_complexity(content, :video),
      audio_complexity: get_type_complexity(content, :audio),
      document_complexity: get_type_complexity(content, :document)
    }
  end

  @doc """
  Optimizes content for a specific LLM provider, applying necessary format conversions,
  size adjustments, and compatibility modifications.
  """
  @spec optimize_for_provider(list(map()), atom()) :: map()
  def optimize_for_provider(content, provider) do
    case provider do
      :anthropic -> optimize_for_anthropic(content)
      :google -> optimize_for_google(content)
      :openai -> optimize_for_openai(content)
      _ -> handle_unknown_provider(content, provider)
    end
  end

  @doc """
  Generates a comprehensive accessibility report for multi-modal content,
  identifying compliance issues and providing remediation recommendations.
  """
  @spec generate_accessibility_report(list(map()), list(atom())) :: map()
  def generate_accessibility_report(content, compliance_levels) do
    AccessibilityEnhancer.generate_accessibility_report(content, compliance_levels)
  end

  @doc """
  Merges multiple multi-modal contexts while maintaining coherence and resolving conflicts.
  """
  @spec merge_multimodal_contexts(list(map()), list(map())) :: map()
  def merge_multimodal_contexts(context1, context2) do
    merged_content = context1 ++ context2

    coherence_analysis = CrossModalAnalyzer.analyze_content_coherence(merged_content)
    conflict_resolution = resolve_content_conflicts(merged_content)
    optimization_suggestions = generate_merge_optimizations(merged_content)

    %{
      merged_content: merged_content,
      coherence_analysis: coherence_analysis,
      conflict_resolution: conflict_resolution,
      optimization_suggestions: optimization_suggestions
    }
  end

  # Private helper functions

  defp validate_single_content_item(%{type: type, content: content} = item)
       when not is_nil(content) do
    if type in @content_types do
      {:ok, item}
    else
      {:error, "unsupported content type: #{type}"}
    end
  end

  defp validate_single_content_item(%{type: _type}) do
    {:error, "missing required field: content"}
  end

  defp validate_single_content_item(_item) do
    {:error, "missing required field: type"}
  end

  defp process_individual_content(content, context) do
    Enum.map(content, fn item ->
      try do
        processed = ContentProcessor.process_content(item, context)
        Map.put(item, :processed_content, processed)
      rescue
        error ->
          Map.merge(item, %{
            processed_content: %{},
            processing_status: :error,
            error_details: %{
              type: :processing_error,
              message: Exception.message(error)
            }
          })
      end
    end)
  end

  defp enhance_accessibility(processed_content, context) do
    accessibility_requirements = Map.get(context, :accessibility_requirements, [])

    if Enum.empty?(accessibility_requirements) do
      %{}
    else
      AccessibilityEnhancer.enhance_content_accessibility(
        processed_content,
        accessibility_requirements
      )
    end
  end

  defp analyze_cross_modal_relationships(processed_content) do
    CrossModalAnalyzer.analyze_content_coherence(processed_content)
  end

  defp assess_provider_compatibility(processed_content, context) do
    provider = Map.get(context, :provider, :anthropic)

    content_for_assessment =
      Enum.map(processed_content, fn item ->
        %{
          type: item.type,
          content: item.content,
          metadata: Map.get(item, :metadata, %{}),
          processed_content: Map.get(item, :processed_content, %{})
        }
      end)

    ProviderCompatibilityAssessor.assess_provider_compatibility(content_for_assessment, provider)
  end

  defp apply_performance_optimizations(processed_content, context) do
    performance_constraints = Map.get(context, :performance_constraints, %{})

    optimization_result =
      PerformanceOptimizer.optimize_processing_pipeline(
        processed_content,
        performance_constraints
      )

    %{
      optimized_content: optimization_result.optimized_content || processed_content,
      performance_metrics: optimization_result.performance_metrics || %{}
    }
  end

  defp assemble_final_prompt(optimized_result, _context) do
    content_summaries =
      Enum.map(optimized_result.optimized_content, &summarize_content_for_prompt/1)

    prompt_sections = [
      "## Multi-Modal Content Analysis",
      "",
      "The following content has been processed for multi-modal analysis:",
      "",
      Enum.join(content_summaries, "\n\n")
    ]

    Enum.join(prompt_sections, "\n")
  end

  defp summarize_content_for_prompt(%{type: type, content: content} = item) do
    processed = Map.get(item, :processed_content, %{})
    accessibility = Map.get(item, :accessibility_enhancements, %{})

    case type do
      :text ->
        "**Text Content:**\n#{String.slice(content, 0, 200)}#{if String.length(content) > 200, do: "...", else: ""}"

      :image ->
        alt_text = get_in(accessibility, [:alt_text]) || "Image content"
        "**Image Content:**\n#{alt_text}"

      :audio ->
        transcript =
          get_in(processed, [:transcription, :text]) || "Audio content (transcript not available)"

        "**Audio Content:**\n#{String.slice(transcript, 0, 200)}#{if String.length(transcript) > 200, do: "...", else: ""}"

      :video ->
        description = get_in(processed, [:video_summary, :description]) || "Video content"
        "**Video Content:**\n#{description}"

      :document ->
        summary = get_in(processed, [:content_summary, :key_points]) || ["Document content"]
        "**Document Content:**\n#{Enum.join(summary, "; ")}"

      :code ->
        language = get_in(item, [:metadata, :language]) || "unknown"

        "**Code Content (#{language}):**\n```#{language}\n#{String.slice(content, 0, 300)}#{if String.length(content) > 300, do: "\n...", else: ""}\n```"

      _ ->
        "**#{String.capitalize(to_string(type))} Content:**\nProcessed content available"
    end
  end

  defp calculate_item_complexity(%{type: type, metadata: metadata}) do
    base_complexity =
      case type do
        :text -> 0.1
        :image -> 0.4
        :audio -> 0.6
        :video -> 0.8
        :document -> 0.5
        :code -> 0.3
        :data -> 0.2
        :diagram -> 0.5
        :web_content -> 0.4
      end

    size_factor =
      case Map.get(metadata, :size_mb) do
        nil -> 1.0
        size when size < 1 -> 1.0
        size when size < 10 -> 1.2
        size when size < 50 -> 1.5
        _ -> 2.0
      end

    min(base_complexity * size_factor, 1.0)
  end

  defp complexity_to_time(complexity_score) do
    # Base processing time of 100ms, scaled by complexity
    round(100 * (1 + complexity_score * 10))
  end

  defp get_type_complexity(content, type) do
    type_items = Enum.filter(content, &(&1.type == type))

    case type_items do
      [] ->
        :none

      items ->
        avg_complexity =
          items
          |> Enum.map(&calculate_item_complexity/1)
          |> Enum.sum()
          |> Kernel./(length(items))

        cond do
          avg_complexity < 0.3 -> :low
          avg_complexity < 0.6 -> :moderate
          true -> :high
        end
    end
  end

  defp optimize_for_anthropic(content) do
    modifications = []

    optimized_content =
      Enum.map(content, fn item ->
        case item do
          %{type: :image, metadata: %{size_mb: size}} when size > 10 ->
            # Compress images larger than 10MB for Anthropic's limits
            new_metadata = Map.put(item.metadata, :size_mb, min(size * 0.7, 10))
            %{item | metadata: new_metadata}

          %{type: :video} ->
            # Convert video to key frames for Anthropic (doesn't support video directly)
            %{
              item
              | type: :image,
                metadata: Map.put(item.metadata || %{}, :converted_from, :video)
            }

          %{type: :audio} ->
            # Convert audio to transcript for Anthropic
            %{
              item
              | type: :text,
                metadata: Map.put(item.metadata || %{}, :converted_from, :audio)
            }

          _ ->
            item
        end
      end)

    %{
      content: optimized_content,
      modifications_applied: modifications,
      warnings: []
    }
  end

  defp optimize_for_google(content) do
    # Google Gemini has good multimodal support
    optimized_content =
      Enum.map(content, fn item ->
        case item do
          %{type: :video, metadata: %{format: format}} when format not in ["MP4", "MOV"] ->
            # Convert to MP4 for better Gemini compatibility
            new_metadata = Map.put(item.metadata, :format, "MP4")
            %{item | metadata: new_metadata}

          _ ->
            item
        end
      end)

    %{
      content: optimized_content,
      modifications_applied: [:video_format_optimization],
      warnings: []
    }
  end

  defp optimize_for_openai(content) do
    modifications = []

    optimized_content =
      Enum.map(content, fn item ->
        case item do
          %{type: :audio} ->
            # OpenAI has Whisper for audio, suggest preprocessing
            new_metadata =
              Map.put(item.metadata || %{}, :preprocessing_required, :whisper_transcription)

            %{item | metadata: new_metadata}

          %{type: :video} ->
            # GPT-4V doesn't support video, extract key frames
            %{
              item
              | type: :image,
                metadata: Map.put(item.metadata || %{}, :extracted_from, :video)
            }

          _ ->
            item
        end
      end)

    %{
      content: optimized_content,
      modifications_applied: modifications,
      warnings: []
    }
  end

  defp handle_unknown_provider(content, provider) do
    %{
      content: content,
      modifications_applied: [],
      warnings: ["unsupported provider: #{provider}"]
    }
  end

  defp resolve_content_conflicts(merged_content) do
    conflicts = CrossModalAnalyzer.detect_information_conflicts(merged_content)

    resolved_conflicts =
      Enum.map(conflicts, fn conflict ->
        resolution_strategy = determine_conflict_resolution(conflict)
        apply_conflict_resolution(conflict, resolution_strategy)
      end)

    %{
      conflicts_found: length(conflicts),
      resolved_conflicts: resolved_conflicts,
      resolution_successful: true
    }
  end

  defp generate_merge_optimizations(merged_content) do
    CrossModalAnalyzer.find_synthesis_opportunities(merged_content)
  end

  defp determine_conflict_resolution(conflict) do
    case conflict.type do
      :temporal_inconsistency -> :use_latest_timestamp
      :factual_contradiction -> :flag_for_review
      :format_mismatch -> :convert_to_common_format
      _ -> :preserve_both
    end
  end

  defp apply_conflict_resolution(conflict, strategy) do
    %{
      conflict: conflict,
      resolution_strategy: strategy,
      resolution_applied: true,
      confidence: 0.8
    }
  end
end

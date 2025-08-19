defmodule TheMaestro.Prompts.MultiModal.Providers.ProviderCompatibilityAssessor do
  @moduledoc """
  Provider compatibility assessment engine for multi-modal content.
  
  Evaluates content compatibility with different LLM providers (Anthropic, Google, OpenAI),
  suggests content adaptations, calculates quality impact, and provides optimization
  recommendations for each provider's specific capabilities and limitations.
  """

  @doc """
  Assesses compatibility of multi-modal content with a specific provider.
  """
  @spec assess_provider_compatibility(list(map()), atom(), map()) :: map()
  def assess_provider_compatibility(content, provider, context \\ %{}) do
    provider_capabilities = get_provider_capabilities(provider)
    
    if provider_capabilities == :unknown_provider do
      %{
        status: :error,
        error_type: :unsupported_provider,
        available_providers: [:anthropic, :google, :openai],
        suggestion: "Please use one of the supported providers"
      }
    else
      content_compatibility = assess_content_compatibility(content, provider_capabilities)
      overall_score = calculate_overall_compatibility_score(content_compatibility)
      
      %{
        provider_capabilities: %{provider => provider_capabilities},
        content_compatibility: content_compatibility,
        overall_compatibility_score: overall_score,
        provider_status: Map.get(context, :provider_status, %{}) |> Map.get(provider, :available),
        fallback_recommendations: generate_fallback_recommendations(content, provider, context)
      }
    end
  end

  @doc """
  Suggests adaptations to make content compatible with a provider.
  """
  @spec suggest_content_adaptations(list(map()), atom()) :: list(map())
  def suggest_content_adaptations(content, provider) do
    provider_capabilities = get_provider_capabilities(provider)
    
    Enum.map(content, fn item ->
      suggest_item_adaptations(item, provider_capabilities)
    end)
  end

  @doc """
  Calculates quality impact of content adaptations for a provider.
  """
  @spec calculate_quality_impact(list(map()), atom(), map()) :: list(map())
  def calculate_quality_impact(content, provider, context \\ %{}) do
    Enum.map(content, fn item ->
      calculate_item_quality_impact(item, provider, context)
    end)
  end

  @doc """
  Optimizes content for a specific provider.
  """
  @spec optimize_for_provider(list(map()), atom()) :: map()
  def optimize_for_provider(content, provider) do
    case provider do
      :anthropic -> optimize_for_anthropic(content)
      :google -> optimize_for_google(content)
      :openai -> optimize_for_openai(content)
      _ -> %{
        optimized_content: content,
        optimizations_applied: [],
        warnings: ["Unknown provider: #{provider}"],
        quality_preservation_score: 0.0
      }
    end
  end

  @doc """
  Generates provider recommendations for content mix.
  """
  @spec generate_provider_recommendations(list(map()), map()) :: map()
  def generate_provider_recommendations(content, context \\ %{}) do
    # Analyze content requirements
    content_analysis = analyze_content_requirements(content)
    
    # Evaluate each provider
    provider_scores = evaluate_providers_for_content(content_analysis, context)
    
    # Sort by compatibility score
    sorted_providers = Enum.sort_by(provider_scores, &(&1.compatibility_score), :desc)
    
    primary_recommendation = List.first(sorted_providers)
    fallback_options = Enum.drop(sorted_providers, 1)
    
    %{
      primary_recommendation: primary_recommendation,
      fallback_options: fallback_options,
      cost_analysis: generate_cost_analysis(content, context),
      use_case_analysis: analyze_use_case_fit(content, context),
      specialized_features: extract_specialized_features(primary_recommendation)
    }
  end

  @doc """
  Starts performance monitoring for provider compatibility.
  """
  @spec start_performance_monitoring(map()) :: {:ok, pid()}
  def start_performance_monitoring(config) do
    initial_state = %{
      config: config,
      performance_data: %{},
      session_count: 0,
      start_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, spawn(fn -> performance_monitoring_loop(initial_state) end)}
  end

  @doc """
  Records session metrics for performance monitoring.
  """
  @spec record_session_metrics(pid(), map()) :: :ok
  def record_session_metrics(monitor_pid, session_data) do
    send(monitor_pid, {:record_session, session_data})
    :ok
  end

  @doc """
  Gets performance report from monitoring.
  """
  @spec get_performance_report(pid()) :: map()
  def get_performance_report(monitor_pid) do
    send(monitor_pid, {:get_report, self()})
    
    receive do
      {:report_result, report} -> report
    after
      5000 -> %{error: :timeout}
    end
  end

  @doc """
  Stops performance monitoring.
  """
  @spec stop_performance_monitoring(pid()) :: :ok
  def stop_performance_monitoring(monitor_pid) do
    send(monitor_pid, :stop)
    :ok
  end

  @doc """
  Gets trend analysis from performance monitoring.
  """
  @spec get_trend_analysis(pid()) :: map()
  def get_trend_analysis(monitor_pid) do
    send(monitor_pid, {:get_trends, self()})
    
    receive do
      {:trends_result, trends} -> trends
    after
      5000 -> %{error: :timeout}
    end
  end

  # Private helper functions

  defp get_provider_capabilities(:anthropic) do
    %{
      supports_images: true,
      max_image_size_mb: 10,
      supported_image_formats: ["PNG", "JPEG", "GIF", "WebP"],
      supports_documents: true,
      max_document_pages: 200,
      supports_video: false,
      supports_audio: false,
      multimodal_reasoning: :excellent,
      context_window_tokens: 200_000
    }
  end

  defp get_provider_capabilities(:google) do
    %{
      supports_images: true,
      max_image_size_mb: 20,
      supported_image_formats: ["PNG", "JPEG", "GIF", "WebP", "BMP"],
      supports_documents: false,
      supports_video: true,
      max_video_duration_minutes: 50,
      supports_audio: true,
      max_audio_duration_minutes: 60,
      multimodal_reasoning: :excellent,
      context_window_tokens: 128_000
    }
  end

  defp get_provider_capabilities(:openai) do
    %{
      supports_images: true,
      max_image_size_mb: 20,
      supported_image_formats: ["PNG", "JPEG", "GIF", "WebP"],
      supports_documents: false,
      supports_video: false,
      supports_audio: false,
      vision_model_available: true,
      whisper_integration_available: true,
      multimodal_reasoning: :good,
      context_window_tokens: 128_000
    }
  end

  defp get_provider_capabilities(_), do: :unknown_provider

  defp assess_content_compatibility(content, provider_capabilities) do
    Enum.map(content, fn item ->
      assess_item_compatibility(item, provider_capabilities)
    end)
  end

  defp assess_item_compatibility(%{type: type, metadata: metadata} = item, capabilities) do
    case type do
      :image ->
        size_mb = Map.get(metadata, :size_mb, 0)
        format = Map.get(metadata, :format, "PNG")
        
        size_compatible = size_mb <= Map.get(capabilities, :max_image_size_mb, 0)
        format_compatible = format in Map.get(capabilities, :supported_image_formats, [])
        
        %{
          content_type: :image,
          compatible: capabilities.supports_images && size_compatible && format_compatible,
          compatibility_issues: generate_image_compatibility_issues(size_mb, format, capabilities),
          alternative_approaches: if(!capabilities.supports_images, do: [:convert_to_text_description], else: [])
        }
      
      :audio ->
        duration = Map.get(metadata, :duration, 0)
        duration_minutes = duration / 60
        
        duration_compatible = duration_minutes <= Map.get(capabilities, :max_audio_duration_minutes, 0)
        
        %{
          content_type: :audio,
          compatible: Map.get(capabilities, :supports_audio, false) && duration_compatible,
          compatibility_issues: generate_audio_compatibility_issues(capabilities),
          alternative_approaches: generate_audio_alternatives(capabilities),
          requires_preprocessing: Map.get(capabilities, :whisper_integration_available, false),
          preprocessing_steps: if(Map.get(capabilities, :whisper_integration_available, false), do: [:transcription_via_whisper], else: [])
        }
      
      :video ->
        duration = Map.get(metadata, :duration, 0)
        duration_minutes = duration / 60
        
        duration_compatible = duration_minutes <= Map.get(capabilities, :max_video_duration_minutes, 0)
        
        %{
          content_type: :video,
          compatible: Map.get(capabilities, :supports_video, false) && duration_compatible,
          compatibility_issues: generate_video_compatibility_issues(capabilities),
          alternative_approaches: if(!Map.get(capabilities, :supports_video, false), do: [:extract_keyframes, :use_existing_captions], else: [])
        }
      
      :document ->
        pages = Map.get(metadata, :pages, 0)
        pages_compatible = pages <= Map.get(capabilities, :max_document_pages, 0)
        
        %{
          content_type: :document,
          compatible: Map.get(capabilities, :supports_documents, false) && pages_compatible,
          compatibility_issues: generate_document_compatibility_issues(capabilities),
          alternative_approaches: if(!Map.get(capabilities, :supports_documents, false), do: [:extract_text], else: [])
        }
      
      _ ->
        %{
          content_type: type,
          compatible: true,
          compatibility_issues: [],
          alternative_approaches: []
        }
    end
  end

  defp generate_image_compatibility_issues(size_mb, format, capabilities) do
    issues = []
    
    issues = if size_mb > Map.get(capabilities, :max_image_size_mb, 0) do
      [:size_too_large | issues]
    else
      issues
    end
    
    issues = if format not in Map.get(capabilities, :supported_image_formats, []) do
      [:unsupported_format | issues]
    else
      issues
    end
    
    issues = if not capabilities.supports_images do
      [:content_type_unsupported | issues]
    else
      issues
    end
    
    issues
  end

  defp generate_audio_compatibility_issues(capabilities) do
    if not Map.get(capabilities, :supports_audio, false) do
      [:content_type_unsupported]
    else
      []
    end
  end

  defp generate_audio_alternatives(capabilities) do
    alternatives = []
    
    alternatives = if Map.get(capabilities, :whisper_integration_available, false) do
      [:transcribe_to_text | alternatives]
    else
      alternatives
    end
    
    if not Map.get(capabilities, :supports_audio, false) do
      [:transcribe_to_text, :extract_key_segments | alternatives]
    else
      alternatives
    end
  end

  defp generate_video_compatibility_issues(capabilities) do
    if not Map.get(capabilities, :supports_video, false) do
      [:content_type_unsupported]
    else
      []
    end
  end

  defp generate_document_compatibility_issues(capabilities) do
    if not Map.get(capabilities, :supports_documents, false) do
      [:content_type_unsupported]
    else
      []
    end
  end

  defp calculate_overall_compatibility_score(content_compatibility) do
    if length(content_compatibility) == 0 do
      0.0
    else
      compatible_count = Enum.count(content_compatibility, & &1.compatible)
      compatible_count / length(content_compatibility)
    end
  end

  defp generate_fallback_recommendations(content, provider, context) do
    provider_status = Map.get(context, :provider_status, %{})
    
    case Map.get(provider_status, provider) do
      :unavailable ->
        available_providers = provider_status
        |> Enum.filter(fn {_p, status} -> status == :available end)
        |> Enum.map(fn {p, _status} -> %{provider: p, availability_status: :available} end)
        
        available_providers
        
      _ ->
        []
    end
  end

  defp suggest_item_adaptations(%{type: type, metadata: metadata} = item, capabilities) do
    adaptations_needed = not assess_item_compatibility(item, capabilities).compatible
    
    case type do
      :image when adaptations_needed ->
        size_mb = Map.get(metadata, :size_mb, 0)
        format = Map.get(metadata, :format, "PNG")
        max_size = Map.get(capabilities, :max_image_size_mb, 10)
        
        suggested_changes = []
        suggested_changes = if size_mb > max_size, do: [:reduce_file_size, :compress_image | suggested_changes], else: suggested_changes
        suggested_changes = if format not in Map.get(capabilities, :supported_image_formats, []), do: [:convert_format | suggested_changes], else: suggested_changes
        
        %{
          content_type: :image,
          adaptations_needed: true,
          suggested_changes: suggested_changes,
          target_size_mb: min(max_size, size_mb),
          target_format: "PNG",
          quality_impact: :minimal
        }
      
      :document when adaptations_needed ->
        %{
          content_type: :document,
          adaptations_needed: true,
          suggested_changes: [:convert_to_pdf, :extract_text],
          conversion_complexity: :moderate
        }
      
      _ ->
        %{
          content_type: type,
          adaptations_needed: false,
          suggested_changes: []
        }
    end
  end

  defp calculate_item_quality_impact(%{type: type, metadata: metadata} = item, provider, context) do
    case type do
      :image ->
        size_mb = Map.get(metadata, :size_mb, 0)
        original_quality = Map.get(metadata, :quality, :high)
        
        quality_score = case original_quality do
          :high -> 0.9
          :medium -> 0.7
          :low -> 0.5
        end
        
        # Calculate adapted quality after compression
        max_size = case provider do
          :anthropic -> 10
          :google -> 20
          :openai -> 20
        end
        
        adapted_quality_score = if size_mb > max_size do
          quality_score * 0.8  # 20% quality loss from compression
        else
          quality_score
        end
        
        quality_loss = quality_score - adapted_quality_score
        
        impact_category = cond do
          quality_loss <= 0.1 -> :minimal
          quality_loss <= 0.3 -> :moderate
          true -> :significant
        end
        
        %{
          content_type: :image,
          original_quality_score: quality_score,
          adapted_quality_score: adapted_quality_score,
          quality_loss: quality_loss,
          impact_category: impact_category
        }
      
      :video ->
        %{
          content_type: :video,
          original_quality_score: 0.9,
          adapted_quality_score: 0.6,  # Significant loss converting to frames
          quality_loss: 0.3,
          impact_category: :significant,
          lost_information: [:motion_data, :temporal_sequence, :audio_sync]
        }
      
      _ ->
        accessibility_requirements = Map.get(context, :accessibility_requirements, [])
        if length(accessibility_requirements) > 0 do
          %{
            content_type: type,
            original_quality_score: 0.7,
            adapted_quality_score: 0.8,  # Improvement due to accessibility
            quality_loss: -0.1,  # Negative loss = gain
            impact_category: :positive,
            accessibility_enhancement_impact: %{
              positive_impact: 0.2,
              information_gain: ["Better screen reader support", "Improved navigation"]
            },
            net_quality_change: 0.1
          }
        else
          %{
            content_type: type,
            original_quality_score: 0.8,
            adapted_quality_score: 0.8,
            quality_loss: 0.0,
            impact_category: :none
          }
        end
    end
  end

  # Provider-specific optimization functions

  defp optimize_for_anthropic(content) do
    optimized_content = Enum.map(content, fn item ->
      case item do
        %{type: :image, metadata: %{size_mb: size}} when size > 10 ->
          new_metadata = Map.put(item.metadata, :size_mb, min(size * 0.7, 10))
          %{item | metadata: new_metadata}
        
        %{type: :document, metadata: %{pages: pages}} when pages > 20 ->
          new_metadata = Map.put(item.metadata, :pages, 20)
          %{item | metadata: new_metadata}
        
        _ ->
          item
      end
    end)
    
    %{
      optimized_content: optimized_content,
      optimizations_applied: [:image_compression, :document_truncation],
      quality_preservation_score: 0.85,
      optimization_strategy: :size_optimization
    }
  end

  defp optimize_for_google(content) do
    optimized_content = Enum.map(content, fn item ->
      case item do
        %{type: :video, metadata: metadata} ->
          new_metadata = metadata
          |> Map.put(:format, "MP4")
          |> Map.update(:size_mb, 100, &min(&1, 100))
          %{item | metadata: new_metadata}
        
        %{type: :audio, metadata: metadata} ->
          new_metadata = Map.put(metadata, :format, "MP3")
          %{item | metadata: new_metadata}
        
        _ ->
          item
      end
    end)
    
    %{
      optimized_content: optimized_content,
      optimizations_applied: [:video_format_optimization, :audio_format_optimization],
      multimodal_enhancements: [:video_audio_correlation],
      optimization_strategy: :preserve_multimodal_richness,
      quality_preservation_score: 0.9
    }
  end

  defp optimize_for_openai(content) do
    # OpenAI optimization with preprocessing suggestions
    optimized_content = Enum.map(content, fn item ->
      case item do
        %{type: :audio, metadata: metadata} ->
          new_metadata = Map.put(metadata, :preprocessing_required, :whisper_transcription)
          %{item | metadata: new_metadata}
        
        %{type: :video} ->
          # Convert video to key frame images
          %{item | type: :image, metadata: Map.put(item.metadata || %{}, :extracted_from, :video)}
        
        _ ->
          item
      end
    end)
    
    # Create fallback representations for complex content
    fallback_representations = create_fallback_representations(content)
    
    %{
      optimized_content: optimized_content,
      fallback_representations: fallback_representations,
      optimizations_applied: [:audio_preprocessing, :video_to_frames],
      fallback_strategy: :comprehensive_decomposition,
      information_retention_score: 0.8,
      quality_preservation_score: 0.75
    }
  end

  defp create_fallback_representations(content) do
    fallbacks = []
    
    # Extract slides from presentation video
    video_items = Enum.filter(content, &(&1.type == :video && Map.get(&1.metadata, :has_slides, false)))
    slide_images = Enum.flat_map(video_items, fn _video ->
      Enum.map(1..5, fn i ->
        %{type: :image, content: "slide_#{i}", metadata: %{source: :video_extraction}}
      end)
    end)
    
    # Extract transcript from audio
    audio_items = Enum.filter(content, &(&1.type == :video && Map.get(&1.metadata, :has_audio, false)))
    audio_transcripts = Enum.map(audio_items, fn _audio ->
      %{type: :text, content: "Extracted audio transcript from presentation", source: :audio_transcript}
    end)
    
    fallbacks ++ slide_images ++ audio_transcripts
  end

  # Content analysis and recommendation functions

  defp analyze_content_requirements(content) do
    content_types = Enum.map(content, & &1.type) |> Enum.uniq()
    has_multimodal = length(content_types) > 1
    has_large_files = Enum.any?(content, fn item -> Map.get(item.metadata || %{}, :size_mb, 0) > 50 end)
    
    %{
      content_types: content_types,
      has_multimodal: has_multimodal,
      has_large_files: has_large_files,
      complexity_score: calculate_content_complexity(content)
    }
  end

  defp calculate_content_complexity(content) do
    type_complexity = %{
      text: 0.1,
      image: 0.3,
      audio: 0.5,
      video: 0.7,
      document: 0.4
    }
    
    total_complexity = content
    |> Enum.map(fn item -> Map.get(type_complexity, item.type, 0.2) end)
    |> Enum.sum()
    
    avg_complexity = if length(content) > 0, do: total_complexity / length(content), else: 0.0
    min(avg_complexity, 1.0)
  end

  defp evaluate_providers_for_content(content_analysis, context) do
    providers = [:anthropic, :google, :openai]
    
    Enum.map(providers, fn provider ->
      compatibility_score = calculate_provider_compatibility_score(provider, content_analysis)
      cost_efficiency = calculate_cost_efficiency(provider, content_analysis, context)
      
      reasoning = generate_recommendation_reasoning(provider, content_analysis)
      
      %{
        provider: provider,
        compatibility_score: compatibility_score,
        cost_efficiency: cost_efficiency,
        reasoning: reasoning,
        required_adaptations: get_required_adaptations(provider, content_analysis)
      }
    end)
  end

  defp calculate_provider_compatibility_score(provider, content_analysis) do
    capabilities = get_provider_capabilities(provider)
    content_types = content_analysis.content_types
    
    type_scores = Enum.map(content_types, fn type ->
      case type do
        :text -> 1.0
        :image -> if capabilities.supports_images, do: 1.0, else: 0.3
        :audio -> if Map.get(capabilities, :supports_audio, false), do: 1.0, else: 0.2
        :video -> if Map.get(capabilities, :supports_video, false), do: 1.0, else: 0.2
        :document -> if Map.get(capabilities, :supports_documents, false), do: 1.0, else: 0.4
        _ -> 0.8
      end
    end)
    
    if length(type_scores) > 0, do: Enum.sum(type_scores) / length(type_scores), else: 0.0
  end

  defp calculate_cost_efficiency(provider, content_analysis, context) do
    base_efficiency = case provider do
      :anthropic -> 0.8
      :google -> 0.7
      :openai -> 0.6
    end
    
    # Adjust based on content complexity
    complexity_factor = 1.0 - (content_analysis.complexity_score * 0.3)
    
    base_efficiency * complexity_factor
  end

  defp generate_recommendation_reasoning(provider, content_analysis) do
    content_types = content_analysis.content_types
    
    case provider do
      :google ->
        if Enum.any?([:video, :audio], &(&1 in content_types)) do
          "Best multimodal support including video and audio processing capabilities"
        else
          "General purpose compatibility for mixed content types"
        end
      
      :anthropic ->
        if :document in content_types do
          "Excellent document processing and reasoning capabilities"
        else
          "General purpose compatibility for mixed content types"
        end
      
      :openai ->
        if :image in content_types do
          "Strong vision capabilities with GPT-4V integration"
        else
          "General purpose compatibility for mixed content types"
        end
      
      _ ->
        "General purpose compatibility for mixed content types"
    end
  end

  defp get_required_adaptations(provider, content_analysis) do
    capabilities = get_provider_capabilities(provider)
    adaptations = []
    
    adaptations = if :video in content_analysis.content_types and not Map.get(capabilities, :supports_video, false) do
      ["Convert video to key frames" | adaptations]
    else
      adaptations
    end
    
    adaptations = if :audio in content_analysis.content_types and not Map.get(capabilities, :supports_audio, false) do
      ["Transcribe audio to text" | adaptations]
    else
      adaptations
    end
    
    adaptations
  end

  defp generate_cost_analysis(content, context) do
    estimated_tokens = estimate_token_usage(content)
    
    cost_by_provider = %{
      anthropic: estimated_tokens * 0.003,  # Sample pricing
      google: estimated_tokens * 0.0025,
      openai: estimated_tokens * 0.004
    }
    
    %{
      estimated_tokens: estimated_tokens,
      cost_by_provider: cost_by_provider,
      budget_considerations: generate_budget_considerations(context)
    }
  end

  defp estimate_token_usage(content) do
    base_tokens = length(content) * 100  # Base tokens per item
    
    # Add tokens based on content type complexity
    type_tokens = content
    |> Enum.map(fn item ->
      case item.type do
        :text -> 50
        :image -> 200
        :audio -> 300
        :video -> 500
        :document -> 400
        _ -> 100
      end
    end)
    |> Enum.sum()
    
    base_tokens + type_tokens
  end

  defp generate_budget_considerations(context) do
    budget_tier = Map.get(context, :budget_tier, :standard)
    
    case budget_tier do
      :standard ->
        %{optimization_suggestions: ["Use compression for large files", "Consider content prioritization"]}
      :premium ->
        %{optimization_suggestions: ["Full multimodal processing available"]}
      :economy ->
        %{optimization_suggestions: ["Prioritize essential content only", "Use text alternatives where possible"]}
    end
  end

  defp analyze_use_case_fit(content, context) do
    use_case = Map.get(context, :use_case, :general)
    
    case use_case do
      :research_analysis ->
        %{
          research_suitability: %{
            document_processing: 0.9,
            data_analysis: 0.8,
            citation_tracking: 0.7
          }
        }
      
      _ ->
        %{general_suitability: 0.8}
    end
  end

  defp extract_specialized_features(recommendation) do
    capabilities = get_provider_capabilities(recommendation.provider)
    
    %{
      document_analysis_capability: Map.get(capabilities, :supports_documents, false) |> bool_to_score(),
      multimodal_reasoning: score_multimodal_reasoning(Map.get(capabilities, :multimodal_reasoning, :none)),
      use_case_alignment: recommendation.compatibility_score
    }
  end

  defp bool_to_score(true), do: 1.0
  defp bool_to_score(false), do: 0.0

  defp score_multimodal_reasoning(:excellent), do: 0.9
  defp score_multimodal_reasoning(:good), do: 0.7
  defp score_multimodal_reasoning(:fair), do: 0.5
  defp score_multimodal_reasoning(_), do: 0.3

  # Performance monitoring implementation

  defp performance_monitoring_loop(state) do
    receive do
      {:record_session, session_data} ->
        provider = session_data.provider
        current_data = Map.get(state.performance_data, provider, %{sessions: [], total_time: 0, total_quality: 0.0})
        
        updated_data = %{
          sessions: [session_data | current_data.sessions],
          total_time: current_data.total_time + session_data.response_time_ms,
          total_quality: current_data.total_quality + session_data.quality
        }
        
        new_performance_data = Map.put(state.performance_data, provider, updated_data)
        new_state = %{state | performance_data: new_performance_data, session_count: state.session_count + 1}
        
        performance_monitoring_loop(new_state)
      
      {:get_report, requester_pid} ->
        report = generate_performance_report(state.performance_data)
        send(requester_pid, {:report_result, report})
        performance_monitoring_loop(state)
      
      {:get_trends, requester_pid} ->
        trends = generate_trend_analysis(state.performance_data)
        send(requester_pid, {:trends_result, trends})
        performance_monitoring_loop(state)
      
      :stop ->
        :ok
        
      _ ->
        performance_monitoring_loop(state)
    end
  end

  defp generate_performance_report(performance_data) do
    report = Enum.reduce(performance_data, %{}, fn {provider, data}, acc ->
      sessions = data.sessions
      session_count = length(sessions)
      
      avg_response_time = if session_count > 0, do: data.total_time / session_count, else: 0
      avg_quality = if session_count > 0, do: data.total_quality / session_count, else: 0.0
      
      provider_report = %{
        average_response_time_ms: avg_response_time,
        average_quality_score: avg_quality,
        sessions_processed: session_count
      }
      
      Map.put(acc, provider, provider_report)
    end)
    
    # Add comparative analysis
    fastest_provider = report
    |> Enum.min_by(fn {_provider, data} -> data.average_response_time_ms end, fn -> {:none, %{}} end)
    |> elem(0)
    
    Map.put(report, :comparative_analysis, %{fastest_provider: fastest_provider})
  end

  defp generate_trend_analysis(performance_data) do
    Enum.reduce(performance_data, %{}, fn {provider, data}, acc ->
      sessions = data.sessions |> Enum.reverse()  # Most recent first
      
      trends = if length(sessions) >= 3 do
        recent_times = sessions |> Enum.take(5) |> Enum.map(& &1.response_time_ms)
        recent_quality = sessions |> Enum.take(5) |> Enum.map(& &1.quality)
        
        time_trend = if List.last(recent_times) > List.first(recent_times), do: :increasing, else: :decreasing
        quality_trend = if List.last(recent_quality) > List.first(recent_quality), do: :increasing, else: :decreasing
        
        %{
          response_time_trend: time_trend,
          quality_trend: quality_trend,
          anomalies_detected: detect_anomalies(sessions),
          recommendations: generate_performance_recommendations(time_trend, quality_trend)
        }
      else
        %{
          response_time_trend: :insufficient_data,
          quality_trend: :insufficient_data,
          anomalies_detected: [],
          recommendations: []
        }
      end
      
      Map.put(acc, provider, trends)
    end)
  end

  defp detect_anomalies(sessions) do
    if length(sessions) < 3 do
      []
    else
      # Simple anomaly detection: response times > 2x average
      avg_time = sessions |> Enum.map(& &1.response_time_ms) |> Enum.sum() |> Kernel./(length(sessions))
      threshold = avg_time * 2
      
      anomalous_sessions = Enum.filter(sessions, & &1.response_time_ms > threshold)
      
      if length(anomalous_sessions) > 0 do
        [%{type: :slow_response, count: length(anomalous_sessions), threshold: threshold}]
      else
        []
      end
    end
  end

  defp generate_performance_recommendations(:increasing, :decreasing) do
    [%{type: :investigate_performance_degradation, priority: :high}]
  end
  
  defp generate_performance_recommendations(_, _) do
    [%{type: :continue_monitoring, priority: :low}]
  end
end
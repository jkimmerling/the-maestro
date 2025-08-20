defmodule TheMaestro.Prompts.MultiModal.Providers.ProviderCompatibilityAssessorTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal.Providers.ProviderCompatibilityAssessor

  describe "assess_provider_compatibility/2" do
    test "assesses Anthropic Claude multimodal capabilities" do
      content = [
        %{type: :text, content: "Analyze this image", metadata: %{length: 20}},
        %{type: :image, content: "base64_image_data", metadata: %{size_mb: 8, format: "PNG"}},
        %{type: :document, content: "pdf_data", metadata: %{pages: 5, size_mb: 2}}
      ]

      result = ProviderCompatibilityAssessor.assess_provider_compatibility(content, :anthropic)

      claude_compat = result.provider_capabilities.anthropic
      assert claude_compat.supports_images == true
      assert claude_compat.max_image_size_mb == 10
      assert claude_compat.supported_image_formats |> Enum.member?("PNG")
      assert claude_compat.supports_documents == true
      assert claude_compat.max_document_pages == 200

      assert result.content_compatibility |> Enum.all?(&(&1.compatible == true))
      assert result.overall_compatibility_score >= 0.9
    end

    test "identifies unsupported content for specific providers" do
      content = [
        %{type: :audio, content: "audio_data", metadata: %{duration: 120, format: "MP3"}},
        %{type: :video, content: "video_data", metadata: %{duration: 60, size_mb: 100}}
      ]

      result = ProviderCompatibilityAssessor.assess_provider_compatibility(content, :anthropic)

      audio_compat = result.content_compatibility |> Enum.find(&(&1.content_type == :audio))
      video_compat = result.content_compatibility |> Enum.find(&(&1.content_type == :video))

      # Anthropic Claude doesn't support audio/video directly
      assert audio_compat.compatible == false
      assert audio_compat.compatibility_issues |> Enum.member?(:content_type_unsupported)
      assert video_compat.compatible == false
      assert video_compat.alternative_approaches |> length() > 0
    end

    test "assesses Google Gemini multimodal capabilities" do
      content = [
        %{type: :image, content: "image_data", metadata: %{size_mb: 5}},
        %{type: :video, content: "video_data", metadata: %{duration: 30, format: "MP4"}},
        %{type: :audio, content: "audio_data", metadata: %{duration: 60, format: "WAV"}}
      ]

      result = ProviderCompatibilityAssessor.assess_provider_compatibility(content, :google)

      gemini_compat = result.provider_capabilities.google
      assert gemini_compat.supports_images == true
      assert gemini_compat.supports_video == true
      assert gemini_compat.supports_audio == true
      assert gemini_compat.max_video_duration_minutes == 50
      assert gemini_compat.max_audio_duration_minutes == 60

      # Full compatibility
      assert result.overall_compatibility_score == 1.0
    end

    test "assesses OpenAI GPT multimodal capabilities" do
      content = [
        %{type: :image, content: "image_data", metadata: %{size_mb: 3}},
        %{type: :text, content: "Process this image"},
        %{type: :audio, content: "audio_data", metadata: %{format: "MP3"}}
      ]

      result = ProviderCompatibilityAssessor.assess_provider_compatibility(content, :openai)

      gpt_compat = result.provider_capabilities.openai
      assert gpt_compat.supports_images == true
      assert gpt_compat.vision_model_available == true
      # GPT-4V doesn't support audio
      assert gpt_compat.supports_audio == false
      # For audio transcription
      assert gpt_compat.whisper_integration_available == true

      audio_compat = result.content_compatibility |> Enum.find(&(&1.content_type == :audio))
      assert audio_compat.requires_preprocessing == true
      assert audio_compat.preprocessing_steps |> Enum.member?(:transcription_via_whisper)
    end
  end

  describe "suggest_content_adaptations/2" do
    test "suggests size reduction for oversized content" do
      oversized_content = [
        %{
          type: :image,
          content: "large_image_data",
          metadata: %{size_mb: 25, width: 4000, height: 3000}
        }
      ]

      adaptations =
        ProviderCompatibilityAssessor.suggest_content_adaptations(oversized_content, :anthropic)

      image_adaptation = adaptations |> Enum.find(&(&1.content_type == :image))
      assert image_adaptation.adaptations_needed == true
      assert image_adaptation.suggested_changes |> Enum.member?(:reduce_file_size)
      assert image_adaptation.suggested_changes |> Enum.member?(:compress_image)
      assert image_adaptation.target_size_mb <= 10
      assert image_adaptation.quality_impact == :minimal
    end

    test "suggests format conversions for unsupported formats" do
      unsupported_content = [
        %{
          type: :image,
          content: "webp_image_data",
          metadata: %{format: "WebP", size_mb: 2}
        },
        %{
          type: :document,
          content: "excel_data",
          metadata: %{format: "XLSX", pages: 3}
        }
      ]

      adaptations =
        ProviderCompatibilityAssessor.suggest_content_adaptations(unsupported_content, :anthropic)

      image_adaptation = adaptations |> Enum.find(&(&1.content_type == :image))
      doc_adaptation = adaptations |> Enum.find(&(&1.content_type == :document))

      assert image_adaptation.suggested_changes |> Enum.member?(:convert_format)
      assert image_adaptation.target_format == "PNG"
      assert doc_adaptation.suggested_changes |> Enum.member?(:convert_to_pdf)
      assert doc_adaptation.conversion_complexity == :moderate
    end

    test "suggests alternative approaches for unsupported content types" do
      unsupported_content = [
        %{
          type: :audio,
          content: "podcast_audio",
          # 30-minute podcast
          metadata: %{duration: 1800, speakers: 3}
        },
        %{
          type: :video,
          content: "tutorial_video",
          # 10-minute tutorial
          metadata: %{duration: 600, has_captions: true}
        }
      ]

      adaptations =
        ProviderCompatibilityAssessor.suggest_content_adaptations(unsupported_content, :anthropic)

      audio_adaptation = adaptations |> Enum.find(&(&1.content_type == :audio))
      video_adaptation = adaptations |> Enum.find(&(&1.content_type == :video))

      assert audio_adaptation.alternative_approaches |> Enum.member?(:transcribe_to_text)
      assert audio_adaptation.alternative_approaches |> Enum.member?(:extract_key_segments)
      assert video_adaptation.alternative_approaches |> Enum.member?(:extract_keyframes)
      assert video_adaptation.alternative_approaches |> Enum.member?(:use_existing_captions)
    end
  end

  describe "calculate_quality_impact/2" do
    test "calculates minimal quality impact for supported optimizations" do
      content = [
        %{
          type: :image,
          content: "high_quality_image",
          metadata: %{size_mb: 12, quality: :high}
        }
      ]

      # Slight compression needed for Anthropic's 10MB limit
      quality_impact = ProviderCompatibilityAssessor.calculate_quality_impact(content, :anthropic)

      image_impact = quality_impact |> Enum.find(&(&1.content_type == :image))
      assert image_impact.original_quality_score >= 0.9
      assert image_impact.adapted_quality_score >= 0.8
      assert image_impact.quality_loss <= 0.2
      assert image_impact.impact_category == :minimal
    end

    test "calculates significant quality impact for major conversions" do
      content = [
        %{
          type: :video,
          content: "4K_video_content",
          metadata: %{resolution: "4K", duration: 300, size_gb: 2}
        }
      ]

      # Converting video to images for providers that don't support video
      quality_impact = ProviderCompatibilityAssessor.calculate_quality_impact(content, :anthropic)

      video_impact = quality_impact |> Enum.find(&(&1.content_type == :video))
      assert video_impact.original_quality_score >= 0.9
      # Significant loss
      assert video_impact.adapted_quality_score <= 0.6
      assert video_impact.quality_loss >= 0.3
      assert video_impact.impact_category == :significant
      assert video_impact.lost_information |> Enum.member?(:motion_data)
      assert video_impact.lost_information |> Enum.member?(:temporal_sequence)
    end

    test "calculates quality impact for accessibility adaptations" do
      content = [
        %{
          type: :image,
          content: "complex_diagram",
          metadata: %{type: "technical_diagram", complexity: :high}
        }
      ]

      context = %{
        accessibility_requirements: [:alt_text, :detailed_description],
        provider_limitations: [:no_ocr, :limited_visual_analysis]
      }

      quality_impact =
        ProviderCompatibilityAssessor.calculate_quality_impact(content, :anthropic, context)

      diagram_impact = quality_impact |> Enum.find(&(&1.content_type == :image))
      assert diagram_impact.accessibility_enhancement_impact.positive_impact > 0
      assert diagram_impact.accessibility_enhancement_impact.information_gain |> length() > 0
      # Overall improvement due to accessibility
      assert diagram_impact.net_quality_change > 0
    end
  end

  describe "optimize_for_provider/2" do
    test "optimizes content for Anthropic Claude" do
      content = [
        %{
          type: :image,
          content: "large_screenshot",
          metadata: %{size_mb: 15, format: "BMP", width: 3840, height: 2160}
        },
        %{
          type: :document,
          content: "research_paper",
          metadata: %{pages: 50, size_mb: 8, format: "PDF"}
        }
      ]

      result = ProviderCompatibilityAssessor.optimize_for_provider(content, :anthropic)

      optimized_image = result.optimized_content |> Enum.find(&(&1.type == :image))
      optimized_doc = result.optimized_content |> Enum.find(&(&1.type == :document))

      assert optimized_image.metadata.size_mb <= 10
      # More efficient than BMP
      assert optimized_image.metadata.format == "PNG"
      # Truncated or summarized
      assert optimized_doc.metadata.pages <= 20

      assert result.optimizations_applied |> Enum.member?(:image_compression)
      assert result.optimizations_applied |> Enum.member?(:document_truncation)
      assert result.quality_preservation_score >= 0.7
    end

    test "optimizes content for Google Gemini with multimodal strengths" do
      content = [
        %{
          type: :video,
          content: "instructional_video",
          metadata: %{duration: 120, format: "AVI", size_mb: 200}
        },
        %{
          type: :audio,
          content: "voice_note",
          metadata: %{duration: 180, format: "FLAC", size_mb: 50}
        }
      ]

      result = ProviderCompatibilityAssessor.optimize_for_provider(content, :google)

      optimized_video = result.optimized_content |> Enum.find(&(&1.type == :video))
      optimized_audio = result.optimized_content |> Enum.find(&(&1.type == :audio))

      # More compatible format
      assert optimized_video.metadata.format == "MP4"
      # Compressed
      assert optimized_video.metadata.size_mb < 200
      # More compatible format
      assert optimized_audio.metadata.format == "MP3"

      assert result.multimodal_enhancements |> Enum.member?(:video_audio_correlation)
      assert result.optimization_strategy == :preserve_multimodal_richness
    end

    test "creates fallback strategies for unsupported content" do
      content = [
        %{
          type: :video,
          content: "presentation_video",
          # 15-minute presentation
          metadata: %{duration: 900, has_slides: true, has_audio: true}
        }
      ]

      result = ProviderCompatibilityAssessor.optimize_for_provider(content, :anthropic)

      # Should create multiple fallback representations
      fallback_content = result.fallback_representations

      slide_images = fallback_content |> Enum.filter(&(&1.type == :image))

      audio_transcript =
        fallback_content |> Enum.find(&(&1.type == :text && &1.source == :audio_transcript))

      # Key slides extracted
      assert slide_images |> length() >= 5
      assert audio_transcript.content |> String.length() > 100
      assert result.fallback_strategy == :comprehensive_decomposition
      assert result.information_retention_score >= 0.8
    end
  end

  describe "generate_provider_recommendations/1" do
    test "recommends optimal provider for content mix" do
      content = [
        %{type: :text, metadata: %{length: 1000}},
        %{type: :image, metadata: %{size_mb: 5, type: :diagram}},
        %{type: :video, metadata: %{duration: 60, type: :tutorial}},
        %{type: :audio, metadata: %{duration: 120, type: :interview}}
      ]

      recommendations = ProviderCompatibilityAssessor.generate_provider_recommendations(content)

      # Best multimodal support
      assert recommendations.primary_recommendation.provider == :google
      assert recommendations.primary_recommendation.compatibility_score >= 0.9
      assert recommendations.primary_recommendation.reasoning |> String.contains?("video")
      assert recommendations.primary_recommendation.reasoning |> String.contains?("audio")

      fallback_rec = recommendations.fallback_options |> List.first()
      assert fallback_rec.provider == :anthropic
      assert fallback_rec.required_adaptations |> length() >= 2
    end

    test "considers cost factors in recommendations" do
      large_content = [
        # Large text
        %{type: :text, metadata: %{length: 50_000}},
        %{type: :image, metadata: %{size_mb: 8}},
        %{type: :image, metadata: %{size_mb: 9}},
        %{type: :document, metadata: %{pages: 30}}
      ]

      context = %{consider_cost: true, budget_tier: :standard}

      recommendations =
        ProviderCompatibilityAssessor.generate_provider_recommendations(large_content, context)

      assert recommendations.cost_analysis.estimated_tokens > 10_000
      assert recommendations.cost_analysis.cost_by_provider |> Map.keys() |> length() >= 2
      assert recommendations.primary_recommendation.cost_efficiency >= 0.7
      assert recommendations.cost_analysis.budget_considerations.optimization_suggestions |> length() > 0
    end

    test "provides specialized recommendations for different use cases" do
      research_content = [
        %{type: :document, metadata: %{pages: 100, type: :research_paper}},
        %{type: :data, metadata: %{format: :csv, rows: 10_000}}
      ]

      context = %{use_case: :research_analysis, priority: :accuracy}

      recommendations =
        ProviderCompatibilityAssessor.generate_provider_recommendations(research_content, context)

      assert recommendations.use_case_analysis.research_suitability |> is_map()
      assert recommendations.specialized_features.document_analysis_capability >= 0.8
      assert recommendations.primary_recommendation.use_case_alignment >= 0.9
    end
  end

  describe "monitor_provider_performance/2" do
    test "tracks provider performance metrics over time" do
      {:ok, monitor_pid} =
        ProviderCompatibilityAssessor.start_performance_monitoring(%{
          providers: [:anthropic, :google, :openai],
          metrics: [:response_time, :quality_score, :error_rate]
        })

      # Simulate processing sessions
      test_sessions = [
        %{
          provider: :anthropic,
          content_types: [:text, :image],
          response_time_ms: 1500,
          quality: 0.9
        },
        %{
          provider: :google,
          content_types: [:video, :audio],
          response_time_ms: 3000,
          quality: 0.85
        },
        %{
          provider: :anthropic,
          content_types: [:text, :document],
          response_time_ms: 2000,
          quality: 0.95
        }
      ]

      Enum.each(test_sessions, fn session ->
        ProviderCompatibilityAssessor.record_session_metrics(monitor_pid, session)
      end)

      performance_report = ProviderCompatibilityAssessor.get_performance_report(monitor_pid)

      # (1500 + 2000) / 2
      assert performance_report.anthropic.average_response_time_ms == 1750
      assert performance_report.anthropic.average_quality_score >= 0.9
      assert performance_report.google.sessions_processed == 1
      assert performance_report.comparative_analysis.fastest_provider == :anthropic

      ProviderCompatibilityAssessor.stop_performance_monitoring(monitor_pid)
    end

    test "identifies performance trends and anomalies" do
      {:ok, monitor_pid} =
        ProviderCompatibilityAssessor.start_performance_monitoring(%{
          trend_analysis: true,
          anomaly_detection: true
        })

      # Simulate performance degradation
      degrading_sessions =
        Enum.map(1..10, fn i ->
          %{
            provider: :anthropic,
            content_types: [:image],
            # Increasing response time
            response_time_ms: 1000 + i * 200,
            # Decreasing quality
            quality: 0.95 - i * 0.02,
            timestamp: DateTime.utc_now()
          }
        end)

      Enum.each(degrading_sessions, fn session ->
        ProviderCompatibilityAssessor.record_session_metrics(monitor_pid, session)
      end)

      trend_analysis = ProviderCompatibilityAssessor.get_trend_analysis(monitor_pid)

      assert trend_analysis.anthropic.response_time_trend == :increasing
      assert trend_analysis.anthropic.quality_trend == :decreasing
      assert trend_analysis.anomalies_detected |> length() > 0

      assert trend_analysis.recommendations
             |> Enum.any?(&(&1.type == :investigate_performance_degradation))

      ProviderCompatibilityAssessor.stop_performance_monitoring(monitor_pid)
    end
  end

  describe "error handling and edge cases" do
    test "handles unknown provider gracefully" do
      content = [%{type: :text, content: "test"}]

      result =
        ProviderCompatibilityAssessor.assess_provider_compatibility(content, :unknown_provider)

      assert result.status == :error
      assert result.error_type == :unsupported_provider
      assert result.available_providers |> length() >= 3
      assert result.suggestion |> String.contains?("supported providers")
    end

    test "handles malformed content during assessment" do
      malformed_content = [
        %{type: :invalid_type, content: "test"},
        %{content: "missing type field"},
        # missing content field
        %{type: :image}
      ]

      result =
        ProviderCompatibilityAssessor.assess_provider_compatibility(malformed_content, :anthropic)

      assert result.validation_errors |> length() == 3
      assert result.valid_content_items == 0
      assert result.overall_compatibility_score == 0.0
      assert result.processing_status == :completed_with_errors
    end

    test "provides graceful degradation when provider services are unavailable" do
      content = [%{type: :image, content: "test_image"}]

      # Simulate provider service unavailability
      context = %{
        provider_status: %{anthropic: :unavailable, google: :available, openai: :degraded}
      }

      result =
        ProviderCompatibilityAssessor.assess_provider_compatibility(content, :anthropic, context)

      assert result.provider_status == :unavailable
      assert result.fallback_recommendations |> length() >= 1
      fallback = result.fallback_recommendations |> List.first()
      assert fallback.provider == :google
      assert fallback.availability_status == :available
    end
  end
end

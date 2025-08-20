defmodule TheMaestro.Prompts.MultiModalTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal

  # Remove unused aliases - they're not needed in main test file

  describe "content_type_definitions/0" do
    test "defines all supported content types" do
      expected_types = [
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

      assert MultiModal.content_type_definitions() == expected_types
    end
  end

  describe "process_multimodal_content/2" do
    setup do
      multimodal_content = [
        %{
          type: :text,
          content: "Please analyze this bug in the authentication system",
          metadata: %{priority: :high}
        },
        %{
          type: :image,
          content:
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
          metadata: %{filename: "error_screenshot.png", dimensions: %{width: 1920, height: 1080}}
        },
        %{
          type: :code,
          content: "def authenticate(user, password), do: {:ok, user}",
          metadata: %{language: :elixir, file_path: "/lib/auth.ex"}
        }
      ]

      context = %{
        user_id: "test-user",
        session_id: "test-session",
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        accessibility_requirements: [:alt_text, :audio_descriptions],
        performance_constraints: %{max_processing_time_ms: 5000}
      }

      %{content: multimodal_content, context: context}
    end

    test "returns processed multimodal prompt structure", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      assert %{
               processed_content: processed,
               accessibility_enhancements: accessibility,
               cross_modal_analysis: analysis,
               provider_compatibility: compatibility,
               performance_metrics: metrics,
               assembled_prompt: prompt
             } = result

      assert is_list(processed)
      assert is_map(accessibility)
      assert is_map(analysis)
      assert is_map(compatibility)
      assert is_map(metrics)
      assert is_binary(prompt)
    end

    test "processes each content type correctly", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      processed = result.processed_content

      # Verify text content processing
      text_item = Enum.find(processed, &(&1.type == :text))
      assert text_item.processed_content =~ "authentication system"
      assert text_item.analysis.intent == :debugging
      assert text_item.analysis.complexity == :moderate

      # Verify image content processing
      image_item = Enum.find(processed, &(&1.type == :image))
      assert image_item.processed_content.format == :base64
      assert image_item.analysis.visual_elements.detected_ui_elements > 0
      assert image_item.analysis.text_extraction.has_text == true

      # Verify code content processing
      code_item = Enum.find(processed, &(&1.type == :code))
      assert code_item.processed_content.language == :elixir
      assert code_item.analysis.complexity_score < 10
      assert code_item.analysis.security_concerns.has_issues == true
    end

    test "includes accessibility enhancements", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      accessibility = result.accessibility_enhancements

      assert accessibility.alt_texts.image_descriptions |> length() == 1
      assert accessibility.audio_descriptions.content_summaries |> length() == 3
      assert accessibility.structure_clarifications.content_hierarchy |> is_list()
      assert accessibility.navigation_aids.content_index |> is_map()
    end

    test "performs cross-modal analysis", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      analysis = result.cross_modal_analysis

      assert analysis.coherence_score >= 0.0 and analysis.coherence_score <= 1.0
      assert analysis.conflict_detection.conflicts |> length() >= 0
      assert analysis.information_gaps.missing_context |> is_list()
      assert analysis.synthesis_opportunities.enhancement_suggestions |> is_list()
      assert analysis.priority_ranking.ordered_content |> length() == 3
    end

    test "assesses provider compatibility", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      compatibility = result.provider_compatibility

      assert compatibility.anthropic.supports_images == true
      assert compatibility.anthropic.max_image_size > 0
      assert compatibility.anthropic.supported_formats |> is_list()
      assert compatibility.quality_impact.overall_score >= 0.0
    end

    test "tracks performance metrics", %{content: content, context: context} do
      result = MultiModal.process_multimodal_content(content, context)

      metrics = result.performance_metrics

      assert metrics.processing_time_ms > 0
      assert metrics.content_processing_times |> is_map()
      assert metrics.memory_usage_mb >= 0
      assert metrics.optimization_applied |> is_list()
    end

    test "handles empty content list gracefully" do
      result = MultiModal.process_multimodal_content([], %{})

      assert result.processed_content == []
      assert result.assembled_prompt == ""
    end
  end

  describe "validate_content_structure/1" do
    test "validates valid content structure" do
      valid_content = [
        %{
          type: :text,
          content: "Test content",
          metadata: %{}
        }
      ]

      assert {:ok, valid_content} == MultiModal.validate_content_structure(valid_content)
    end

    test "rejects content with missing required fields" do
      invalid_content = [
        %{
          type: :text
          # missing content field
        }
      ]

      assert {:error, reason} = MultiModal.validate_content_structure(invalid_content)
      assert reason =~ "missing required field: content"
    end

    test "rejects unsupported content types" do
      invalid_content = [
        %{
          type: :unsupported_type,
          content: "Test content",
          metadata: %{}
        }
      ]

      assert {:error, reason} = MultiModal.validate_content_structure(invalid_content)
      assert reason =~ "unsupported content type: unsupported_type"
    end
  end

  describe "estimate_processing_complexity/1" do
    test "estimates complexity for different content types" do
      content = [
        %{type: :text, content: "Simple text"},
        %{type: :image, content: "base64_encoded_image_data", metadata: %{size_kb: 500}},
        %{type: :video, content: "video_data", metadata: %{duration_seconds: 120}}
      ]

      complexity = MultiModal.estimate_processing_complexity(content)

      assert complexity.overall_score >= 0.0 and complexity.overall_score <= 1.0
      assert complexity.text_complexity == :low
      assert complexity.image_complexity == :moderate
      assert complexity.video_complexity == :high
      assert complexity.estimated_processing_time_ms > 1000
    end

    test "handles empty content" do
      complexity = MultiModal.estimate_processing_complexity([])

      assert complexity.overall_score == 0.0
      assert complexity.estimated_processing_time_ms == 0
    end
  end

  describe "optimize_for_provider/2" do
    test "optimizes content for Anthropic Claude" do
      content = [
        %{type: :image, content: "large_image_data", metadata: %{size_mb: 15}}
      ]

      optimized = MultiModal.optimize_for_provider(content, :anthropic)

      assert optimized.modifications_applied |> length() > 0
      compressed_image = Enum.find(optimized.content, &(&1.type == :image))
      assert compressed_image.metadata.size_mb < 15
    end

    test "optimizes content for Google Gemini" do
      content = [
        %{type: :video, content: "video_data", metadata: %{format: "mov"}}
      ]

      optimized = MultiModal.optimize_for_provider(content, :google)

      # Gemini might convert video to image frames
      assert optimized.modifications_applied |> Enum.any?(&(&1.type == :format_conversion))
    end

    test "handles unsupported providers gracefully" do
      content = [%{type: :text, content: "test"}]

      optimized = MultiModal.optimize_for_provider(content, :unknown_provider)

      assert optimized.content == content
      assert optimized.modifications_applied == []
      assert optimized.warnings |> Enum.any?(&(&1 =~ "unsupported provider"))
    end
  end

  describe "generate_accessibility_report/2" do
    test "generates comprehensive accessibility report" do
      content = [
        %{type: :image, content: "image_data", metadata: %{alt_text: nil}},
        %{type: :audio, content: "audio_data", metadata: %{transcript: nil}}
      ]

      report = MultiModal.generate_accessibility_report(content, [:wcag_aa])

      assert report.compliance_level == :wcag_aa
      # Missing alt_text and transcript
      assert report.issues_found |> length() >= 2
      assert report.recommendations |> length() >= 2
      assert report.severity_breakdown.critical >= 0
      assert report.estimated_fix_time_hours > 0
    end

    test "reports full compliance when all requirements met" do
      content = [
        %{type: :image, content: "image_data", metadata: %{alt_text: "Descriptive text"}},
        %{type: :audio, content: "audio_data", metadata: %{transcript: "Full transcript"}}
      ]

      report = MultiModal.generate_accessibility_report(content, [:wcag_aa])

      assert report.compliance_score == 1.0
      assert report.issues_found == []
    end
  end

  describe "merge_multimodal_contexts/2" do
    test "merges multiple multimodal contexts coherently" do
      context1 = [
        %{type: :text, content: "First part of the story"}
      ]

      context2 = [
        %{type: :text, content: "Second part of the story"},
        %{type: :image, content: "supporting_image"}
      ]

      merged = MultiModal.merge_multimodal_contexts(context1, context2)

      assert merged.merged_content |> length() == 3
      assert merged.coherence_analysis.narrative_flow_score >= 0.0
      assert merged.conflict_resolution.resolved_conflicts |> is_list()
      assert merged.optimization_suggestions |> is_list()
    end
  end

  describe "error handling" do
    test "handles corrupted content gracefully" do
      corrupted_content = [
        %{type: :image, content: "invalid_base64_data", metadata: %{}}
      ]

      result = MultiModal.process_multimodal_content(corrupted_content, %{})

      assert result.processed_content |> length() == 1
      processed = result.processed_content |> List.first()
      assert processed.processing_status == :error
      assert processed.error_details.type == :content_corruption
    end

    test "handles processing timeouts" do
      large_content = [
        %{type: :video, content: "very_large_video_data", metadata: %{size_gb: 5}}
      ]

      context = %{performance_constraints: %{max_processing_time_ms: 100}}

      result = MultiModal.process_multimodal_content(large_content, context)

      assert result.performance_metrics.timeout_occurred == true
      assert result.performance_metrics.partial_processing == true
    end
  end
end

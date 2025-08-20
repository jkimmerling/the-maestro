defmodule TheMaestro.Prompts.MultiModal.Processors.ContentProcessorTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal.Processors.ContentProcessor

  alias TheMaestro.Prompts.MultiModal.Processors.{
    ImageProcessor,
    AudioProcessor,
    DocumentProcessor,
    VideoProcessor,
    CodeProcessor,
    DataProcessor
  }

  describe "process_content/2" do
    test "delegates to appropriate processor based on content type" do
      text_content = %{type: :text, content: "Hello world"}
      image_content = %{type: :image, content: "base64_image_data"}
      audio_content = %{type: :audio, content: "audio_binary_data"}

      text_result = ContentProcessor.process_content(text_content, %{})
      image_result = ContentProcessor.process_content(image_content, %{})
      audio_result = ContentProcessor.process_content(audio_content, %{})

      assert text_result.processor_used == :text_processor
      assert image_result.processor_used == :image_processor
      assert audio_result.processor_used == :audio_processor
    end

    test "returns error for unsupported content types" do
      unsupported_content = %{type: :unsupported, content: "data"}

      result = ContentProcessor.process_content(unsupported_content, %{})

      assert result.status == :error
      assert result.error == :unsupported_content_type
    end
  end

  describe "ImageProcessor" do
    test "processes image content with visual analysis" do
      image_content = %{
        type: :image,
        content:
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
        metadata: %{filename: "test.png"}
      }

      result = ImageProcessor.process(image_content, %{})

      assert result.visual_analysis.detected_elements |> is_list()
      assert result.visual_analysis.dominant_colors |> is_list()
      assert result.visual_analysis.scene_classification.category |> is_binary()
      assert result.text_extraction.ocr_text |> is_binary()
      assert result.accessibility.alt_text_generated |> is_binary()
      assert result.technical_metadata.dimensions.width > 0
      assert result.technical_metadata.format == "PNG"
    end

    test "handles screenshot analysis" do
      screenshot_content = %{
        type: :image,
        content: "screenshot_data",
        metadata: %{context: :screenshot, application: "web_browser"}
      }

      result = ImageProcessor.process(screenshot_content, %{})

      assert result.screenshot_analysis.ui_elements.buttons |> is_list()
      assert result.screenshot_analysis.ui_elements.text_fields |> is_list()
      assert result.screenshot_analysis.error_detection.errors_found |> is_list()
      assert result.screenshot_analysis.workflow_context.detected_workflow |> is_binary()
    end

    test "detects code in images" do
      code_image_content = %{
        type: :image,
        content: "image_with_code",
        metadata: %{context: :code_screenshot}
      }

      result = ImageProcessor.process(code_image_content, %{})

      assert result.code_detection.has_code == true
      assert result.code_detection.detected_languages |> is_list()
      assert result.code_detection.syntax_highlighting.applied == true
      assert result.code_extraction.extracted_code |> is_binary()
    end
  end

  describe "AudioProcessor" do
    test "processes audio content with transcription" do
      audio_content = %{
        type: :audio,
        content: "binary_audio_data",
        metadata: %{format: "wav", duration: 60.5}
      }

      result = AudioProcessor.process(audio_content, %{})

      assert result.transcription.text |> is_binary()
      assert result.transcription.confidence_score >= 0.0
      assert result.transcription.word_timestamps |> is_list()
      assert result.speaker_analysis.speaker_count >= 1
      assert result.audio_analysis.sentiment.overall_sentiment |> is_atom()
      assert result.content_classification.category |> is_binary()
      assert result.accessibility.transcript_enhanced |> is_binary()
    end

    test "handles voice command detection" do
      voice_command_content = %{
        type: :audio,
        content: "voice_command_audio",
        metadata: %{context: :voice_command}
      }

      result = AudioProcessor.process(voice_command_content, %{})

      assert result.command_detection.is_command == true
      assert result.command_detection.command_intent |> is_binary()
      assert result.command_detection.parameters |> is_map()
    end
  end

  describe "DocumentProcessor" do
    test "processes PDF documents" do
      pdf_content = %{
        type: :document,
        content: "pdf_binary_data",
        metadata: %{format: "pdf", pages: 10}
      }

      result = DocumentProcessor.process(pdf_content, %{})

      assert result.text_extraction.full_text |> is_binary()
      assert result.structure_analysis.headings |> is_list()
      assert result.structure_analysis.sections |> is_list()
      assert result.metadata_extraction.title |> is_binary()
      assert result.content_summary.key_points |> is_list()
      assert result.accessibility.structure_tags |> is_map()
    end

    test "processes Word documents" do
      docx_content = %{
        type: :document,
        content: "docx_binary_data",
        metadata: %{format: "docx"}
      }

      result = DocumentProcessor.process(docx_content, %{})

      assert result.text_extraction.full_text |> is_binary()
      assert result.formatting_analysis.styles_used |> is_list()
      assert result.revision_tracking.has_revisions |> is_boolean()
    end
  end

  describe "VideoProcessor" do
    test "processes video content with frame analysis" do
      video_content = %{
        type: :video,
        content: "video_binary_data",
        metadata: %{format: "mp4", duration: 120.0, fps: 30}
      }

      result = VideoProcessor.process(video_content, %{})

      assert result.frame_analysis.key_frames |> is_list()
      assert result.scene_detection.scenes |> is_list()
      assert result.motion_analysis.motion_vectors |> is_list()
      assert result.audio_track.transcription |> is_binary()
      assert result.video_summary.description |> is_binary()
      assert result.accessibility.video_description |> is_binary()
    end

    test "handles screen recording analysis" do
      screen_recording_content = %{
        type: :video,
        content: "screen_recording_data",
        metadata: %{context: :screen_recording}
      }

      result = VideoProcessor.process(screen_recording_content, %{})

      assert result.screen_analysis.applications_detected |> is_list()
      assert result.screen_analysis.user_actions |> is_list()
      assert result.workflow_detection.workflow_steps |> is_list()
    end
  end

  describe "CodeProcessor" do
    test "processes code content with syntax analysis" do
      code_content = %{
        type: :code,
        content: "def hello_world, do: IO.puts(\"Hello, World!\")",
        metadata: %{language: :elixir, file_path: "/lib/hello.ex"}
      }

      result = CodeProcessor.process(code_content, %{})

      assert result.syntax_analysis.is_valid == true
      assert result.syntax_analysis.language_detected == :elixir
      assert result.complexity_analysis.cyclomatic_complexity >= 1
      assert result.security_analysis.vulnerabilities |> is_list()
      assert result.style_analysis.style_issues |> is_list()
      assert result.documentation_extraction.comments |> is_list()
      assert result.code_enhancement.suggestions |> is_list()
    end

    test "detects code patterns and antipatterns" do
      complex_code_content = %{
        type: :code,
        content: """
        def complex_function(x) do
          if x > 10 do
            if x < 20 do
              if rem(x, 2) == 0 do
                "even"
              else
                "odd"
              end
            else
              "large"
            end
          else
            "small"
          end
        end
        """,
        metadata: %{language: :elixir}
      }

      result = CodeProcessor.process(complex_code_content, %{})

      assert result.pattern_detection.patterns_found |> length() > 0
      assert result.pattern_detection.antipatterns |> length() > 0
      assert result.complexity_analysis.nesting_depth > 3
    end
  end

  describe "DataProcessor" do
    test "processes JSON data" do
      json_content = %{
        type: :data,
        content: "{\"users\": [{\"name\": \"Alice\", \"age\": 30}]}",
        metadata: %{format: :json}
      }

      result = DataProcessor.process(json_content, %{})

      assert result.structure_analysis.schema |> is_map()
      assert result.validation.is_valid == true
      assert result.content_summary.record_count == 1
      assert result.data_quality.completeness_score >= 0.0
      assert result.accessibility.table_headers |> is_list()
    end

    test "processes CSV data" do
      csv_content = %{
        type: :data,
        content: "name,age,city\nAlice,30,New York\nBob,25,San Francisco",
        metadata: %{format: :csv}
      }

      result = DataProcessor.process(csv_content, %{})

      assert result.structure_analysis.columns |> length() == 3
      assert result.structure_analysis.row_count == 2
      assert result.data_types.inferred_types |> is_map()
      assert result.statistical_analysis.summary_stats |> is_map()
    end
  end

  describe "performance optimization" do
    test "applies lazy loading for large content" do
      large_content = %{
        type: :image,
        content: String.duplicate("large_image_data", 10_000),
        metadata: %{size_mb: 50}
      }

      context = %{performance_mode: :optimized}

      result = ContentProcessor.process_content(large_content, context)

      assert result.optimization_applied.lazy_loading.enabled == true
      assert result.performance_metrics.memory_saved_mb > 0
    end

    test "enables parallel processing for multiple items" do
      content_items =
        Enum.map(1..10, fn i ->
          %{type: :text, content: "Content item #{i}"}
        end)

      context = %{processing_mode: :parallel}

      results = ContentProcessor.process_batch(content_items, context)

      assert results.parallel_processing == true
      # Should be faster than sequential
      assert results.processing_time_ms < length(content_items) * 100
    end
  end

  describe "error handling" do
    test "handles malformed content gracefully" do
      malformed_content = %{
        type: :image,
        content: "not_valid_image_data"
      }

      result = ContentProcessor.process_content(malformed_content, %{})

      assert result.status == :error
      assert result.error_details.type == :content_malformed
      assert result.fallback_processing.attempted == true
    end

    test "provides detailed error information for debugging" do
      problematic_content = %{
        type: :code,
        content: "invalid syntax here ::::"
      }

      result = ContentProcessor.process_content(problematic_content, %{})

      assert result.error_details.line_number |> is_integer()
      assert result.error_details.column_number |> is_integer()
      assert result.error_details.error_message |> is_binary()
      assert result.debugging_hints |> is_list()
    end
  end
end

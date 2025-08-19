defmodule TheMaestro.Prompts.MultiModal.Accessibility.AccessibilityEnhancerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal.Accessibility.AccessibilityEnhancer

  describe "enhance_content_accessibility/2" do
    test "generates comprehensive alt-text for images" do
      image_content = %{
        type: :image,
        content: "screenshot_data",
        processed_content: %{
          visual_analysis: %{
            detected_elements: [:button, :text_field, :error_message],
            dominant_colors: [:red, :white, :black],
            scene_classification: %{category: "error_dialog"}
          },
          text_extraction: %{ocr_text: "Authentication Failed: Invalid credentials"}
        }
      }

      requirements = [:alt_text, :descriptive_text]

      result = AccessibilityEnhancer.enhance_content_accessibility([image_content], requirements)

      alt_text = result.enhancements.alt_text |> List.first()
      assert alt_text.content_id == image_content
      assert alt_text.alt_text =~ "error dialog"
      assert alt_text.alt_text =~ "Authentication Failed"
      # Detailed description
      assert alt_text.descriptive_detail |> String.length() > 50
      assert alt_text.wcag_compliance.level == :aa
    end

    test "creates audio descriptions for video content" do
      video_content = %{
        type: :video,
        content: "demo_video_data",
        processed_content: %{
          frame_analysis: %{
            key_frames: [
              %{timestamp: 0.0, description: "Application launch screen"},
              %{timestamp: 10.5, description: "User clicks login button"},
              %{timestamp: 25.0, description: "Error message appears"}
            ]
          },
          audio_track: %{transcription: "Now I'll demonstrate the login process"}
        }
      }

      requirements = [:audio_descriptions, :video_captions]

      result = AccessibilityEnhancer.enhance_content_accessibility([video_content], requirements)

      audio_desc = result.enhancements.audio_descriptions |> List.first()
      assert audio_desc.content_id == video_content
      # One for each key frame
      assert audio_desc.descriptions |> length() >= 3
      assert audio_desc.timing_synchronized == true
      assert audio_desc.descriptions |> Enum.all?(&(String.length(&1.description) > 10))
    end

    test "enhances document structure for screen readers" do
      document_content = %{
        type: :document,
        content: "pdf_data",
        processed_content: %{
          structure_analysis: %{
            headings: [
              %{level: 1, text: "Introduction", page: 1},
              %{level: 2, text: "Authentication Methods", page: 2},
              %{level: 3, text: "OAuth Implementation", page: 3}
            ],
            sections: [:introduction, :auth_methods, :oauth_details]
          }
        }
      }

      requirements = [:structure_tags, :navigation_aids]

      result =
        AccessibilityEnhancer.enhance_content_accessibility([document_content], requirements)

      structure = result.enhancements.structure_enhancements |> List.first()
      assert structure.heading_hierarchy |> length() == 3
      assert structure.navigation_landmarks.main_sections |> length() == 3
      assert structure.reading_order.logical_sequence == true
      assert structure.accessibility_tree.properly_nested == true
    end

    test "creates transcripts for audio content" do
      audio_content = %{
        type: :audio,
        content: "meeting_audio",
        processed_content: %{
          transcription: %{
            text: "Welcome everyone to today's standup meeting",
            word_timestamps: [
              %{word: "Welcome", start: 0.0, end: 0.8},
              %{word: "everyone", start: 0.8, end: 1.5}
            ]
          },
          speaker_analysis: %{
            speakers: [
              %{id: 1, name: "Alice", segments: [{0.0, 5.0}]},
              %{id: 2, name: "Bob", segments: [{5.0, 10.0}]}
            ]
          }
        }
      }

      requirements = [:transcripts, :speaker_identification]

      result = AccessibilityEnhancer.enhance_content_accessibility([audio_content], requirements)

      transcript = result.enhancements.transcripts |> List.first()
      assert transcript.formatted_text |> String.contains?("Alice:")
      assert transcript.formatted_text |> String.contains?("Bob:")
      assert transcript.timestamps_included == true
      assert transcript.speaker_identified == true
      assert transcript.quality_score >= 0.8
    end
  end

  describe "validate_wcag_compliance/2" do
    test "validates WCAG AA compliance for images" do
      image_with_alt = %{
        type: :image,
        accessibility_enhancements: %{
          alt_text: "Error dialog showing authentication failure message",
          color_contrast: %{ratio: 4.5, passes_aa: true}
        }
      }

      result = AccessibilityEnhancer.validate_wcag_compliance([image_with_alt], :aa)

      compliance = result.compliance_results |> List.first()
      assert compliance.wcag_level == :aa
      assert compliance.passes_compliance == true
      assert compliance.criteria_met.images_have_alt_text == true
      assert compliance.criteria_met.color_contrast_sufficient == true
    end

    test "identifies WCAG violations" do
      non_compliant_image = %{
        type: :image,
        accessibility_enhancements: %{
          # Empty alt text
          alt_text: "",
          # Insufficient contrast
          color_contrast: %{ratio: 2.1, passes_aa: false}
        }
      }

      result = AccessibilityEnhancer.validate_wcag_compliance([non_compliant_image], :aa)

      compliance = result.compliance_results |> List.first()
      assert compliance.passes_compliance == false
      assert compliance.violations |> Enum.any?(&(&1.criterion == :alt_text_missing))
      assert compliance.violations |> Enum.any?(&(&1.criterion == :color_contrast_insufficient))
      assert compliance.remediation_suggestions |> length() >= 2
    end

    test "validates AAA compliance requirements" do
      content_aaa = %{
        type: :video,
        accessibility_enhancements: %{
          captions: %{synchronized: true, accurate: true},
          audio_descriptions: %{comprehensive: true, well_timed: true},
          # AAA requirement
          sign_language: %{provided: true}
        }
      }

      result = AccessibilityEnhancer.validate_wcag_compliance([content_aaa], :aaa)

      compliance = result.compliance_results |> List.first()
      assert compliance.wcag_level == :aaa
      assert compliance.criteria_met.sign_language_provided == true
      assert compliance.overall_score >= 0.9
    end
  end

  describe "generate_cognitive_accessibility_aids/1" do
    test "creates simplified language versions" do
      complex_content = %{
        type: :text,
        content:
          "Utilize the authentication mechanism to establish secure credentials validation",
        processed_content: %{complexity_score: 0.8, reading_level: :graduate}
      }

      result = AccessibilityEnhancer.generate_cognitive_accessibility_aids([complex_content])

      simplified = result.cognitive_aids |> List.first()
      assert simplified.simplified_language |> String.contains?("login")
      assert simplified.reading_level == :middle_school
      assert simplified.complexity_reduction_score > 0.5
      assert simplified.key_concepts |> length() >= 2
    end

    test "provides content structure clarification" do
      structured_content = %{
        type: :document,
        processed_content: %{
          structure_analysis: %{
            sections: [:intro, :methods, :results, :conclusion],
            complexity: :high
          }
        }
      }

      result = AccessibilityEnhancer.generate_cognitive_accessibility_aids([structured_content])

      structure_aid = result.structure_clarifications |> List.first()
      assert structure_aid.content_outline |> length() == 4
      assert structure_aid.section_summaries |> Map.has_key?(:intro)
      assert structure_aid.reading_path.recommended_order |> is_list()
      assert structure_aid.estimated_reading_time > 0
    end

    test "creates memory aids and navigation helpers" do
      multi_part_content = [
        %{type: :text, content: "Part 1: Setup"},
        %{type: :text, content: "Part 2: Configuration"},
        %{type: :text, content: "Part 3: Testing"}
      ]

      result = AccessibilityEnhancer.generate_cognitive_accessibility_aids(multi_part_content)

      memory_aids = result.memory_aids
      assert memory_aids.progress_indicators |> length() == 3
      assert memory_aids.content_index.sections |> length() == 3
      assert memory_aids.quick_reference.key_points |> length() >= 3
      assert memory_aids.navigation_breadcrumbs |> is_list()
    end
  end

  describe "enhance_motor_accessibility/1" do
    test "provides keyboard navigation alternatives for interactive content" do
      interactive_content = %{
        type: :image,
        processed_content: %{
          screenshot_analysis: %{
            ui_elements: %{
              buttons: [%{text: "Submit", clickable: true}],
              links: [%{text: "Learn More", href: "/docs"}],
              form_fields: [%{type: "text", label: "Username"}]
            }
          }
        }
      }

      result = AccessibilityEnhancer.enhance_motor_accessibility([interactive_content])

      motor_aids = result.motor_accessibility_aids |> List.first()
      assert motor_aids.keyboard_alternatives.tab_order |> length() >= 3
      assert motor_aids.keyboard_alternatives.shortcuts |> Map.has_key?(:submit_button)
      assert motor_aids.focus_indicators.visible == true
      assert motor_aids.target_sizes.all_sufficient == true
    end

    test "suggests voice control alternatives" do
      complex_interface = %{
        type: :image,
        processed_content: %{
          screenshot_analysis: %{
            ui_elements: %{
              interactive_count: 15,
              complex_controls: [:dropdown, :slider, :color_picker]
            }
          }
        }
      }

      result = AccessibilityEnhancer.enhance_motor_accessibility([complex_interface])

      voice_aids = result.voice_control_aids |> List.first()
      assert voice_aids.voice_commands |> length() >= 10
      assert voice_aids.command_patterns.navigation |> is_list()
      assert voice_aids.command_patterns.actions |> is_list()
      assert voice_aids.disambiguation_strategies |> is_list()
    end
  end

  describe "generate_accessibility_report/2" do
    test "creates comprehensive accessibility assessment" do
      mixed_content = [
        %{
          type: :image,
          accessibility_enhancements: %{alt_text: "Good alt text"},
          wcag_compliance: %{level: :aa, passes: true}
        },
        %{
          type: :video,
          # Missing captions
          accessibility_enhancements: %{captions: nil},
          wcag_compliance: %{level: :aa, passes: false}
        },
        %{
          type: :audio,
          accessibility_enhancements: %{transcript: "Full transcript available"},
          wcag_compliance: %{level: :aa, passes: true}
        }
      ]

      report = AccessibilityEnhancer.generate_accessibility_report(mixed_content, :aa)

      # Partial compliance
      assert report.overall_compliance_score > 0.5
      assert report.compliant_items == 2
      assert report.non_compliant_items == 1
      assert report.compliance_breakdown.images.compliant == 1
      assert report.compliance_breakdown.videos.compliant == 0
      assert report.compliance_breakdown.audio.compliant == 1

      assert report.priority_issues |> length() >= 1
      priority_issue = report.priority_issues |> List.first()
      assert priority_issue.content_type == :video
      assert priority_issue.issue_type == :missing_captions
      assert priority_issue.severity == :high

      assert report.remediation_plan.immediate_actions |> length() >= 1
      assert report.remediation_plan.estimated_effort_hours > 0
    end

    test "provides actionable improvement recommendations" do
      low_accessibility_content = [
        %{
          type: :image,
          accessibility_enhancements: %{alt_text: ""},
          wcag_compliance: %{passes: false, violations: [:alt_text_missing]}
        }
      ]

      report = AccessibilityEnhancer.generate_accessibility_report(low_accessibility_content, :aa)

      recommendations = report.improvement_recommendations
      assert recommendations |> length() >= 1

      alt_text_rec = recommendations |> Enum.find(&(&1.category == :alt_text))
      assert alt_text_rec.priority == :high
      assert alt_text_rec.implementation_steps |> length() >= 2
      assert alt_text_rec.resources.tools |> is_list()
      assert alt_text_rec.estimated_impact == :high
    end
  end

  describe "real-time accessibility monitoring" do
    test "monitors accessibility during content processing" do
      {:ok, monitor_pid} =
        AccessibilityEnhancer.start_accessibility_monitoring(%{wcag_level: :aa})

      test_content = %{
        type: :image,
        processing_stage: :visual_analysis,
        accessibility_data: %{alt_text_generated: false}
      }

      AccessibilityEnhancer.monitor_content_processing(monitor_pid, test_content)

      status = AccessibilityEnhancer.get_monitoring_status(monitor_pid)
      assert status.items_monitored == 1
      assert status.accessibility_issues_detected >= 1
      assert status.real_time_suggestions |> is_list()

      AccessibilityEnhancer.stop_accessibility_monitoring(monitor_pid)
    end

    test "provides progressive accessibility enhancement suggestions" do
      {:ok, monitor_pid} =
        AccessibilityEnhancer.start_accessibility_monitoring(%{
          enhancement_mode: :progressive,
          wcag_level: :aa
        })

      content_stream = [
        %{type: :text, accessibility_score: 0.9},
        # Low score triggers enhancement
        %{type: :image, accessibility_score: 0.3},
        %{type: :video, accessibility_score: 0.6}
      ]

      Enum.each(content_stream, fn content ->
        AccessibilityEnhancer.monitor_content_processing(monitor_pid, content)
      end)

      suggestions = AccessibilityEnhancer.get_progressive_suggestions(monitor_pid)
      assert suggestions.priority_enhancements |> length() >= 1
      assert suggestions.quick_wins |> length() >= 1
      assert suggestions.long_term_improvements |> is_list()

      AccessibilityEnhancer.stop_accessibility_monitoring(monitor_pid)
    end
  end

  describe "performance optimization" do
    test "optimizes accessibility processing for large content sets" do
      large_content_set =
        Enum.map(1..100, fn i ->
          %{
            type: Enum.random([:text, :image, :audio]),
            content: "Content item #{i}",
            processed_content: %{complexity_score: :rand.uniform()}
          }
        end)

      start_time = System.monotonic_time(:millisecond)
      result = AccessibilityEnhancer.enhance_content_accessibility(large_content_set, [:alt_text])
      end_time = System.monotonic_time(:millisecond)

      processing_time = end_time - start_time

      assert result.enhancements |> Map.keys() |> length() > 0
      # Should complete within 10 seconds
      assert processing_time < 10_000
      assert result.performance_metrics.items_processed == 100
      assert result.performance_metrics.parallel_processing == true
    end

    test "supports batch processing with priority queuing" do
      priority_content = [
        %{type: :image, priority: :critical, accessibility_score: 0.1},
        %{type: :video, priority: :high, accessibility_score: 0.3},
        %{type: :text, priority: :normal, accessibility_score: 0.8}
      ]

      result =
        AccessibilityEnhancer.process_with_priority_queue(priority_content, [:alt_text, :captions])

      processing_order = result.processing_order
      assert processing_order |> List.first() |> Map.get(:priority) == :critical
      assert processing_order |> List.last() |> Map.get(:priority) == :normal

      assert result.batch_metrics.priority_adherence == 1.0
      assert result.batch_metrics.efficiency_score >= 0.8
    end
  end

  describe "error handling and resilience" do
    test "gracefully handles malformed content during accessibility enhancement" do
      malformed_content = [
        # Invalid content
        %{type: :image, content: nil},
        # Valid content
        %{type: :text, content: "Valid text"}
      ]

      result = AccessibilityEnhancer.enhance_content_accessibility(malformed_content, [:alt_text])

      # Only valid item processed
      assert result.error_recovery.items_processed == 1
      assert result.error_recovery.errors_handled == 1
      # No alt text for invalid image
      assert result.enhancements.alt_text |> length() == 0
      assert result.processing_warnings |> Enum.any?(&(&1 =~ "malformed content"))
    end

    test "provides fallback accessibility enhancements when primary methods fail" do
      problematic_content = %{
        type: :image,
        content: "corrupted_image_data",
        processing_errors: [:visual_analysis_failed, :ocr_failed]
      }

      result =
        AccessibilityEnhancer.enhance_content_accessibility([problematic_content], [:alt_text])

      fallback = result.fallback_enhancements |> List.first()
      assert fallback.primary_method_failed == true
      assert fallback.fallback_method_used |> is_atom()
      # Basic alt text provided
      assert fallback.fallback_alt_text |> is_binary()
      # Lower quality due to fallback
      assert fallback.quality_score < 0.7
    end
  end
end

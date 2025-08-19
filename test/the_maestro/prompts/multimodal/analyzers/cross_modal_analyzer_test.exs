defmodule TheMaestro.Prompts.MultiModal.Analyzers.CrossModalAnalyzerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal.Analyzers.CrossModalAnalyzer

  describe "analyze_content_coherence/1" do
    test "analyzes coherence between text and image content" do
      content = [
        %{
          type: :text,
          content: "This screenshot shows an authentication error",
          processed_content: %{intent: :debugging, topics: [:authentication, :error]}
        },
        %{
          type: :image,
          content: "screenshot_data",
          processed_content: %{
            visual_analysis: %{scene_classification: %{category: "error_dialog"}},
            text_extraction: %{ocr_text: "Authentication Failed"}
          }
        }
      ]

      result = CrossModalAnalyzer.analyze_content_coherence(content)

      assert result.coherence_score >= 0.8  # High coherence expected
      assert result.supporting_relationships |> length() > 0
      assert result.topic_alignment.shared_topics |> Enum.member?(:authentication)
      assert result.narrative_consistency.consistent == true
    end

    test "detects conflicting information across modalities" do
      content = [
        %{
          type: :text,
          content: "The system is working perfectly",
          processed_content: %{sentiment: :positive, topics: [:system_status]}
        },
        %{
          type: :image,
          content: "error_screenshot",
          processed_content: %{
            visual_analysis: %{scene_classification: %{category: "error_page"}},
            text_extraction: %{ocr_text: "500 Internal Server Error"}
          }
        }
      ]

      result = CrossModalAnalyzer.analyze_content_coherence(content)

      assert result.coherence_score < 0.5  # Low coherence due to conflict
      assert result.conflicts_detected |> length() > 0
      conflict = result.conflicts_detected |> List.first()
      assert conflict.type == :sentiment_mismatch
      assert conflict.severity == :high
    end

    test "analyzes temporal consistency in sequential content" do
      content = [
        %{
          type: :text,
          content: "Step 1: Click the login button",
          processed_content: %{sequence_indicator: 1, action_type: :instruction}
        },
        %{
          type: :image,
          content: "login_screenshot",
          processed_content: %{
            screenshot_analysis: %{ui_elements: %{buttons: [%{text: "Login", state: "normal"}]}}
          }
        },
        %{
          type: :text,
          content: "Step 2: Enter credentials",
          processed_content: %{sequence_indicator: 2, action_type: :instruction}
        },
        %{
          type: :image,
          content: "credentials_screenshot",
          processed_content: %{
            screenshot_analysis: %{ui_elements: %{text_fields: [%{type: "password", filled: true}]}}
          }
        }
      ]

      result = CrossModalAnalyzer.analyze_content_coherence(content)

      assert result.temporal_consistency.sequence_valid == true
      assert result.temporal_consistency.logical_flow_score >= 0.8
      assert result.workflow_coherence.step_completion_rate == 1.0
    end
  end

  describe "detect_information_gaps/1" do
    test "identifies missing context between related content items" do
      content = [
        %{
          type: :text,
          content: "The error occurs when processing the file",
          processed_content: %{references: [:file_processing, :error], specificity: :vague}
        },
        %{
          type: :code,
          content: "def process_file(file), do: File.read!(file)",
          processed_content: %{functions: [:process_file], error_handling: :none}
        }
      ]

      result = CrossModalAnalyzer.detect_information_gaps(content)

      gaps = result.identified_gaps

      assert gaps |> Enum.any?(&(&1.type == :missing_error_details))
      assert gaps |> Enum.any?(&(&1.type == :missing_file_specification))
      assert result.gap_severity.critical > 0
      assert result.completion_suggestions |> length() > 0
    end

    test "detects missing visual evidence for claims" do
      content = [
        %{
          type: :text,
          content: "As you can see in the screenshot, the button is disabled",
          processed_content: %{visual_references: [:screenshot, :button_state]}
        }
        # No corresponding image content
      ]

      result = CrossModalAnalyzer.detect_information_gaps(content)

      gap = result.identified_gaps |> Enum.find(&(&1.type == :missing_visual_evidence))
      assert gap != nil
      assert gap.severity == :high
      assert gap.description =~ "screenshot"
    end

    test "identifies incomplete workflows" do
      content = [
        %{
          type: :text,
          content: "Step 1: Open the application",
          processed_content: %{workflow_step: 1, action_type: :instruction}
        },
        %{
          type: :text,
          content: "Step 3: Click submit",
          processed_content: %{workflow_step: 3, action_type: :instruction}
        }
        # Missing Step 2
      ]

      result = CrossModalAnalyzer.detect_information_gaps(content)

      gap = result.identified_gaps |> Enum.find(&(&1.type == :missing_workflow_step))
      assert gap != nil
      assert gap.missing_step == 2
      assert gap.context == :workflow_sequence
    end
  end

  describe "find_synthesis_opportunities/1" do
    test "identifies opportunities to combine complementary content" do
      content = [
        %{
          type: :text,
          content: "The authentication function has security issues",
          processed_content: %{topics: [:authentication, :security], specificity: :general}
        },
        %{
          type: :code,
          content: "def authenticate(user, pass), do: user == \"admin\" && pass == \"123\"",
          processed_content: %{
            security_analysis: %{vulnerabilities: [:hardcoded_credentials, :weak_authentication]},
            functions: [:authenticate]
          }
        },
        %{
          type: :image,
          content: "security_audit_report",
          processed_content: %{
            text_extraction: %{ocr_text: "High Risk: Hardcoded passwords detected"}
          }
        }
      ]

      result = CrossModalAnalyzer.find_synthesis_opportunities(content)

      opportunities = result.synthesis_opportunities

      security_synthesis = opportunities |> Enum.find(&(&1.topic == :security_analysis))
      assert security_synthesis != nil
      assert security_synthesis.content_items |> length() == 3
      assert security_synthesis.synthesis_type == :comprehensive_analysis
      assert security_synthesis.potential_value == :high

      assert result.enhancement_suggestions |> Enum.any?(&(&1.type == :create_security_summary))
    end

    test "identifies cross-reference opportunities" do
      content = [
        %{
          type: :text,
          content: "The bug is in line 42 of auth.ex",
          processed_content: %{references: [%{type: :file_location, file: "auth.ex", line: 42}]}
        },
        %{
          type: :code,
          content: "# Line 42\ndef verify_token(token), do: token == \"valid\"",
          processed_content: %{
            line_number: 42,
            functions: [:verify_token],
            security_analysis: %{vulnerabilities: [:weak_token_validation]}
          }
        }
      ]

      result = CrossModalAnalyzer.find_synthesis_opportunities(content)

      cross_ref = result.cross_references |> List.first()
      assert cross_ref.text_reference.line == 42
      assert cross_ref.code_reference.functions |> Enum.member?(:verify_token)
      assert cross_ref.relationship_type == :direct_reference
    end
  end

  describe "prioritize_content/1" do
    test "ranks content by importance and relevance" do
      content = [
        %{
          type: :text,
          content: "Nice weather today",
          processed_content: %{relevance_score: 0.1, importance: :low}
        },
        %{
          type: :code,
          content: "critical_security_function()",
          processed_content: %{
            relevance_score: 0.9,
            importance: :critical,
            security_analysis: %{risk_level: :high}
          }
        },
        %{
          type: :image,
          content: "error_screenshot",
          processed_content: %{
            relevance_score: 0.7,
            importance: :high,
            visual_analysis: %{scene_classification: %{category: "error_critical"}}
          }
        }
      ]

      result = CrossModalAnalyzer.prioritize_content(content)

      ordered_content = result.priority_ranking.ordered_content
      assert ordered_content |> List.first() |> Map.get(:type) == :code  # Highest priority
      assert ordered_content |> List.last() |> Map.get(:type) == :text   # Lowest priority

      assert result.priority_factors.security_weight > 0
      assert result.priority_factors.error_weight > 0
      assert result.ranking_explanation |> is_list()
    end

    test "considers user context in prioritization" do
      content = [
        %{
          type: :text,
          content: "Documentation update needed",
          processed_content: %{relevance_score: 0.5, task_alignment: :documentation}
        },
        %{
          type: :code,
          content: "performance_optimization()",
          processed_content: %{relevance_score: 0.6, task_alignment: :optimization}
        }
      ]

      context = %{user_task: :documentation, priority_focus: [:documentation, :clarity]}

      result = CrossModalAnalyzer.prioritize_content(content, context)

      # Documentation should be prioritized higher due to user context
      ordered_content = result.priority_ranking.ordered_content
      assert ordered_content |> List.first() |> Map.get(:processed_content) |> Map.get(:task_alignment) == :documentation
    end
  end

  describe "analyze_content_relationships/1" do
    test "maps relationships between different content types" do
      content = [
        %{
          type: :text,
          content: "The login form validation fails",
          processed_content: %{entities: [:login_form, :validation], intent: :problem_report}
        },
        %{
          type: :code,
          content: "function validateLogin(form) { return form.username && form.password; }",
          processed_content: %{
            functions: [:validateLogin],
            parameters: [:form],
            validation_logic: :basic
          }
        },
        %{
          type: :image,
          content: "login_form_screenshot",
          processed_content: %{
            screenshot_analysis: %{
              ui_elements: %{
                forms: [%{id: "login-form", validation_state: "invalid"}]
              }
            }
          }
        }
      ]

      result = CrossModalAnalyzer.analyze_content_relationships(content)

      relationships = result.relationship_map

      # Should find relationship between text problem and code implementation
      text_code_rel = relationships |> Enum.find(&(&1.source_type == :text && &1.target_type == :code))
      assert text_code_rel != nil
      assert text_code_rel.relationship_type == :problem_to_implementation

      # Should find relationship between text description and visual evidence
      text_image_rel = relationships |> Enum.find(&(&1.source_type == :text && &1.target_type == :image))
      assert text_image_rel != nil
      assert text_image_rel.relationship_type == :description_to_evidence

      assert result.relationship_strength.overall_connectivity >= 0.5
    end

    test "identifies semantic links across modalities" do
      content = [
        %{
          type: :audio,
          content: "audio_explanation",
          processed_content: %{
            transcription: %{text: "Let me show you the database schema"},
            speaker_intent: :explanation
          }
        },
        %{
          type: :diagram,
          content: "database_schema_diagram",
          processed_content: %{
            diagram_analysis: %{
              diagram_type: :database_schema,
              entities: [:users, :posts, :comments]
            }
          }
        }
      ]

      result = CrossModalAnalyzer.analyze_content_relationships(content)

      semantic_link = result.semantic_connections |> List.first()
      assert semantic_link.connection_type == :explanatory_visual
      assert semantic_link.semantic_overlap |> Enum.member?(:database_schema)
      assert semantic_link.confidence_score >= 0.7
    end
  end

  describe "performance and scalability" do
    test "handles large numbers of content items efficiently" do
      large_content = Enum.map(1..100, fn i ->
        %{
          type: :text,
          content: "Content item #{i}",
          processed_content: %{item_id: i, relevance_score: :rand.uniform()}
        }
      end)

      start_time = System.monotonic_time(:millisecond)
      result = CrossModalAnalyzer.analyze_content_coherence(large_content)
      end_time = System.monotonic_time(:millisecond)

      processing_time = end_time - start_time

      assert result.coherence_score |> is_float()
      assert processing_time < 5000  # Should complete within 5 seconds
      assert result.performance_metrics.items_processed == 100
    end

    test "provides streaming analysis for real-time processing" do
      content_stream = [
        %{type: :text, content: "First item"},
        %{type: :image, content: "Second item"},
        %{type: :audio, content: "Third item"}
      ]

      {:ok, analyzer_pid} = CrossModalAnalyzer.start_streaming_analysis(%{})

      Enum.each(content_stream, fn item ->
        CrossModalAnalyzer.add_content_item(analyzer_pid, item)
      end)

      result = CrossModalAnalyzer.get_current_analysis(analyzer_pid)

      assert result.items_processed == 3
      assert result.streaming_coherence_score |> is_float()
      assert result.incremental_updates |> is_list()

      CrossModalAnalyzer.stop_streaming_analysis(analyzer_pid)
    end
  end

  describe "error handling and robustness" do
    test "handles content with missing processed_content gracefully" do
      incomplete_content = [
        %{type: :text, content: "Some text"},  # Missing processed_content
        %{
          type: :image,
          content: "image_data",
          processed_content: %{visual_analysis: %{}}
        }
      ]

      result = CrossModalAnalyzer.analyze_content_coherence(incomplete_content)

      assert result.coherence_score |> is_float()
      assert result.analysis_warnings |> Enum.any?(&(&1 =~ "missing processed_content"))
      assert result.partial_analysis == true
    end

    test "recovers from processing errors gracefully" do
      problematic_content = [
        %{
          type: :text,
          content: nil,  # Invalid content
          processed_content: %{error: :processing_failed}
        },
        %{
          type: :code,
          content: "valid code",
          processed_content: %{functions: [:valid_function]}
        }
      ]

      result = CrossModalAnalyzer.analyze_content_coherence(problematic_content)

      assert result.error_recovery.errors_handled > 0
      assert result.error_recovery.fallback_analysis == true
      assert result.coherence_score |> is_float()  # Should still provide a score
    end
  end
end
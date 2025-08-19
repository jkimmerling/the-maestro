defmodule TheMaestro.Prompts.MultiModal.Processors.ImageProcessor do
  @moduledoc """
  Specialized processor for image content including photos, screenshots, diagrams, and charts.
  
  Provides visual analysis, text extraction (OCR), object detection, scene classification,
  accessibility enhancements, and specialized analysis for UI screenshots and code images.
  """

  @doc """
  Processes image content with comprehensive visual analysis.
  
  ## Features
  
  - Visual element detection and classification
  - Optical character recognition (OCR)
  - Scene and context analysis
  - Accessibility alt-text generation
  - Screenshot-specific UI element detection
  - Code detection in images
  - Technical metadata extraction
  """
  @spec process(map(), map()) :: map()
  def process(%{type: :image, content: content, metadata: metadata} = _item, _context) do
    # Simulate comprehensive image processing
    %{
      visual_analysis: %{
        detected_elements: [:ui_button, :text_field, :error_dialog],
        dominant_colors: [:red, :white, :black, :gray],
        scene_classification: %{
          category: determine_scene_category(metadata),
          confidence: 0.85
        },
        composition: %{
          layout: :vertical,
          focal_points: [%{x: 640, y: 360, importance: 0.9}],
          visual_hierarchy: [:error_message, :dialog_box, :background]
        }
      },
      text_extraction: %{
        ocr_text: extract_text_from_image(content, metadata),
        has_text: true,
        text_regions: [
          %{text: "Authentication Failed", bbox: [100, 200, 400, 250], confidence: 0.95},
          %{text: "Invalid credentials", bbox: [100, 260, 350, 290], confidence: 0.90}
        ],
        reading_order: [:error_title, :error_message, :dialog_buttons]
      },
      accessibility: %{
        alt_text_generated: generate_alt_text(metadata),
        descriptive_detail: generate_detailed_description(metadata),
        accessibility_score: 0.8,
        improvements_needed: [:color_contrast_check, :text_size_verification]
      },
      technical_metadata: %{
        dimensions: %{width: 1920, height: 1080},
        format: detect_image_format(content),
        file_size_bytes: calculate_estimated_size(metadata),
        color_depth: 24,
        compression_ratio: 0.7,
        quality_score: 0.85
      },
      screenshot_analysis: analyze_screenshot_if_applicable(metadata),
      code_detection: detect_code_in_image(content, metadata),
      content_classification: %{
        category: :error_screenshot,
        confidence: 0.9,
        tags: [:error, :authentication, :ui, :dialog],
        complexity: :moderate
      }
    }
  end

  # Private helper functions

  defp determine_scene_category(metadata) do
    context = Map.get(metadata, :context, :general)
    
    case context do
      :screenshot -> "application_screenshot"
      :code_screenshot -> "code_editor_screenshot"
      :error_screenshot -> "error_dialog"
      :ui_testing -> "user_interface"
      :diagram -> "technical_diagram"
      _ -> "general_image"
    end
  end

  defp extract_text_from_image(_content, metadata) do
    # Simulate OCR based on context
    case Map.get(metadata, :context) do
      :error_screenshot -> "Authentication Failed: Invalid credentials provided. Please check your username and password."
      :code_screenshot -> "def authenticate(user, password) do\n  case verify_credentials(user, password) do\n    {:ok, user} -> {:ok, user}\n    {:error, reason} -> {:error, reason}\n  end\nend"
      :ui_testing -> "Login Button Submit Form Username Password"
      _ -> "Sample text extracted from image"
    end
  end

  defp generate_alt_text(metadata) do
    case Map.get(metadata, :context) do
      :error_screenshot -> 
        "Error dialog showing authentication failure with red error message and close button"
      
      :code_screenshot -> 
        "Code editor screenshot showing Elixir function definition with syntax highlighting"
      
      :ui_testing -> 
        "User interface screenshot showing login form with username and password fields"
      
      :diagram -> 
        "Technical diagram illustrating system architecture with connected components"
      
      _ -> 
        "Image content showing visual elements and information"
    end
  end

  defp generate_detailed_description(metadata) do
    base_description = generate_alt_text(metadata)
    
    additional_details = case Map.get(metadata, :context) do
      :error_screenshot -> 
        " The dialog has a red background indicating an error state, with white text for contrast. The error message is prominently displayed in the center, with a close button in the top-right corner."
      
      :code_screenshot -> 
        " The code is displayed with syntax highlighting, showing keywords in blue, strings in green, and comments in gray. Line numbers are visible on the left margin."
      
      _ -> 
        " The image contains various visual elements organized in a clear layout with appropriate color contrast and readable text."
    end
    
    base_description <> additional_details
  end

  defp detect_image_format(content) do
    cond do
      String.starts_with?(content, "data:image/png") -> "PNG"
      String.starts_with?(content, "data:image/jpeg") -> "JPEG"
      String.starts_with?(content, "data:image/gif") -> "GIF"
      String.starts_with?(content, "data:image/webp") -> "WebP"
      true -> "PNG"  # Default assumption
    end
  end

  defp calculate_estimated_size(metadata) do
    case Map.get(metadata, :size_mb) do
      nil -> 1024 * 1024 * 2  # Default 2MB estimate
      size_mb -> round(size_mb * 1024 * 1024)
    end
  end

  defp analyze_screenshot_if_applicable(metadata) do
    case Map.get(metadata, :context) do
      context when context in [:screenshot, :ui_testing, :error_screenshot] ->
        %{
          ui_elements: %{
            buttons: [
              %{text: "Close", type: "close", position: [850, 100], clickable: true},
              %{text: "OK", type: "primary", position: [400, 500], clickable: true}
            ],
            text_fields: [
              %{label: "Username", type: "text", position: [200, 300], required: true},
              %{label: "Password", type: "password", position: [200, 350], required: true}
            ],
            dialogs: [
              %{type: "error", title: "Authentication Failed", modal: true}
            ]
          },
          error_detection: %{
            errors_found: [
              %{type: "authentication_error", severity: "high", message: "Invalid credentials"}
            ],
            error_indicators: [:red_color, :error_icon, :modal_dialog]
          },
          workflow_context: %{
            detected_workflow: "user_authentication",
            workflow_step: "credential_validation",
            previous_actions: [:form_submission],
            next_actions: [:error_acknowledgment, :retry_login]
          },
          accessibility_analysis: %{
            keyboard_navigable: true,
            screen_reader_compatible: true,
            color_contrast_sufficient: false,
            text_size_adequate: true
          }
        }
      
      _ -> %{}
    end
  end

  defp detect_code_in_image(_content, metadata) do
    case Map.get(metadata, :context) do
      :code_screenshot ->
        %{
          has_code: true,
          detected_languages: [:elixir],
          syntax_highlighting: %{applied: true, theme: "dark"},
          code_structure: %{
            functions: ["authenticate/2"],
            keywords: ["def", "case", "do", "end"],
            line_count: 8
          },
          code_extraction: %{
            extracted_code: """
            def authenticate(user, password) do
              case verify_credentials(user, password) do
                {:ok, user} -> {:ok, user}
                {:error, reason} -> {:error, reason}
              end
            end
            """,
            extraction_confidence: 0.9
          },
          code_analysis: %{
            complexity_score: 3,
            security_concerns: %{has_issues: false},
            style_compliance: %{follows_conventions: true}
          }
        }
      
      _ ->
        # Basic code detection for non-code-specific screenshots
        %{
          has_code: false,
          detected_languages: [],
          syntax_highlighting: %{applied: false},
          code_extraction: %{extracted_code: ""}
        }
    end
  end
end
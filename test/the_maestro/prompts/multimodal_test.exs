defmodule TheMaestro.Prompts.MultiModalTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal

  describe "supported_content_types/0" do
    test "defines all supported content types" do
      expected_types = [:text, :image, :audio, :video, :document, :file]
      assert MultiModal.supported_content_types() == expected_types
    end
  end

  describe "content_to_parts/1" do
    test "converts text content to text part" do
      content = [
        %{type: :text, content: "Hello world"}
      ]

      parts = MultiModal.content_to_parts(content)

      assert [%{text: "Hello world"}] = parts
    end

    test "converts image content to inline_data part" do
      content = [
        %{
          type: :image,
          content: "base64_encoded_image_data",
          mime_type: "image/png"
        }
      ]

      parts = MultiModal.content_to_parts(content)

      assert [
               %{
                 inline_data: %{
                   mime_type: "image/png",
                   data: "base64_encoded_image_data"
                 }
               }
             ] = parts
    end

    test "converts multiple content items correctly" do
      content = [
        %{type: :text, content: "Analyze this image:"},
        %{
          type: :image,
          content: "base64_data",
          mime_type: "image/jpeg"
        },
        %{type: :text, content: "What do you see?"}
      ]

      parts = MultiModal.content_to_parts(content)

      assert [
               %{text: "Analyze this image:"},
               %{inline_data: %{mime_type: "image/jpeg", data: "base64_data"}},
               %{text: "What do you see?"}
             ] = parts
    end

    test "infers MIME types when not provided" do
      content = [
        %{type: :image, content: "image_data"},
        %{type: :document, content: "pdf_data"},
        %{type: :audio, content: "audio_data"}
      ]

      parts = MultiModal.content_to_parts(content)

      assert [
               %{inline_data: %{mime_type: "image/png", data: "image_data"}},
               %{inline_data: %{mime_type: "application/pdf", data: "pdf_data"}},
               %{inline_data: %{mime_type: "audio/wav", data: "audio_data"}}
             ] = parts
    end

    test "filters out invalid content items" do
      content = [
        %{type: :text, content: "Valid text"},
        %{type: :invalid_type, content: "Should be filtered"},
        # Empty content
        %{type: :image, content: ""},
        # Missing type
        %{content: "Missing type"},
        %{type: :video, content: "valid_video_data"}
      ]

      parts = MultiModal.content_to_parts(content)

      assert [
               %{text: "Valid text"},
               %{inline_data: %{mime_type: "video/mp4", data: "valid_video_data"}}
             ] = parts
    end

    test "handles empty content list" do
      assert MultiModal.content_to_parts([]) == []
    end
  end

  describe "valid_content_item?/1" do
    test "validates text content" do
      assert MultiModal.valid_content_item?(%{type: :text, content: "Hello"})
      refute MultiModal.valid_content_item?(%{type: :text, content: ""})
      refute MultiModal.valid_content_item?(%{type: :text})
    end

    test "validates non-text content" do
      assert MultiModal.valid_content_item?(%{type: :image, content: "image_data"})
      assert MultiModal.valid_content_item?(%{type: :document, content: "pdf_data"})
      refute MultiModal.valid_content_item?(%{type: :image, content: ""})
    end

    test "rejects unsupported types" do
      refute MultiModal.valid_content_item?(%{type: :unsupported, content: "data"})
    end

    test "rejects invalid structures" do
      refute MultiModal.valid_content_item?(%{content: "missing type"})
      refute MultiModal.valid_content_item?("not a map")
      refute MultiModal.valid_content_item?(%{})
    end
  end

  describe "estimate_token_usage/1" do
    test "estimates tokens for text content" do
      content = [
        # ~6 tokens
        %{type: :text, content: "This is a test message"}
      ]

      tokens = MultiModal.estimate_token_usage(content)
      # 23 chars / 4 = 5.75, truncated to 5
      assert tokens == 5
    end

    test "estimates tokens for different content types" do
      content = [
        # ~2 tokens
        %{type: :text, content: "Short text"},
        # 1000 tokens
        %{type: :image, content: "image_data"},
        # 2000 tokens
        %{type: :video, content: "video_data"},
        # 1500 tokens
        %{type: :document, content: "pdf_data"},
        # 500 tokens
        %{type: :file, content: "file_data"}
      ]

      tokens = MultiModal.estimate_token_usage(content)
      # 5002
      expected = 2 + 1000 + 2000 + 1500 + 500
      assert tokens == expected
    end

    test "handles empty content" do
      assert MultiModal.estimate_token_usage([]) == 0
    end

    test "ignores invalid content items in estimation" do
      content = [
        %{type: :text, content: "Valid"},
        %{type: :invalid, content: "Invalid"},
        %{content: "No type"}
      ]

      # Only counts the valid text item
      tokens = MultiModal.estimate_token_usage(content)
      # "Valid" = 5 chars / 4 = 1.25, truncated to 1
      assert tokens == 1
    end
  end

  describe "integration with LLM providers" do
    test "generates parts compatible with Gemini format" do
      content = [
        %{type: :text, content: "Please analyze this image"},
        %{
          type: :image,
          content:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
          mime_type: "image/png"
        }
      ]

      parts = MultiModal.content_to_parts(content)

      # Should be compatible with Google Gemini API part format
      assert [text_part, image_part] = parts
      assert %{text: _} = text_part
      assert %{inline_data: %{mime_type: "image/png", data: _}} = image_part
    end

    test "generates parts compatible with Claude format" do
      content = [
        %{type: :text, content: "Analyze this document"},
        %{
          type: :document,
          content: "base64_pdf_content",
          mime_type: "application/pdf"
        }
      ]

      parts = MultiModal.content_to_parts(content)

      # Should be compatible with Claude API format
      assert [text_part, doc_part] = parts
      assert %{text: "Analyze this document"} = text_part

      assert %{inline_data: %{mime_type: "application/pdf", data: "base64_pdf_content"}} =
               doc_part
    end
  end
end

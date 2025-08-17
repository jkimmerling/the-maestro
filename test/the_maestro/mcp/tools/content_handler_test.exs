defmodule TheMaestro.MCP.Tools.ContentHandlerTest do
  use ExUnit.Case, async: true
  doctest TheMaestro.MCP.Tools.ContentHandler

  alias TheMaestro.MCP.Tools.ContentHandler

  describe "process_content/1" do
    test "processes text content" do
      content = [
        %{"type" => "text", "text" => "Hello, World!"}
      ]

      result = ContentHandler.process_content(content)
      
      assert result.text_content == "Hello, World!"
      assert result.has_images == false
      assert result.has_resources == false
      assert result.has_binary == false
      assert length(result.processed_blocks) == 1
    end

    test "processes image content" do
      content = [
        %{
          "type" => "image",
          "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
          "mimeType" => "image/png"
        }
      ]

      result = ContentHandler.process_content(content)
      
      assert result.text_content == ""
      assert result.has_images == true
      assert result.has_resources == false
      assert result.has_binary == false
      assert length(result.processed_blocks) == 1
      
      image_block = List.first(result.processed_blocks)
      assert image_block.type == :image
      assert image_block.mime_type == "image/png"
      assert byte_size(image_block.decoded_data) > 0
    end

    test "processes resource content" do
      content = [
        %{
          "type" => "resource",
          "resource" => %{
            "uri" => "file:///test/resource.txt",
            "text" => "Resource content here",
            "mimeType" => "text/plain"
          }
        }
      ]

      result = ContentHandler.process_content(content)
      
      assert result.text_content == "Resource content here"
      assert result.has_images == false
      assert result.has_resources == true
      assert result.has_binary == false
      assert length(result.processed_blocks) == 1
      
      resource_block = List.first(result.processed_blocks)
      assert resource_block.type == :resource
      assert resource_block.uri == "file:///test/resource.txt"
      assert resource_block.content == "Resource content here"
    end

    test "processes audio content" do
      content = [
        %{
          "type" => "audio",
          "data" => "UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2/LDciUFLIHO8tiJNwgZaLvt559NEAxQp+PwtmMcBjiR1/LMeSwFJHfH8N2QQAoUXrTp66hVFApGn+DyvmwhBTOH0PK5dysKL4/C8M2QPQYUUqzk5KBlGA==",
          "mimeType" => "audio/wav"
        }
      ]

      result = ContentHandler.process_content(content)
      
      assert result.text_content == ""
      assert result.has_images == false
      assert result.has_resources == false
      assert result.has_binary == true
      assert length(result.processed_blocks) == 1
      
      audio_block = List.first(result.processed_blocks)
      assert audio_block.type == :audio
      assert audio_block.mime_type == "audio/wav"
      assert byte_size(audio_block.decoded_data) > 0
    end

    test "processes mixed content types" do
      content = [
        %{"type" => "text", "text" => "Analysis results:"},
        %{
          "type" => "image",
          "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
          "mimeType" => "image/png"
        },
        %{"type" => "text", "text" => "Summary: Complete!"}
      ]

      result = ContentHandler.process_content(content)
      
      assert result.text_content == "Analysis results: Summary: Complete!"
      assert result.has_images == true
      assert result.has_resources == false
      assert result.has_binary == false
      assert length(result.processed_blocks) == 3
    end

    test "handles empty content" do
      result = ContentHandler.process_content([])
      
      assert result.text_content == ""
      assert result.has_images == false
      assert result.has_resources == false
      assert result.has_binary == false
      assert result.processed_blocks == []
    end

    test "handles malformed content gracefully" do
      content = [
        %{"type" => "unknown_type", "data" => "some_data"},
        %{"incomplete" => "block"}
      ]

      result = ContentHandler.process_content(content)
      
      # Should handle unknown types gracefully
      assert result.text_content == ""
      assert length(result.processed_blocks) == 2
      assert List.first(result.processed_blocks).type == :unknown
    end
  end

  describe "decode_base64_content/2" do
    test "decodes valid base64 image data" do
      base64_data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
      
      {:ok, decoded} = ContentHandler.decode_base64_content(base64_data, "image/png")
      
      assert is_binary(decoded)
      assert byte_size(decoded) > 0
    end

    test "handles invalid base64 data" do
      invalid_data = "not_valid_base64!!!"
      
      {:error, reason} = ContentHandler.decode_base64_content(invalid_data, "image/png")
      
      assert reason.type == :invalid_base64
    end

    test "validates content size limits" do
      # Create a large base64 string (over 10MB when decoded)
      large_data = String.duplicate("A", 15_000_000) |> Base.encode64()
      
      {:error, reason} = ContentHandler.decode_base64_content(large_data, "image/png")
      
      assert reason.type == :content_too_large
    end
  end

  describe "extract_text_from_content/1" do
    test "extracts text from various content types" do
      content = [
        %{"type" => "text", "text" => "First part"},
        %{"type" => "image", "data" => "imagedata"},
        %{"type" => "resource", "resource" => %{"text" => "Resource text"}},
        %{"type" => "text", "text" => "Last part"}
      ]

      text = ContentHandler.extract_text_from_content(content)
      
      assert text == "First part Resource text Last part"
    end

    test "handles content without text" do
      content = [
        %{"type" => "image", "data" => "imagedata"},
        %{"type" => "audio", "data" => "audiodata"}
      ]

      text = ContentHandler.extract_text_from_content(content)
      
      assert text == ""
    end
  end

  describe "validate_content_security/1" do
    test "validates safe content" do
      content = [
        %{"type" => "text", "text" => "Safe text content"},
        %{"type" => "image", "data" => "validbase64data", "mimeType" => "image/png"}
      ]

      assert :ok == ContentHandler.validate_content_security(content)
    end

    test "detects potentially dangerous content" do
      content = [
        %{
          "type" => "resource",
          "resource" => %{
            "uri" => "file:///etc/passwd",
            "text" => "root:x:0:0:root:/root:/bin/bash"
          }
        }
      ]

      {:error, reason} = ContentHandler.validate_content_security(content)
      
      assert reason.type == :suspicious_resource
    end

    test "validates file path safety" do
      content = [
        %{
          "type" => "resource",
          "resource" => %{
            "uri" => "file:///../../../etc/passwd",
            "text" => "content"
          }
        }
      ]

      {:error, reason} = ContentHandler.validate_content_security(content)
      
      assert reason.type == :path_traversal_attempt
    end
  end

  describe "optimize_content_for_agent/2" do
    test "optimizes content for multimodal agent" do
      content = [
        %{"type" => "text", "text" => "Analysis:"},
        %{
          "type" => "image",
          "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
          "mimeType" => "image/png"
        }
      ]

      options = %{agent_type: :multimodal, max_content_size: 1_000_000}
      
      optimized = ContentHandler.optimize_content_for_agent(content, options)
      
      # Should preserve both text and image for multimodal agent
      assert length(optimized) == 2
      assert Enum.any?(optimized, &(&1["type"] == "text"))
      assert Enum.any?(optimized, &(&1["type"] == "image"))
    end

    test "optimizes content for text-only agent" do
      content = [
        %{"type" => "text", "text" => "Analysis:"},
        %{
          "type" => "image",
          "data" => "imagedata",
          "mimeType" => "image/png"
        },
        %{"type" => "text", "text" => "Summary"}
      ]

      options = %{agent_type: :text_only}
      
      optimized = ContentHandler.optimize_content_for_agent(content, options)
      
      # Should only preserve text content
      assert length(optimized) == 2
      assert Enum.all?(optimized, &(&1["type"] == "text"))
    end

    test "respects content size limits" do
      large_text = String.duplicate("A", 10_000)
      content = [
        %{"type" => "text", "text" => large_text}
      ]

      # Use max_text_length instead of max_content_size for this test
      options = %{max_text_length: 5_000}
      
      optimized = ContentHandler.optimize_content_for_agent(content, options)
      
      # Should truncate large text content
      text_content = List.first(optimized)["text"]
      refute is_nil(text_content)
      assert String.length(text_content) <= 5_000
      assert String.contains?(text_content, "... [truncated]")
    end
  end
end
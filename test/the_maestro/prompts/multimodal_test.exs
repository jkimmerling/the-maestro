defmodule TheMaestro.Prompts.MultiModalTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal

  alias TheMaestro.Prompts.MultiModal.{
    ContentItem,
    ContentProcessor,
    ProviderAdapter,
    MessageIntegrator
  }

  # Create test files for real file processing tests
  setup_all do
    # Create temporary directory for test files
    test_dir = "/tmp/multimodal_test_#{:rand.uniform(1_000_000)}"
    File.mkdir_p!(test_dir)

    # Create test image file (1x1 PNG)
    png_data =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
      )

    image_path = Path.join(test_dir, "test_image.png")
    File.write!(image_path, png_data)

    # Create test text file
    text_path = Path.join(test_dir, "test_document.txt")
    File.write!(text_path, "This is a test document with some content.")

    # Create test PDF (minimal PDF structure)
    pdf_data =
      "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\nxref\n0 4\n0000000000 65535 f \n0000000010 00000 n \n0000000053 00000 n \n0000000125 00000 n \ntrailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n198\n%%EOF"

    pdf_path = Path.join(test_dir, "test_document.pdf")
    File.write!(pdf_path, pdf_data)

    on_exit(fn ->
      File.rm_rf(test_dir)
    end)

    %{
      test_dir: test_dir,
      image_path: image_path,
      text_path: text_path,
      pdf_path: pdf_path,
      png_data: png_data,
      pdf_data: pdf_data
    }
  end

  # Legacy API compatibility tests
  describe "legacy content_to_parts/1 (for backwards compatibility)" do
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
                   data: "YmFzZTY0X2VuY29kZWRfaW1hZ2VfZGF0YQ=="
                 }
               }
             ] = parts
    end

    test "validates legacy content item format" do
      assert MultiModal.valid_content_item?(%{type: :text, content: "Hello"})
      assert MultiModal.valid_content_item?(%{type: :image, content: "image_data"})
      refute MultiModal.valid_content_item?(%{type: :text, content: ""})
      refute MultiModal.valid_content_item?(%{type: :unsupported, content: "data"})
    end
  end

  # ContentItem tests
  describe "ContentItem" do
    test "creates valid content items" do
      item = ContentItem.from_text("Hello world")
      assert ContentItem.valid?(item)
      assert item.type == :text
      assert item.data == "Hello world"
      assert item.mime_type == "text/plain"
      assert item.size == 11
    end

    test "creates content item with all fields" do
      item =
        ContentItem.new(:image, "binary_data", "image/png", "/path/to/file.png", %{source: "test"})

      assert ContentItem.valid?(item)
      assert item.type == :image
      assert item.data == "binary_data"
      assert item.mime_type == "image/png"
      assert item.file_path == "/path/to/file.png"
      assert item.size == 11
      assert item.metadata == %{source: "test"}
    end

    test "validates content items" do
      valid_item = ContentItem.new(:image, "data", "image/png")
      invalid_item = %ContentItem{type: :invalid, data: "", mime_type: "text/plain"}

      assert ContentItem.valid?(valid_item)
      refute ContentItem.valid?(invalid_item)
    end
  end

  # ContentProcessor tests with real files
  describe "ContentProcessor real file processing" do
    test "processes PNG image file", %{image_path: image_path, png_data: png_data} do
      {:ok, content_item} = ContentProcessor.process_file(image_path)

      assert content_item.type == :image
      assert content_item.data == png_data
      assert content_item.mime_type == "image/png"
      assert content_item.file_path == image_path
      assert content_item.size == byte_size(png_data)
      assert ContentItem.valid?(content_item)
    end

    test "processes text file", %{text_path: text_path} do
      {:ok, content_item} = ContentProcessor.process_file(text_path)

      assert content_item.type == :document
      assert content_item.data == "This is a test document with some content."
      assert content_item.mime_type == "text/plain"
      assert content_item.file_path == text_path
      assert content_item.size == 42
      assert ContentItem.valid?(content_item)
    end

    test "processes PDF file", %{pdf_path: pdf_path, pdf_data: pdf_data} do
      {:ok, content_item} = ContentProcessor.process_file(pdf_path)

      assert content_item.type == :document
      assert content_item.data == pdf_data
      assert content_item.mime_type == "application/pdf"
      assert content_item.file_path == pdf_path
      assert content_item.size == byte_size(pdf_data)
      assert ContentItem.valid?(content_item)
    end

    test "handles non-existent file" do
      {:error, error_msg} = ContentProcessor.process_file("/nonexistent/file.png")
      assert String.contains?(error_msg, "Cannot read file")
    end

    test "validates file before processing" do
      # Test file size validation
      assert ContentProcessor.validate_file("/dev/null") ==
               {:error, "File is not a regular file (type: device)"}
    end

    test "processes base64 content" do
      base64_data = Base.encode64("test image data")
      {:ok, content_item} = ContentProcessor.process_base64(base64_data, "image/jpeg")

      assert content_item.type == :image
      assert content_item.data == "test image data"
      assert content_item.mime_type == "image/jpeg"
      assert is_nil(content_item.file_path)
      assert content_item.metadata.source == :base64
    end

    test "detects MIME types from file content" do
      # Test PNG magic number detection
      png_header = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "rest of data">>
      temp_file = "/tmp/test_magic_#{:rand.uniform(1_000_000)}.unknown"
      File.write!(temp_file, png_header)

      {:ok, content_item} = ContentProcessor.process_file(temp_file)
      assert content_item.mime_type == "image/png"

      File.rm!(temp_file)
    end
  end

  # ProviderAdapter tests
  describe "ProviderAdapter" do
    setup %{png_data: png_data} do
      content_items = [
        ContentItem.from_text("Analyze this image"),
        ContentItem.new(:image, png_data, "image/png", "/test/image.png")
      ]

      %{content_items: content_items}
    end

    test "formats for Gemini provider", %{content_items: content_items} do
      {:ok, message} =
        ProviderAdapter.format_for_provider(content_items, "Please analyze", :gemini)

      assert message.role == "user"
      # prompt text + 2 content items
      assert length(message.parts) == 3

      [text_part, text_item_part, image_part] = message.parts
      assert text_part.text == "Please analyze"
      assert text_item_part.text == "Analyze this image"
      assert image_part.inline_data.mime_type == "image/png"

      assert image_part.inline_data.data ==
               Base.encode64(content_items |> Enum.at(1) |> Map.get(:data))
    end

    test "formats for OpenAI provider", %{content_items: content_items} do
      {:ok, message} =
        ProviderAdapter.format_for_provider(content_items, "Please analyze", :openai)

      assert message.role == "user"
      assert length(message.content) == 3

      [text_part, text_item_part, image_part] = message.content
      assert text_part.type == "text"
      assert text_part.text == "Please analyze"
      assert text_item_part.type == "text"
      assert text_item_part.text == "Analyze this image"
      assert image_part.type == "image_url"
      assert String.starts_with?(image_part.image_url.url, "data:image/png;base64,")
    end

    test "formats for Claude provider", %{content_items: content_items} do
      {:ok, message} =
        ProviderAdapter.format_for_provider(content_items, "Please analyze", :claude)

      assert message.role == "user"
      assert length(message.content) == 3

      [text_part, text_item_part, image_part] = message.content
      assert text_part.type == "text"
      assert text_part.text == "Please analyze"
      assert text_item_part.type == "text"
      assert text_item_part.text == "Analyze this image"
      assert image_part.type == "image"
      assert image_part.source.type == "base64"
      assert image_part.source.media_type == "image/png"
    end

    test "checks provider content type support" do
      assert ProviderAdapter.supports_content_type?(:gemini, :image)
      assert ProviderAdapter.supports_content_type?(:gemini, :document)
      assert ProviderAdapter.supports_content_type?(:openai, :image)
      refute ProviderAdapter.supports_content_type?(:openai, :document)
      assert ProviderAdapter.supports_content_type?(:claude, :image)
      assert ProviderAdapter.supports_content_type?(:claude, :document)
    end

    test "handles unsupported provider" do
      {:error, error_msg} = ProviderAdapter.format_for_provider([], "test", :unsupported)
      assert String.contains?(error_msg, "Unsupported provider")
    end
  end

  # MessageIntegrator tests
  describe "MessageIntegrator" do
    test "integrates multimodal content into message" do
      message = %{role: :user, content: "Look at this image"}
      content_items = [ContentItem.new(:image, "image_data", "image/png")]

      {:ok, enhanced_message} =
        MessageIntegrator.integrate_multimodal_content(message, content_items, :gemini)

      assert enhanced_message.role == "user"
      assert length(enhanced_message.parts) == 2
      assert Enum.any?(enhanced_message.parts, &Map.has_key?(&1, :text))
      assert Enum.any?(enhanced_message.parts, &Map.has_key?(&1, :inline_data))
    end

    test "creates new multimodal message" do
      content_items = [
        ContentItem.from_text("Hello"),
        ContentItem.new(:image, "data", "image/png")
      ]

      {:ok, message} =
        MessageIntegrator.create_multimodal_message(content_items, "Analyze", :gemini)

      assert message.role == :user
      # prompt + 2 content items
      assert length(message.parts) == 3
    end

    test "adds content descriptions for non-multimodal providers" do
      content_items = [ContentItem.new(:image, "data", "image/png", "/test.png")]

      description = MessageIntegrator.add_content_descriptions("Original text", content_items)

      assert String.contains?(description, "Original text")
      assert String.contains?(description, "[IMAGE: image/png (/test.png)]")
    end
  end

  # Full integration tests with real files
  describe "Full multimodal integration with real files" do
    test "creates multimodal prompt from file paths", %{
      image_path: image_path,
      text_path: text_path
    } do
      {:ok, message} =
        MultiModal.create_multimodal_prompt(
          [image_path, text_path],
          "Analyze these files",
          :gemini
        )

      assert message.role == :user
      # prompt + image + text
      assert length(message.parts) >= 3

      # Should have text parts and inline_data parts
      text_parts = Enum.filter(message.parts, &Map.has_key?(&1, :text))
      media_parts = Enum.filter(message.parts, &Map.has_key?(&1, :inline_data))

      assert length(text_parts) >= 1
      assert length(media_parts) >= 1
    end

    test "processes mixed content inputs", %{image_path: image_path} do
      base64_data = Base.encode64("pdf content")
      content_item = ContentItem.from_text("Text item")

      {:ok, message} =
        MultiModal.create_multimodal_prompt(
          [
            image_path,
            %{type: :document, content: base64_data, mime_type: "application/pdf"},
            content_item
          ],
          "Analyze all content",
          :claude
        )

      assert message.role == :user
      # prompt + image + pdf + text
      assert length(message.content) >= 4
    end

    test "enhances existing message with file content", %{image_path: image_path} do
      original_message = %{role: :user, content: "Please review"}

      {:ok, enhanced_message} =
        MultiModal.enhance_message(
          original_message,
          [image_path],
          :openai
        )

      assert enhanced_message.role == "user"
      # original text + image
      assert length(enhanced_message.content) >= 2

      # Should have both text and image_url content
      text_content = Enum.filter(enhanced_message.content, &(&1.type == "text"))
      image_content = Enum.filter(enhanced_message.content, &(&1.type == "image_url"))

      assert length(text_content) >= 1
      assert length(image_content) == 1
    end

    test "estimates token usage for real content", %{image_path: image_path, text_path: text_path} do
      {:ok, image_item} = MultiModal.process_file(image_path)
      {:ok, text_item} = MultiModal.process_file(text_path)

      tokens = MultiModal.estimate_token_usage([image_item, text_item], "Analyze both", :gemini)

      # Should account for prompt text, text content, and image
      # At least 1000 for the image
      assert tokens > 1000
    end

    test "supports different providers for the same content", %{image_path: image_path} do
      content_inputs = [image_path]
      prompt = "What's in this image?"

      {:ok, gemini_message} = MultiModal.create_multimodal_prompt(content_inputs, prompt, :gemini)
      {:ok, openai_message} = MultiModal.create_multimodal_prompt(content_inputs, prompt, :openai)
      {:ok, claude_message} = MultiModal.create_multimodal_prompt(content_inputs, prompt, :claude)

      # Each should have provider-specific format
      assert Map.has_key?(gemini_message, :parts)
      assert Map.has_key?(openai_message, :content)
      assert Map.has_key?(claude_message, :content)

      # But all should contain the same image data
      assert String.contains?(inspect(gemini_message), "image/png")
      assert String.contains?(inspect(openai_message), "image/png")
      assert String.contains?(inspect(claude_message), "image/png")
    end

    test "handles file validation errors gracefully" do
      # Test with non-existent file
      {:error, error_msg} =
        MultiModal.create_multimodal_prompt(
          ["/nonexistent/file.png"],
          "Analyze this",
          :gemini
        )

      assert String.contains?(error_msg, "Error processing input")
      assert String.contains?(error_msg, "Cannot access file")
    end

    test "validates input limits" do
      # Test max content items limit
      large_input_list = for i <- 1..25, do: "/fake/file#{i}.png"

      {:error, error_msg} =
        MultiModal.create_multimodal_prompt(
          large_input_list,
          "Analyze",
          :gemini,
          max_content_items: 20
        )

      assert String.contains?(error_msg, "Too many content items")
    end
  end

  # Provider-specific content support tests
  describe "provider content type support" do
    test "lists supported content types for each provider" do
      gemini_types = MultiModal.supported_content_types(:gemini)
      openai_types = MultiModal.supported_content_types(:openai)
      claude_types = MultiModal.supported_content_types(:claude)

      assert :image in gemini_types
      assert :document in gemini_types
      assert :image in openai_types
      refute :document in openai_types
      assert :image in claude_types
      assert :document in claude_types
    end
  end

  # Additional edge case tests for better coverage
  describe "ContentProcessor edge cases" do
    test "handles invalid file paths" do
      {:error, error_msg} = ContentProcessor.process_file("")
      assert String.contains?(error_msg, "Cannot access file")
    end

    test "handles directory instead of file" do
      temp_dir = "/tmp/test_dir_#{:rand.uniform(1_000_000)}"
      File.mkdir_p!(temp_dir)

      {:error, error_msg} = ContentProcessor.process_file(temp_dir)
      assert String.contains?(error_msg, "File is not a regular file")

      File.rmdir!(temp_dir)
    end

    test "handles very large files" do
      # 51MB
      large_data = String.duplicate("a", 51 * 1024 * 1024)
      temp_file = "/tmp/large_file_#{:rand.uniform(1_000_000)}.txt"
      File.write!(temp_file, large_data)

      {:error, error_msg} = ContentProcessor.process_file(temp_file)
      assert String.contains?(error_msg, "exceeds maximum allowed size")

      File.rm!(temp_file)
    end

    test "processes base64 with invalid data" do
      {:error, error_msg} = ContentProcessor.process_base64("invalid_base64!", "text/plain")
      assert String.contains?(error_msg, "Invalid base64 data")
    end

    test "processes base64 with empty data" do
      # Empty data should be processed successfully as an empty document
      {:ok, content_item} = ContentProcessor.process_base64("", "text/plain")
      assert content_item.type == :document
      assert content_item.data == ""
      assert content_item.size == 0
    end
  end

  # Additional ProviderAdapter tests
  describe "ProviderAdapter edge cases" do
    test "handles unsupported content type for provider" do
      content_items = [ContentItem.new(:audio, "audio_data", "audio/wav")]

      # OpenAI should handle unsupported types gracefully by adding text descriptions
      {:ok, message} = ProviderAdapter.format_for_provider(content_items, "Test", :openai)
      assert message.role == "user"
      # Should include the original text and a description of the audio content
      assert length(message.content) >= 2
    end

    test "handles empty content items list" do
      {:ok, message} = ProviderAdapter.format_for_provider([], "Just text", :gemini)

      assert message.role == "user"
      assert length(message.parts) == 1
      assert List.first(message.parts).text == "Just text"
    end

    test "content_to_parts with provider compatibility" do
      parts = ProviderAdapter.content_to_parts([], :gemini)
      assert parts == []
    end
  end

  # Additional MessageIntegrator tests
  describe "MessageIntegrator edge cases" do
    test "handles message with existing content" do
      message = %{role: :user, content: "existing text"}
      content_items = [ContentItem.from_text("new content")]

      {:ok, enhanced_message} =
        MessageIntegrator.integrate_multimodal_content(message, content_items, :gemini)

      assert enhanced_message.role == "user"
      assert length(enhanced_message.parts) >= 2
    end

    test "handles non-multimodal provider fallback" do
      content_items = [ContentItem.new(:image, "data", "image/png", "/test.png")]

      description = MessageIntegrator.add_content_descriptions("Text", content_items)
      assert String.contains?(description, "Text")
      assert String.contains?(description, "[IMAGE:")
    end

    test "creates message with text-only content" do
      content_items = [ContentItem.from_text("Hello"), ContentItem.from_text("World")]

      {:ok, message} =
        MessageIntegrator.create_multimodal_message(content_items, "Prompt", :gemini)

      assert message.role == :user
      assert length(message.parts) >= 3
    end
  end

  # Additional MultiModalPrompt tests
  describe "MultiModalPrompt edge cases" do
    test "validates maximum content items" do
      large_input_list = for i <- 1..25, do: ContentItem.from_text("item #{i}")

      {:error, error_msg} =
        MultiModal.create_multimodal_prompt(
          large_input_list,
          "Test",
          :gemini,
          max_content_items: 20
        )

      assert String.contains?(error_msg, "Too many content items")
    end

    test "validates empty content inputs" do
      {:error, error_msg} = MultiModal.create_multimodal_prompt([], "Test", :gemini)
      assert String.contains?(error_msg, "No content items provided")
    end

    test "processes mixed input types" do
      content_inputs = [
        ContentItem.from_text("Text item"),
        %{type: :text, content: "Legacy text", mime_type: "text/plain"}
      ]

      {:ok, message} = MultiModal.create_multimodal_prompt(content_inputs, "Mixed", :gemini)

      assert message.role == :user
      assert length(message.parts) >= 3
    end

    test "estimates token usage accurately" do
      content_items = [
        ContentItem.from_text("Short text"),
        ContentItem.new(:image, "image_data", "image/png"),
        ContentItem.new(:document, "doc_data", "application/pdf")
      ]

      tokens = MultiModal.estimate_token_usage(content_items, "Analyze these", :gemini)

      # Should be: text (3 chars / 4) + text (10 chars / 4) + image (1000) + document (1500) = ~2503 tokens
      assert tokens > 2500
      assert tokens < 3000
    end

    test "supports content types query" do
      gemini_types = MultiModal.supported_content_types(:gemini)
      assert :text in gemini_types
      assert :image in gemini_types
      assert :document in gemini_types
    end

    test "processes file with validation disabled" do
      temp_file = "/tmp/test_no_validation_#{:rand.uniform(1_000_000)}.txt"
      File.write!(temp_file, "test content")

      {:ok, content_item} = MultiModal.process_file(temp_file, false)
      assert content_item.type == :document
      assert content_item.data == "test content"

      File.rm!(temp_file)
    end
  end
end

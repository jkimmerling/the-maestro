defmodule TheMaestro.Prompts.MultiModal do
  @moduledoc """
  Multi-modal prompt handling system with real file processing and provider integration.

  This module provides the main interface for creating multimodal prompts that combine
  text, images, documents, and other media types for LLM providers. It uses a modular
  architecture with separate modules for content processing, provider formatting, and
  message integration.

  ## Architecture

  - `ContentItem` - Data structure for multimodal content
  - `ContentProcessor` - File reading and MIME type detection  
  - `ProviderAdapter` - Provider-specific formatting (Gemini, OpenAI, Claude)
  - `MessageIntegrator` - Integration with existing message system
  - `MultiModalPrompt` - Main coordinator and public interface

  ## Quick Start

      # Process files and create multimodal prompt
      {:ok, message} = MultiModal.create_multimodal_prompt(
        ["/path/to/image.png", "/path/to/document.pdf"],
        "Analyze these files",
        :gemini
      )

      # Enhance existing message with multimodal content  
      {:ok, enhanced} = MultiModal.enhance_message(
        %{role: :user, content: "Review this"},
        ["/path/to/file.jpg"],
        :claude
      )

  ## Supported Content Types

  - `:text` - Text content and instructions
  - `:image` - Images, screenshots, diagrams  
  - `:audio` - Audio files, voice recordings (Gemini only)
  - `:video` - Video content, screen recordings (Gemini only)
  - `:document` - PDFs, Word docs, presentations
  - `:file` - Generic file attachments

  ## Supported Providers

  - `:gemini` - Text, images, documents, audio, video
  - `:openai` - Text, images only  
  - `:claude` - Text, images, documents
  """

  # Re-export main modules for convenient access
  alias TheMaestro.Prompts.MultiModal.{
    ContentItem,
    ProviderAdapter,
    MultiModalPrompt
  }

  # Delegate main functions to the appropriate modules

  @doc """
  Creates a multimodal prompt from files and text.

  This is the main entry point for creating multimodal prompts.

  ## Parameters

  - `content_inputs` - List of file paths, base64 data, or ContentItems
  - `prompt_text` - Text prompt to include
  - `provider` - Target provider (:gemini, :openai, :claude)
  - `opts` - Options (see MultiModalPrompt.create_multimodal_prompt/4)

  ## Returns

  - `{:ok, message}` - Successfully created multimodal message
  - `{:error, reason}` - Error creating prompt

  ## Examples

      # From file paths
      {:ok, message} = MultiModal.create_multimodal_prompt(
        ["/path/to/image.png"],
        "What's in this image?",
        :gemini
      )

      # Mixed content types
      {:ok, message} = MultiModal.create_multimodal_prompt(
        [content_item, "/path/to/file.pdf"],
        "Analyze both items",
        :claude
      )
  """
  defdelegate create_multimodal_prompt(content_inputs, prompt_text, provider, opts \\ []),
    to: MultiModalPrompt

  @doc """
  Processes a file into a ContentItem structure.

  ## Parameters

  - `file_path` - Path to file to process
  - `validate` - Whether to validate file access (default: true)

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error processing file
  """
  defdelegate process_file(file_path, validate \\ true), to: MultiModalPrompt

  @doc """
  Processes base64-encoded content into a ContentItem.

  ## Parameters

  - `base64_data` - Base64-encoded content
  - `mime_type` - MIME type of the content
  - `metadata` - Optional metadata

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error processing content
  """
  defdelegate process_base64(base64_data, mime_type, metadata \\ %{}), to: MultiModalPrompt

  @doc """
  Enhances an existing message with multimodal content.

  ## Parameters

  - `message` - Existing message to enhance
  - `content_inputs` - Content to add to the message  
  - `provider` - Target provider for formatting
  - `opts` - Additional options

  ## Returns

  - `{:ok, enhanced_message}` - Message enhanced with multimodal content
  - `{:error, reason}` - Error enhancing message
  """
  defdelegate enhance_message(message, content_inputs, provider, opts \\ []), to: MultiModalPrompt

  @doc """
  Lists supported content types for a provider.

  ## Parameters

  - `provider` - Provider to check support for

  ## Returns

  List of supported content types for the provider.
  """
  defdelegate supported_content_types(provider), to: MultiModalPrompt

  @doc """
  Estimates token usage for multimodal content.

  ## Parameters

  - `content_items` - List of ContentItem structs
  - `prompt_text` - Text content
  - `provider` - Target provider

  ## Returns

  Estimated token count.
  """
  defdelegate estimate_token_usage(content_items, prompt_text, provider), to: MultiModalPrompt

  # Legacy compatibility functions

  @doc """
  Converts simple content items to provider parts (legacy compatibility).

  This function provides backwards compatibility with the original simple format.
  For new code, use the full multimodal prompt creation functions.

  ## Parameters

  - `content` - List of simple content items with :type, :content, :mime_type

  ## Returns

  List of provider-compatible parts.
  """
  @spec content_to_parts(list()) :: list()
  def content_to_parts([]), do: []

  def content_to_parts(content) when is_list(content) do
    # Convert legacy format to ContentItems and format for Gemini (default)
    content_items = Enum.map(content, &legacy_item_to_content_item/1)
    |> Enum.filter(&(&1 != nil))

    ProviderAdapter.content_to_parts(content_items, :gemini)
  end

  @doc """
  Validates legacy content item format.
  """
  @spec valid_content_item?(map()) :: boolean()
  def valid_content_item?(%{type: type, content: content})
      when type in [:text, :image, :audio, :video, :document, :file] and 
           is_binary(content) and byte_size(content) > 0 do
    true
  end

  def valid_content_item?(_), do: false

  # Private helper functions

  @spec legacy_item_to_content_item(map()) :: ContentItem.t() | nil
  defp legacy_item_to_content_item(%{type: :text, content: text}) do
    ContentItem.from_text(text)
  end

  defp legacy_item_to_content_item(%{type: type, content: data, mime_type: mime_type}) 
       when type in [:image, :audio, :video, :document, :file] and is_binary(mime_type) do
    # For legacy content, decode base64 data since legacy format assumes base64 content
    decoded_data = case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data  # If not base64, use as-is
    end
    ContentItem.new(type, decoded_data, mime_type)
  end

  defp legacy_item_to_content_item(%{type: type, content: data}) 
       when type in [:image, :audio, :video, :document, :file] do
    # Infer MIME type for legacy compatibility
    mime_type = infer_legacy_mime_type(type)
    if mime_type do
      # For legacy content, decode base64 data since legacy format assumes base64 content
      decoded_data = case Base.decode64(data) do
        {:ok, decoded} -> decoded
        :error -> data  # If not base64, use as-is
      end
      ContentItem.new(type, decoded_data, mime_type)
    else
      nil
    end
  end

  defp legacy_item_to_content_item(_), do: nil

  @spec infer_legacy_mime_type(atom()) :: String.t() | nil
  defp infer_legacy_mime_type(:image), do: "image/png"
  defp infer_legacy_mime_type(:audio), do: "audio/wav"
  defp infer_legacy_mime_type(:video), do: "video/mp4"
  defp infer_legacy_mime_type(:document), do: "application/pdf"
  defp infer_legacy_mime_type(:file), do: "application/octet-stream"
  defp infer_legacy_mime_type(_), do: nil
end

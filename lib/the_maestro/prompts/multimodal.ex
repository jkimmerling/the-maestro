defmodule TheMaestro.Prompts.MultiModal do
  @moduledoc """
  Multi-modal prompt handling system that formats multimodal content for LLM providers.

  This module provides a simple interface for preparing multimodal content (text, images, 
  audio, video, documents, etc.) to be sent to LLM provider APIs. The LLM providers
  handle the actual interpretation and analysis of the content.

  ## Supported Content Types

  - `:text` - Text content and instructions
  - `:image` - Images, screenshots, diagrams  
  - `:audio` - Audio files, voice recordings
  - `:video` - Video content, screen recordings
  - `:document` - PDFs, Word docs, presentations
  - `:file` - Generic file attachments

  ## Usage

      content = [
        %{type: :text, content: "Analyze this error"},
        %{type: :image, content: base64_image_data, mime_type: "image/png"},
        %{type: :document, content: base64_pdf_data, mime_type: "application/pdf"}
      ]
      
      parts = MultiModal.content_to_parts(content)
      # Send parts directly to LLM provider
  """

  @type content_type :: :text | :image | :audio | :video | :document | :file
  @type content_item :: %{
          type: content_type(),
          content: String.t(),
          mime_type: String.t() | nil,
          metadata: map()
        }
  @type content_list :: [content_item()]
  @type part ::
          %{
            text: String.t()
          }
          | %{
              inline_data: %{
                mime_type: String.t(),
                data: String.t()
              }
            }

  @supported_content_types [:text, :image, :audio, :video, :document, :file]

  @doc """
  Returns the list of supported content types.
  """
  @spec supported_content_types() :: [content_type()]
  def supported_content_types, do: @supported_content_types

  @doc """
  Converts multimodal content items into LLM provider-compatible parts.

  This function formats content for direct consumption by LLM APIs without
  internal processing or analysis.

  ## Parameters

  - `content` - List of content items with type, content, and optional metadata

  ## Returns

  List of parts that can be sent directly to LLM provider APIs.
  """
  @spec content_to_parts(content_list()) :: [part()]
  def content_to_parts([]), do: []

  def content_to_parts(content) when is_list(content) do
    content
    |> Enum.filter(&valid_content_item?/1)
    |> Enum.map(&content_item_to_part/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Validates that a content item has the required structure.
  """
  @spec valid_content_item?(map()) :: boolean()
  def valid_content_item?(%{type: type, content: content})
      when type in @supported_content_types and is_binary(content) and byte_size(content) > 0 do
    true
  end

  def valid_content_item?(_), do: false

  @doc """
  Estimates the token usage for multimodal content.

  This provides a rough estimate based on content type and size.
  """
  @spec estimate_token_usage(content_list()) :: non_neg_integer()
  def estimate_token_usage([]), do: 0

  def estimate_token_usage(content) when is_list(content) do
    content
    |> Enum.map(&estimate_item_tokens/1)
    |> Enum.sum()
  end

  # Private functions

  @spec content_item_to_part(content_item()) :: part() | nil
  defp content_item_to_part(%{type: :text, content: text}) when is_binary(text) do
    %{text: text}
  end

  defp content_item_to_part(%{type: type, content: data, mime_type: mime_type})
       when type in [:image, :audio, :video, :document, :file] and is_binary(mime_type) do
    %{
      inline_data: %{
        mime_type: mime_type,
        data: data
      }
    }
  end

  defp content_item_to_part(%{type: type, content: data})
       when type in [:image, :audio, :video, :document, :file] do
    # Try to infer MIME type from content type
    mime_type = infer_mime_type(type)

    if mime_type do
      %{
        inline_data: %{
          mime_type: mime_type,
          data: data
        }
      }
    else
      nil
    end
  end

  defp content_item_to_part(_), do: nil

  @spec infer_mime_type(content_type()) :: String.t() | nil
  defp infer_mime_type(:image), do: "image/png"
  defp infer_mime_type(:audio), do: "audio/wav"
  defp infer_mime_type(:video), do: "video/mp4"
  defp infer_mime_type(:document), do: "application/pdf"
  defp infer_mime_type(:file), do: "application/octet-stream"
  defp infer_mime_type(_), do: nil

  @spec estimate_item_tokens(content_item()) :: non_neg_integer()
  defp estimate_item_tokens(%{type: :text, content: text}) do
    # Rough approximation: ~4 characters per token
    div(String.length(text), 4)
  end

  defp estimate_item_tokens(%{type: :image}) do
    # Images typically consume more tokens
    1000
  end

  defp estimate_item_tokens(%{type: type}) when type in [:audio, :video] do
    # Audio/video consume significant tokens
    2000
  end

  defp estimate_item_tokens(%{type: :document}) do
    # Documents vary but typically substantial
    1500
  end

  defp estimate_item_tokens(%{type: :file}) do
    # Generic files
    500
  end

  defp estimate_item_tokens(_), do: 0
end

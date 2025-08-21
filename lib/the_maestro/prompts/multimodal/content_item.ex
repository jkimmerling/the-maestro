defmodule TheMaestro.Prompts.MultiModal.ContentItem do
  @moduledoc """
  Data structure for representing multimodal content items.

  Content items represent different types of media that can be processed 
  and sent to LLM providers for analysis.
  """

  @typedoc """
  Supported content types for multimodal processing.
  """
  @type content_type :: :text | :image | :audio | :video | :document | :file

  @typedoc """
  Content item structure containing media data and metadata.
  """
  @type t :: %__MODULE__{
          type: content_type(),
          data: binary(),
          mime_type: String.t(),
          file_path: String.t() | nil,
          size: non_neg_integer(),
          metadata: map()
        }

  defstruct [
    :type,
    :data,
    :mime_type,
    :file_path,
    :size,
    metadata: %{}
  ]

  @doc """
  Creates a new content item from text content.
  """
  @spec from_text(String.t()) :: t()
  def from_text(text) when is_binary(text) do
    %__MODULE__{
      type: :text,
      data: text,
      mime_type: "text/plain",
      file_path: nil,
      size: byte_size(text),
      metadata: %{}
    }
  end

  @doc """
  Creates a new content item with all required fields.
  """
  @spec new(content_type(), binary(), String.t(), String.t() | nil, map()) :: t()
  def new(type, data, mime_type, file_path \\ nil, metadata \\ %{}) do
    %__MODULE__{
      type: type,
      data: data,
      mime_type: mime_type,
      file_path: file_path,
      size: byte_size(data),
      metadata: metadata
    }
  end

  @doc """
  Validates that a content item has all required fields.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{type: type, data: data, mime_type: mime_type})
      when is_atom(type) and is_binary(data) and is_binary(mime_type) and byte_size(data) > 0 do
    type in [:text, :image, :audio, :video, :document, :file]
  end

  def valid?(_), do: false
end

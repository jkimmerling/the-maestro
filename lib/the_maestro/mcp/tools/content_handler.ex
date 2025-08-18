defmodule TheMaestro.MCP.Tools.ContentHandler do
  @moduledoc """
  Rich Content Handler for processing MCP tool responses.

  This module provides comprehensive processing of MCP tool responses that may
  contain various content types including text, images, resources, audio, and
  binary data. It handles decoding, validation, security checks, and optimization
  for different agent types.

  ## Features

  - Multi-format content processing (text, images, resources, binary data)
  - Base64 decoding with size limits and validation
  - Security validation for suspicious content and path traversal
  - Content optimization for different agent capabilities
  - Memory-efficient handling of large content
  - Comprehensive error handling and logging

  ## Content Types Supported

  - **Text**: Plain text content from tool responses
  - **Images**: Base64-encoded images (PNG, JPEG, GIF, WebP)
  - **Resources**: File references with optional content
  - **Audio**: Base64-encoded audio data (WAV, MP3, etc.)
  - **Video**: Base64-encoded video data (MP4, WebM, etc.)
  - **Binary**: Raw binary data with MIME type information

  ## Security Features

  - Path traversal detection for resource URIs
  - Content size limits to prevent memory exhaustion
  - MIME type validation and sanitization
  - Suspicious content pattern detection
  """

  require Logger

  # Content processing result structure
  defmodule ProcessingResult do
    @moduledoc """
    Result of content processing with extracted metadata and processed blocks.
    """
    @type t :: %__MODULE__{
            text_content: String.t(),
            has_images: boolean(),
            has_resources: boolean(),
            has_binary: boolean(),
            processed_blocks: [ContentBlock.t()],
            total_size: non_neg_integer(),
            content_types: [atom()]
          }

    defstruct [
      :text_content,
      :has_images,
      :has_resources,
      :has_binary,
      :processed_blocks,
      :total_size,
      :content_types
    ]
  end

  # Individual content block structure
  defmodule ContentBlock do
    @moduledoc """
    Processed content block with type-specific metadata and content.
    """
    @type t :: %__MODULE__{
            type: atom(),
            content: String.t() | binary(),
            decoded_data: binary() | nil,
            mime_type: String.t() | nil,
            uri: String.t() | nil,
            size: non_neg_integer(),
            metadata: map()
          }

    defstruct [
      :type,
      :content,
      :decoded_data,
      :mime_type,
      :uri,
      :size,
      :metadata
    ]
  end

  # Security validation error
  defmodule SecurityError do
    @moduledoc """
    Security validation error with details.
    """
    @type t :: %__MODULE__{
            type: atom(),
            message: String.t(),
            details: map()
          }

    defstruct [:type, :message, :details]
  end

  # Configuration constants
  # 10MB limit for individual content blocks
  @max_content_size 10 * 1024 * 1024
  # 50MB limit for total content
  @max_total_size 50 * 1024 * 1024
  @supported_image_types ["image/png", "image/jpeg", "image/gif", "image/webp"]
  @supported_audio_types ["audio/wav", "audio/mp3", "audio/ogg", "audio/m4a"]
  @supported_video_types ["video/mp4", "video/webm", "video/avi", "video/mov"]

  @doc """
  Process MCP content array into structured format with metadata.

  Analyzes all content blocks, decodes base64 data, extracts text content,
  and provides comprehensive metadata about the content types present.

  ## Parameters

  - `content` - Array of MCP content blocks

  ## Returns

  `ProcessingResult.t()` with processed content and metadata

  ## Examples

      content = [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "image", "data" => "base64data", "mimeType" => "image/png"}
      ]
      
      result = ContentHandler.process_content(content)
      # result.text_content == "Hello"
      # result.has_images == true
      # length(result.processed_blocks) == 2
  """
  @spec process_content([map()]) :: ProcessingResult.t()
  def process_content(content) when is_list(content) do
    processed_blocks = Enum.map(content, &process_content_block/1)

    text_content =
      processed_blocks
      |> Enum.filter(&(&1.type in [:text, :resource]))
      |> Enum.map(& &1.content)
      |> Enum.join(" ")
      |> String.trim()

    content_types = Enum.map(processed_blocks, & &1.type) |> Enum.uniq()
    total_size = Enum.sum(Enum.map(processed_blocks, & &1.size))

    %ProcessingResult{
      text_content: text_content,
      has_images: :image in content_types,
      has_resources: :resource in content_types,
      has_binary: Enum.any?(content_types, &(&1 in [:audio, :video, :binary])),
      processed_blocks: processed_blocks,
      total_size: total_size,
      content_types: content_types
    }
  end

  def process_content(_),
    do: %ProcessingResult{
      text_content: "",
      has_images: false,
      has_resources: false,
      has_binary: false,
      processed_blocks: [],
      total_size: 0,
      content_types: []
    }

  @doc """
  Decode base64 content with validation and size limits.

  Safely decodes base64 data while enforcing size limits and validating
  the decoded content format.

  ## Parameters

  - `base64_data` - Base64 encoded data string
  - `mime_type` - Expected MIME type for validation

  ## Returns

  - `{:ok, decoded_binary}` on success
  - `{:error, SecurityError.t()}` on failure

  ## Examples

      {:ok, decoded} = ContentHandler.decode_base64_content("aGVsbG8=", "text/plain")
      # decoded == "hello"
  """
  @spec decode_base64_content(String.t(), String.t()) ::
          {:ok, binary()} | {:error, SecurityError.t()}
  def decode_base64_content(base64_data, mime_type) when is_binary(base64_data) do
    # Estimate decoded size (base64 is ~4/3 of original size)
    estimated_size = trunc(String.length(base64_data) * 0.75)

    if estimated_size > @max_content_size do
      {:error,
       %SecurityError{
         type: :content_too_large,
         message: "Content size exceeds limit of #{@max_content_size} bytes",
         details: %{estimated_size: estimated_size, limit: @max_content_size}
       }}
    else
      case Base.decode64(base64_data) do
        {:ok, decoded} ->
          if byte_size(decoded) > @max_content_size do
            {:error,
             %SecurityError{
               type: :content_too_large,
               message: "Decoded content size exceeds limit",
               details: %{actual_size: byte_size(decoded), limit: @max_content_size}
             }}
          else
            validate_decoded_content(decoded, mime_type)
          end

        :error ->
          {:error,
           %SecurityError{
             type: :invalid_base64,
             message: "Invalid base64 encoding",
             details: %{mime_type: mime_type}
           }}
      end
    end
  end

  def decode_base64_content(_, _),
    do:
      {:error,
       %SecurityError{
         type: :invalid_input,
         message: "Base64 data must be a string",
         details: %{}
       }}

  @doc """
  Extract text content from MCP content array.

  Combines text from text blocks and resource blocks into a single string.

  ## Parameters

  - `content` - Array of MCP content blocks

  ## Returns

  Combined text string

  ## Examples

      content = [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "resource", "resource" => %{"text" => "World"}}
      ]
      
      text = ContentHandler.extract_text_from_content(content)
      # text == "Hello World"
  """
  @spec extract_text_from_content([map()]) :: String.t()
  def extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.flat_map(&extract_text_from_block/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  def extract_text_from_content(_), do: ""

  @doc """
  Validate content for security issues.

  Checks for path traversal attempts, suspicious file access patterns,
  and potentially dangerous content.

  ## Parameters

  - `content` - Array of MCP content blocks

  ## Returns

  - `:ok` if content is safe
  - `{:error, SecurityError.t()}` if security issues found

  ## Examples

      # Safe content
      ContentHandler.validate_content_security([
        %{"type" => "text", "text" => "Safe content"}
      ])
      # :ok
      
      # Dangerous content
      ContentHandler.validate_content_security([
        %{"type" => "resource", "resource" => %{"uri" => "file:///etc/passwd"}}
      ])
      # {:error, %SecurityError{type: :suspicious_resource}}
  """
  @spec validate_content_security([map()]) :: :ok | {:error, SecurityError.t()}
  def validate_content_security(content) when is_list(content) do
    case Enum.find_value(content, &validate_content_block_security/1) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  def validate_content_security(_), do: :ok

  @doc """
  Optimize content for specific agent types and constraints.

  Adjusts content based on agent capabilities (text-only vs multimodal),
  size constraints, and performance requirements.

  ## Parameters

  - `content` - Array of MCP content blocks
  - `options` - Optimization options map

  ## Options

  - `:agent_type` - `:text_only` or `:multimodal` (default: `:multimodal`)
  - `:max_content_size` - Maximum total content size in bytes
  - `:preserve_images` - Whether to preserve images (default: `true`)
  - `:compress_large_text` - Whether to compress large text blocks

  ## Returns

  Optimized content array

  ## Examples

      # Optimize for text-only agent
      optimized = ContentHandler.optimize_content_for_agent(content, %{
        agent_type: :text_only,
        max_content_size: 100_000
      })
  """
  @spec optimize_content_for_agent([map()], map()) :: [map()]
  def optimize_content_for_agent(content, options \\ %{}) when is_list(content) do
    agent_type = Map.get(options, :agent_type, :multimodal)
    max_size = Map.get(options, :max_content_size, @max_total_size)

    content
    |> filter_content_by_agent_type(agent_type)
    |> limit_content_size(max_size)
    |> optimize_text_content(options)
  end

  ## Private Helper Functions

  defp process_content_block(%{"type" => "text", "text" => text}) do
    %ContentBlock{
      type: :text,
      content: text,
      decoded_data: nil,
      mime_type: "text/plain",
      uri: nil,
      size: String.length(text),
      metadata: %{}
    }
  end

  defp process_content_block(%{"type" => "image"} = block) do
    data = Map.get(block, "data", "")
    mime_type = Map.get(block, "mimeType", "image/png")

    {decoded_data, size} =
      case decode_base64_content(data, mime_type) do
        {:ok, decoded} -> {decoded, byte_size(decoded)}
        {:error, _} -> {nil, String.length(data)}
      end

    %ContentBlock{
      type: :image,
      content: "",
      decoded_data: decoded_data,
      mime_type: mime_type,
      uri: nil,
      size: size,
      metadata: %{
        format: extract_image_format(mime_type),
        has_valid_data: decoded_data != nil
      }
    }
  end

  defp process_content_block(%{"type" => "resource"} = block) do
    resource = Map.get(block, "resource", %{})
    uri = Map.get(resource, "uri", "")
    text = Map.get(resource, "text", "")
    mime_type = Map.get(resource, "mimeType", "text/plain")

    %ContentBlock{
      type: :resource,
      content: text,
      decoded_data: nil,
      mime_type: mime_type,
      uri: uri,
      size: String.length(text),
      metadata: %{
        uri_scheme: extract_uri_scheme(uri),
        has_content: text != ""
      }
    }
  end

  defp process_content_block(%{"type" => "audio"} = block) do
    data = Map.get(block, "data", "")
    mime_type = Map.get(block, "mimeType", "audio/wav")

    {decoded_data, size} =
      case decode_base64_content(data, mime_type) do
        {:ok, decoded} -> {decoded, byte_size(decoded)}
        {:error, _} -> {nil, String.length(data)}
      end

    %ContentBlock{
      type: :audio,
      content: "",
      decoded_data: decoded_data,
      mime_type: mime_type,
      uri: nil,
      size: size,
      metadata: %{
        format: extract_audio_format(mime_type),
        has_valid_data: decoded_data != nil
      }
    }
  end

  defp process_content_block(%{"type" => "video"} = block) do
    data = Map.get(block, "data", "")
    mime_type = Map.get(block, "mimeType", "video/mp4")

    {decoded_data, size} =
      case decode_base64_content(data, mime_type) do
        {:ok, decoded} -> {decoded, byte_size(decoded)}
        {:error, _} -> {nil, String.length(data)}
      end

    %ContentBlock{
      type: :video,
      content: "",
      decoded_data: decoded_data,
      mime_type: mime_type,
      uri: nil,
      size: size,
      metadata: %{
        format: extract_video_format(mime_type),
        has_valid_data: decoded_data != nil
      }
    }
  end

  defp process_content_block(block) do
    # Handle unknown or malformed content blocks
    type = Map.get(block, "type", "unknown")
    content = Map.get(block, "text") || Map.get(block, "data", "")

    %ContentBlock{
      type: :unknown,
      content: to_string(content),
      decoded_data: nil,
      mime_type: nil,
      uri: nil,
      size: String.length(to_string(content)),
      metadata: %{original_type: type, malformed: true}
    }
  end

  defp validate_decoded_content(decoded, mime_type) do
    cond do
      mime_type in @supported_image_types ->
        validate_image_content(decoded, mime_type)

      mime_type in @supported_audio_types ->
        validate_audio_content(decoded, mime_type)

      mime_type in @supported_video_types ->
        validate_video_content(decoded, mime_type)

      true ->
        # Generic validation for other types
        {:ok, decoded}
    end
  end

  defp validate_image_content(decoded, mime_type) do
    # Basic image validation - check for common image file signatures
    case mime_type do
      "image/png" ->
        if binary_part(decoded, 0, min(8, byte_size(decoded))) ==
             <<137, 80, 78, 71, 13, 10, 26, 10>> do
          {:ok, decoded}
        else
          {:error,
           %SecurityError{
             type: :invalid_image_format,
             message: "Invalid PNG format",
             details: %{}
           }}
        end

      "image/jpeg" ->
        if byte_size(decoded) >= 2 and binary_part(decoded, 0, 2) == <<255, 216>> do
          {:ok, decoded}
        else
          {:error,
           %SecurityError{
             type: :invalid_image_format,
             message: "Invalid JPEG format",
             details: %{}
           }}
        end

      _ ->
        # For other image types, just return the decoded data
        {:ok, decoded}
    end
  end

  defp validate_audio_content(decoded, _mime_type) do
    # Basic audio validation - check minimum size
    # Minimum WAV header size
    if byte_size(decoded) > 44 do
      {:ok, decoded}
    else
      {:error,
       %SecurityError{type: :invalid_audio_format, message: "Audio data too small", details: %{}}}
    end
  end

  defp validate_video_content(decoded, _mime_type) do
    # Basic video validation - check minimum size
    # Minimum for any video format
    if byte_size(decoded) > 100 do
      {:ok, decoded}
    else
      {:error,
       %SecurityError{type: :invalid_video_format, message: "Video data too small", details: %{}}}
    end
  end

  defp extract_text_from_block(%{"type" => "text", "text" => text}), do: [text]

  defp extract_text_from_block(%{"type" => "resource", "resource" => %{"text" => text}}),
    do: [text]

  defp extract_text_from_block(_), do: []

  defp validate_content_block_security(%{"type" => "resource", "resource" => resource}) do
    uri = Map.get(resource, "uri", "")

    cond do
      contains_path_traversal?(uri) ->
        %SecurityError{
          type: :path_traversal_attempt,
          message: "Path traversal detected in URI",
          details: %{uri: uri}
        }

      suspicious_resource?(uri) ->
        %SecurityError{
          type: :suspicious_resource,
          message: "Suspicious resource URI detected",
          details: %{uri: uri}
        }

      true ->
        nil
    end
  end

  defp validate_content_block_security(_), do: nil

  defp contains_path_traversal?(uri) do
    String.contains?(uri, "..") or
      String.contains?(uri, "%2e%2e") or
      String.contains?(uri, "%2E%2E")
  end

  defp suspicious_resource?(uri) do
    suspicious_paths = ["/etc/", "/proc/", "/sys/", "/root/", "/var/log/"]
    Enum.any?(suspicious_paths, &String.contains?(uri, &1))
  end

  defp filter_content_by_agent_type(content, :text_only) do
    Enum.filter(content, &(Map.get(&1, "type") in ["text", "resource"]))
  end

  defp filter_content_by_agent_type(content, _), do: content

  defp limit_content_size(content, max_size) do
    {result, _current_size} =
      Enum.reduce_while(content, {[], 0}, fn block, {acc, current_size} ->
        block_size = estimate_block_size(block)

        if current_size + block_size <= max_size do
          {:cont, {[block | acc], current_size + block_size}}
        else
          {:halt, {acc, current_size}}
        end
      end)

    Enum.reverse(result)
  end

  defp optimize_text_content(content, options) do
    max_text_length = Map.get(options, :max_text_length, 10_000)

    Enum.map(content, fn block ->
      case Map.get(block, "type") do
        "text" ->
          text = Map.get(block, "text", "")

          if String.length(text) > max_text_length do
            truncated = String.slice(text, 0, max_text_length - 20) <> "... [truncated]"
            Map.put(block, "text", truncated)
          else
            block
          end

        _ ->
          block
      end
    end)
  end

  defp estimate_block_size(%{"type" => "text", "text" => text}), do: String.length(text)

  defp estimate_block_size(%{"type" => "image", "data" => data}),
    do: trunc(String.length(data) * 0.75)

  defp estimate_block_size(%{"type" => "audio", "data" => data}),
    do: trunc(String.length(data) * 0.75)

  defp estimate_block_size(%{"type" => "video", "data" => data}),
    do: trunc(String.length(data) * 0.75)

  defp estimate_block_size(%{"type" => "resource", "resource" => %{"text" => text}}),
    do: String.length(text)

  # Default estimate
  defp estimate_block_size(_), do: 100

  defp extract_image_format("image/png"), do: :png
  defp extract_image_format("image/jpeg"), do: :jpeg
  defp extract_image_format("image/gif"), do: :gif
  defp extract_image_format("image/webp"), do: :webp
  defp extract_image_format(_), do: :unknown

  defp extract_audio_format("audio/wav"), do: :wav
  defp extract_audio_format("audio/mp3"), do: :mp3
  defp extract_audio_format("audio/ogg"), do: :ogg
  defp extract_audio_format("audio/m4a"), do: :m4a
  defp extract_audio_format(_), do: :unknown

  defp extract_video_format("video/mp4"), do: :mp4
  defp extract_video_format("video/webm"), do: :webm
  defp extract_video_format("video/avi"), do: :avi
  defp extract_video_format("video/mov"), do: :mov
  defp extract_video_format(_), do: :unknown

  defp extract_uri_scheme(uri) do
    case String.split(uri, ":", parts: 2) do
      [scheme, _] -> scheme
      _ -> "unknown"
    end
  end
end

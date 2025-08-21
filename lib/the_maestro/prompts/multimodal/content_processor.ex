defmodule TheMaestro.Prompts.MultiModal.ContentProcessor do
  @moduledoc """
  Content processing module for reading files and preparing multimodal content.

  This module handles file system operations, MIME type detection, and content
  preparation for multimodal prompts.
  """

  alias TheMaestro.Prompts.MultiModal.ContentItem

  # Maximum file size: 50MB
  @max_file_size 50 * 1024 * 1024

  @doc """
  Processes a file from the filesystem into a ContentItem.

  Reads the file, detects its MIME type, classifies the content type,
  and creates a properly structured ContentItem.

  ## Parameters

  - `file_path` - Absolute path to the file to process

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error reading or processing the file

  ## Examples

      iex> ContentProcessor.process_file("/path/to/image.png")
      {:ok, %ContentItem{type: :image, mime_type: "image/png", ...}}

      iex> ContentProcessor.process_file("/nonexistent/file.txt")
      {:error, "Cannot read file /nonexistent/file.txt: enoent"}
  """
  @spec process_file(String.t()) :: {:ok, ContentItem.t()} | {:error, String.t()}
  def process_file(file_path) when is_binary(file_path) do
    with {:ok, data} <- read_file_safely(file_path),
         {:ok, mime_type} <- determine_mime_type(file_path, data),
         content_type <- classify_content_type(mime_type) do
      content_item =
        ContentItem.new(
          content_type,
          data,
          mime_type,
          file_path,
          %{original_size: byte_size(data)}
        )

      {:ok, content_item}
    else
      {:error, reason} ->
        {:error, "Cannot read file #{file_path}: #{reason}"}
    end
  end

  @doc """
  Processes base64-encoded content into a ContentItem.

  Useful when content is already available as base64 data rather than
  needing to read from filesystem.

  ## Parameters

  - `base64_data` - Base64-encoded content
  - `mime_type` - MIME type of the content
  - `metadata` - Optional metadata map

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error decoding or processing the content
  """
  @spec process_base64(String.t(), String.t(), map()) ::
          {:ok, ContentItem.t()} | {:error, String.t()}
  def process_base64(base64_data, mime_type, metadata \\ %{}) do
    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        content_type = classify_content_type(mime_type)

        content_item =
          ContentItem.new(
            content_type,
            binary_data,
            mime_type,
            nil,
            Map.put(metadata, :source, :base64)
          )

        {:ok, content_item}

      :error ->
        {:error, "Invalid base64 data"}
    end
  end

  @doc """
  Validates file size and accessibility before processing.

  ## Parameters

  - `file_path` - Path to validate

  ## Returns

  - `:ok` - File is valid and accessible
  - `{:error, reason}` - File validation failed
  """
  @spec validate_file(String.t()) :: :ok | {:error, String.t()}
  def validate_file(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size, type: :regular}} ->
        if size <= @max_file_size do
          :ok
        else
          {:error, "File size #{size} bytes exceeds maximum allowed size #{@max_file_size} bytes"}
        end

      {:ok, %File.Stat{type: type}} ->
        {:error, "File is not a regular file (type: #{type})"}

      {:error, reason} ->
        {:error, "Cannot access file: #{reason}"}
    end
  end

  # Private functions

  @spec read_file_safely(String.t()) :: {:ok, binary()} | {:error, atom()}
  defp read_file_safely(file_path) do
    case validate_file(file_path) do
      :ok ->
        File.read(file_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec determine_mime_type(String.t(), binary()) :: {:ok, String.t()} | {:error, String.t()}
  defp determine_mime_type(file_path, data) do
    # First try to determine from file extension
    extension_mime = mime_type_from_extension(file_path)

    # Then try to verify with file content (magic numbers)
    case detect_mime_from_content(data) do
      {:ok, content_mime} ->
        # If extension and content agree, use that
        # If they disagree, prefer content detection but log warning
        if extension_mime == content_mime or extension_mime == "application/octet-stream" do
          {:ok, content_mime}
        else
          # Extension disagrees with content, use content detection
          {:ok, content_mime}
        end

      :unknown ->
        # Fall back to extension-based detection
        {:ok, extension_mime}
    end
  end

  @spec mime_type_from_extension(String.t()) :: String.t()
  defp mime_type_from_extension(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      # Images
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".bmp" -> "image/bmp"
      ".svg" -> "image/svg+xml"
      ".tiff" -> "image/tiff"
      ".tif" -> "image/tiff"
      # Documents
      ".pdf" -> "application/pdf"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".txt" -> "text/plain"
      ".md" -> "text/markdown"
      ".html" -> "text/html"
      ".htm" -> "text/html"
      # Audio
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".flac" -> "audio/flac"
      ".aac" -> "audio/aac"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      # Video
      ".mp4" -> "video/mp4"
      ".avi" -> "video/x-msvideo"
      ".mov" -> "video/quicktime"
      ".mkv" -> "video/x-matroska"
      ".webm" -> "video/webm"
      ".wmv" -> "video/x-ms-wmv"
      # Archives
      ".zip" -> "application/zip"
      ".tar" -> "application/x-tar"
      ".gz" -> "application/gzip"
      ".7z" -> "application/x-7z-compressed"
      # Default
      _ -> "application/octet-stream"
    end
  end

  @spec detect_mime_from_content(binary()) :: {:ok, String.t()} | :unknown
  defp detect_mime_from_content(data) do
    case data do
      # PNG
      <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>> ->
        {:ok, "image/png"}

      # JPEG
      <<0xFF, 0xD8, 0xFF, _rest::binary>> ->
        {:ok, "image/jpeg"}

      # GIF87a or GIF89a
      <<"GIF87a", _rest::binary>> ->
        {:ok, "image/gif"}

      <<"GIF89a", _rest::binary>> ->
        {:ok, "image/gif"}

      # WebP
      <<"RIFF", _size::32, "WEBP", _rest::binary>> ->
        {:ok, "image/webp"}

      # PDF
      <<"%PDF-", _rest::binary>> ->
        {:ok, "application/pdf"}

      # ZIP (and derivatives like DOCX)
      <<"PK", 0x03, 0x04, _rest::binary>> ->
        {:ok, "application/zip"}

      <<"PK", 0x05, 0x06, _rest::binary>> ->
        {:ok, "application/zip"}

      # MP3
      <<0xFF, 0xFB, _rest::binary>> ->
        {:ok, "audio/mpeg"}

      <<"ID3", _rest::binary>> ->
        {:ok, "audio/mpeg"}

      # WAV
      <<"RIFF", _size::32, "WAVE", _rest::binary>> ->
        {:ok, "audio/wav"}

      # MP4/M4A
      <<_size::32, "ftyp", _rest::binary>> ->
        {:ok, "video/mp4"}

      # Default case - unknown
      _ ->
        :unknown
    end
  end

  @spec classify_content_type(String.t()) :: ContentItem.content_type()
  defp classify_content_type(mime_type) do
    cond do
      String.starts_with?(mime_type, "image/") ->
        :image

      String.starts_with?(mime_type, "video/") ->
        :video

      String.starts_with?(mime_type, "audio/") ->
        :audio

      String.starts_with?(mime_type, "text/") ->
        :document

      mime_type in [
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ] ->
        :document

      true ->
        :file
    end
  end
end

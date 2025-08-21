defmodule TheMaestro.Prompts.MultiModal.MultiModalPrompt do
  @moduledoc """
  Main coordinator for multimodal prompt handling.

  This module provides the primary interface for creating and managing multimodal
  prompts that combine text, images, documents, and other media types for LLM providers.
  """

  alias TheMaestro.Prompts.MultiModal.{
    ContentItem,
    ContentProcessor,
    ProviderAdapter,
    MessageIntegrator
  }

  @typedoc """
  Supported content formats for multimodal prompts.
  """
  @type content_format :: :file_path | :base64 | :content_item

  @typedoc """
  Input content specification.
  """
  @type content_input :: 
          String.t() |  # file path or base64 data
          ContentItem.t() | # pre-processed content item
          %{type: atom(), content: String.t(), mime_type: String.t()}

  @doc """
  Creates a multimodal prompt from mixed content types and text.

  This is the main entry point for creating multimodal prompts. It accepts
  various content inputs and formats them for the specified provider.

  ## Parameters

  - `content_inputs` - List of content inputs (file paths, base64, ContentItems)
  - `prompt_text` - Text prompt to include with the content
  - `provider` - Target provider (:gemini, :openai, :claude)
  - `opts` - Additional options

  ## Options

  - `:role` - Message role (default: :user)
  - `:validate_files` - Whether to validate file access (default: true)
  - `:max_content_items` - Maximum number of content items (default: 20)

  ## Returns

  - `{:ok, message}` - Successfully created multimodal message
  - `{:error, reason}` - Error creating prompt

  ## Examples

      iex> MultiModalPrompt.create_multimodal_prompt(
      ...>   ["/path/to/image.png", base64_pdf],
      ...>   "Analyze these documents",
      ...>   :gemini
      ...> )
      {:ok, %{role: "user", parts: [...]}}
  """
  @spec create_multimodal_prompt([content_input()], String.t(), atom(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def create_multimodal_prompt(content_inputs, prompt_text, provider, opts \\ []) do
    role = Keyword.get(opts, :role, :user)
    validate_files = Keyword.get(opts, :validate_files, true)
    max_items = Keyword.get(opts, :max_content_items, 20)

    with :ok <- validate_inputs(content_inputs, max_items),
         {:ok, content_items} <- process_content_inputs(content_inputs, validate_files),
         {:ok, message} <- MessageIntegrator.create_multimodal_message(
                             content_items, prompt_text, provider, role) do
      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Processes a single file into a ContentItem.

  Convenience function for processing individual files.

  ## Parameters

  - `file_path` - Path to file to process
  - `validate` - Whether to validate file access (default: true)

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error processing file
  """
  @spec process_file(String.t(), boolean()) :: {:ok, ContentItem.t()} | {:error, String.t()}
  def process_file(file_path, validate \\ true) do
    if validate do
      case ContentProcessor.validate_file(file_path) do
        :ok -> ContentProcessor.process_file(file_path)
        {:error, reason} -> {:error, reason}
      end
    else
      ContentProcessor.process_file(file_path)
    end
  end

  @doc """
  Processes base64 content into a ContentItem.

  Convenience function for processing base64-encoded content.

  ## Parameters

  - `base64_data` - Base64-encoded content
  - `mime_type` - MIME type of the content
  - `metadata` - Optional metadata

  ## Returns

  - `{:ok, ContentItem.t()}` - Successfully processed content item
  - `{:error, reason}` - Error processing content
  """
  @spec process_base64(String.t(), String.t(), map()) :: {:ok, ContentItem.t()} | {:error, String.t()}
  def process_base64(base64_data, mime_type, metadata \\ %{}) do
    ContentProcessor.process_base64(base64_data, mime_type, metadata)
  end

  @doc """
  Enhances an existing message with multimodal content.

  Useful for adding multimodal capabilities to existing message structures.

  ## Parameters

  - `message` - Existing message to enhance
  - `content_inputs` - Content to add to the message
  - `provider` - Target provider for formatting
  - `opts` - Additional options

  ## Returns

  - `{:ok, enhanced_message}` - Message enhanced with multimodal content
  - `{:error, reason}` - Error enhancing message
  """
  @spec enhance_message(map(), [content_input()], atom(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def enhance_message(message, content_inputs, provider, opts \\ []) do
    validate_files = Keyword.get(opts, :validate_files, true)

    with {:ok, content_items} <- process_content_inputs(content_inputs, validate_files),
         {:ok, enhanced_message} <- MessageIntegrator.integrate_multimodal_content(
                                      message, content_items, provider) do
      {:ok, enhanced_message}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists supported content types for a provider.

  ## Parameters

  - `provider` - Provider to check support for

  ## Returns

  List of supported content types for the provider.
  """
  @spec supported_content_types(atom()) :: [ContentItem.content_type()]
  def supported_content_types(provider) do
    [:text, :image, :audio, :video, :document, :file]
    |> Enum.filter(&ProviderAdapter.supports_content_type?(provider, &1))
  end

  @doc """
  Estimates token usage for multimodal content.

  Provides rough estimates based on content types and sizes.

  ## Parameters

  - `content_items` - List of ContentItem structs
  - `prompt_text` - Text content
  - `provider` - Target provider (affects estimation)

  ## Returns

  Estimated token count.
  """
  @spec estimate_token_usage([ContentItem.t()], String.t(), atom()) :: non_neg_integer()
  def estimate_token_usage(content_items, prompt_text, _provider) do
    # Basic text estimation (4 chars per token)
    text_tokens = if prompt_text do
      div(String.length(prompt_text), 4)
    else
      0
    end

    # Content item estimation
    content_tokens = Enum.reduce(content_items, 0, fn item, acc ->
      acc + estimate_item_tokens(item)
    end)

    text_tokens + content_tokens
  end

  # Private functions

  @spec validate_inputs([content_input()], non_neg_integer()) :: :ok | {:error, String.t()}
  defp validate_inputs(content_inputs, max_items) do
    cond do
      length(content_inputs) > max_items ->
        {:error, "Too many content items (#{length(content_inputs)} > #{max_items})"}

      length(content_inputs) == 0 ->
        {:error, "No content items provided"}

      true ->
        :ok
    end
  end

  @spec process_content_inputs([content_input()], boolean()) ::
          {:ok, [ContentItem.t()]} | {:error, String.t()}
  defp process_content_inputs(content_inputs, validate_files) do
    content_inputs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {input, index}, {:ok, acc} ->
      case process_single_input(input, validate_files) do
        {:ok, content_item} ->
          {:cont, {:ok, [content_item | acc]}}

        {:error, reason} ->
          {:halt, {:error, "Error processing input #{index + 1}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  @spec process_single_input(content_input(), boolean()) ::
          {:ok, ContentItem.t()} | {:error, String.t()}
  defp process_single_input(input, validate_files) do
    case input do
      %ContentItem{} = item ->
        if ContentItem.valid?(item) do
          {:ok, item}
        else
          {:error, "Invalid ContentItem structure"}
        end

      %{type: type, content: content, mime_type: mime_type} ->
        case type do
          :text ->
            {:ok, ContentItem.from_text(content)}

          _ ->
            # Assume content is base64
            ContentProcessor.process_base64(content, mime_type)
        end

      path when is_binary(path) ->
        # Check if it looks like a file path or base64
        if String.contains?(path, "/") or File.exists?(path) do
          # Treat as file path
          process_file(path, validate_files)
        else
          {:error, "Input appears to be base64 but no MIME type provided"}
        end

      _ ->
        {:error, "Unsupported input format: #{inspect(input)}"}
    end
  end

  @spec estimate_item_tokens(ContentItem.t()) :: non_neg_integer()
  defp estimate_item_tokens(%ContentItem{type: :text, data: text}) do
    div(String.length(text), 4)
  end

  defp estimate_item_tokens(%ContentItem{type: :image}) do
    1000
  end

  defp estimate_item_tokens(%ContentItem{type: type}) when type in [:audio, :video] do
    2000
  end

  defp estimate_item_tokens(%ContentItem{type: :document}) do
    1500
  end

  defp estimate_item_tokens(%ContentItem{type: :file}) do
    500
  end

  defp estimate_item_tokens(_), do: 0
end
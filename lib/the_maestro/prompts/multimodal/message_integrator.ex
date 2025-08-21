defmodule TheMaestro.Prompts.MultiModal.MessageIntegrator do
  @moduledoc """
  Integration module for incorporating multimodal content into existing message structures.

  This module bridges multimodal content with the existing message handling system,
  allowing seamless integration with current provider implementations.
  """

  alias TheMaestro.Prompts.MultiModal.{ContentItem, ProviderAdapter}

  @typedoc """
  Standard message format used by the system.
  """
  @type message :: %{
          role: :user | :assistant | :system | :tool,
          content: String.t(),
          parts: [map()] | nil
        }

  @typedoc """
  Provider type for determining message format.
  """
  @type provider :: :gemini | :openai | :claude

  @doc """
  Integrates multimodal content into an existing message structure.

  This function takes a standard message and enhances it with multimodal content
  formatted for the specified provider.

  ## Parameters

  - `message` - Base message with role and content
  - `content_items` - List of ContentItem structs to integrate
  - `provider` - Target provider for formatting

  ## Returns

  - `{:ok, enhanced_message}` - Message enhanced with multimodal content
  - `{:error, reason}` - Error integrating content

  ## Examples

      iex> message = %{role: :user, content: "Analyze this image"}
      iex> MessageIntegrator.integrate_multimodal_content(message, [image_item], :gemini)
      {:ok, %{role: :user, content: "Analyze this image", parts: [...]}}
  """
  @spec integrate_multimodal_content(message(), [ContentItem.t()], provider()) ::
          {:ok, map()} | {:error, String.t()}
  def integrate_multimodal_content(message, content_items, provider) do
    case provider do
      :gemini ->
        {:ok, integrate_for_gemini(message, content_items)}

      :openai ->
        {:ok, integrate_for_openai(message, content_items)}

      :claude ->
        {:ok, integrate_for_claude(message, content_items)}

      _ ->
        {:error, "Unsupported provider: #{inspect(provider)}"}
    end
  end

  @doc """
  Creates a new multimodal message from content items and text.

  This function creates a complete message structure from scratch rather than
  enhancing an existing message.

  ## Parameters

  - `content_items` - List of ContentItem structs
  - `prompt_text` - Text content for the message
  - `provider` - Target provider for formatting
  - `role` - Message role (default: :user)

  ## Returns

  - `{:ok, message}` - Complete multimodal message
  - `{:error, reason}` - Error creating message
  """
  @spec create_multimodal_message([ContentItem.t()], String.t(), provider(), atom()) ::
          {:ok, map()} | {:error, String.t()}
  def create_multimodal_message(content_items, prompt_text, provider, role \\ :user) do
    case ProviderAdapter.format_for_provider(content_items, prompt_text, provider) do
      {:ok, formatted_message} ->
        # Convert provider role format to system role format
        system_role =
          case role do
            :user -> :user
            :assistant -> :assistant
            :system -> :system
            :tool -> :tool
            _ -> :user
          end

        enhanced_message = Map.put(formatted_message, :role, system_role)
        {:ok, enhanced_message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds content descriptions to message content for non-multimodal providers.

  When a provider doesn't support multimodal content, this function creates
  text descriptions of the content for inclusion in the message.
  """
  @spec add_content_descriptions(String.t(), [ContentItem.t()]) :: String.t()
  def add_content_descriptions(text_content, content_items) do
    descriptions =
      Enum.map(content_items, fn item ->
        file_info = if item.file_path, do: " (#{item.file_path})", else: ""
        "[#{String.upcase(to_string(item.type))}: #{item.mime_type}#{file_info}]"
      end)

    [text_content | descriptions]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.join("\n\n")
  end

  # Private functions for provider-specific integration

  @spec integrate_for_gemini(message(), [ContentItem.t()]) :: map()
  defp integrate_for_gemini(message, content_items) do
    # Gemini uses parts format
    text_parts =
      if message.content && message.content != "" do
        [%{text: message.content}]
      else
        []
      end

    media_parts = ProviderAdapter.content_to_parts(content_items, :gemini)

    message
    |> Map.put(:parts, text_parts ++ media_parts)
    |> convert_role_to_gemini()
  end

  @spec integrate_for_openai(message(), [ContentItem.t()]) :: map()
  defp integrate_for_openai(message, content_items) do
    # OpenAI uses content array format
    content_array =
      if message.content && message.content != "" do
        [%{type: "text", text: message.content}]
      else
        []
      end

    media_content = ProviderAdapter.content_to_parts(content_items, :openai)

    message
    |> Map.put(:content, content_array ++ media_content)
    |> convert_role_to_openai()
  end

  @spec integrate_for_claude(message(), [ContentItem.t()]) :: map()
  defp integrate_for_claude(message, content_items) do
    # Claude uses content array format similar to OpenAI
    content_array =
      if message.content && message.content != "" do
        [%{type: "text", text: message.content}]
      else
        []
      end

    media_content = ProviderAdapter.content_to_parts(content_items, :claude)

    message
    |> Map.put(:content, content_array ++ media_content)
    |> convert_role_to_claude()
  end

  # Role conversion helpers

  @spec convert_role_to_gemini(map()) :: map()
  defp convert_role_to_gemini(message) do
    gemini_role =
      case message.role do
        :user -> "user"
        :assistant -> "model"
        # Gemini doesn't have system role
        :system -> "user"
        # Tool results as model responses
        :tool -> "model"
      end

    Map.put(message, :role, gemini_role)
  end

  @spec convert_role_to_openai(map()) :: map()
  defp convert_role_to_openai(message) do
    openai_role =
      case message.role do
        :user -> "user"
        :assistant -> "assistant"
        :system -> "system"
        :tool -> "tool"
      end

    Map.put(message, :role, openai_role)
  end

  @spec convert_role_to_claude(map()) :: map()
  defp convert_role_to_claude(message) do
    claude_role =
      case message.role do
        :user -> "user"
        :assistant -> "assistant"
        # Claude handles system differently
        :system -> "user"
        # Tool results as user messages
        :tool -> "user"
      end

    Map.put(message, :role, claude_role)
  end
end

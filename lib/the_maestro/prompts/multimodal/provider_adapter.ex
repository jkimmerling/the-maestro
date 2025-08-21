defmodule TheMaestro.Prompts.MultiModal.ProviderAdapter do
  @moduledoc """
  Provider-specific formatting for multimodal content.

  This module handles the conversion of ContentItem structures into the specific
  formats required by different LLM providers (Gemini, OpenAI, Claude).
  """

  alias TheMaestro.Prompts.MultiModal.ContentItem

  @typedoc """
  Supported LLM providers for multimodal content.
  """
  @type provider :: :gemini | :openai | :claude

  @typedoc """
  Provider-specific part format.
  """
  @type provider_part :: map()

  @doc """
  Formats content items and prompt text for a specific provider.

  ## Parameters

  - `content_items` - List of ContentItem structs to format
  - `prompt_text` - Text prompt to include
  - `provider` - Target provider (:gemini, :openai, or :claude)

  ## Returns

  - `{:ok, formatted_message}` - Successfully formatted message for provider
  - `{:error, reason}` - Error formatting content for provider

  ## Examples

      iex> ProviderAdapter.format_for_provider([content_item], "Analyze this", :gemini)
      {:ok, %{role: "user", parts: [%{text: "Analyze this"}, %{inline_data: ...}]}}
  """
  @spec format_for_provider([ContentItem.t()], String.t(), provider()) :: 
          {:ok, map()} | {:error, String.t()}
  def format_for_provider(content_items, prompt_text, provider) do
    case provider do
      :gemini ->
        {:ok, format_for_gemini(content_items, prompt_text)}

      :openai ->
        {:ok, format_for_openai(content_items, prompt_text)}

      :claude ->
        {:ok, format_for_claude(content_items, prompt_text)}

      _ ->
        {:error, "Unsupported provider: #{inspect(provider)}"}
    end
  end

  @doc """
  Converts content items to provider-specific parts only (without message wrapper).

  Useful when integrating with existing message structures.
  """
  @spec content_to_parts([ContentItem.t()], provider()) :: [provider_part()]
  def content_to_parts(content_items, provider) do
    case provider do
      :gemini -> content_items_to_gemini_parts(content_items)
      :openai -> content_items_to_openai_parts(content_items)
      :claude -> content_items_to_claude_parts(content_items)
      _ -> []
    end
  end

  @doc """
  Checks if a provider supports a specific content type.
  """
  @spec supports_content_type?(provider(), ContentItem.content_type()) :: boolean()
  def supports_content_type?(:gemini, content_type) do
    content_type in [:text, :image, :document]
  end

  def supports_content_type?(:openai, content_type) do
    content_type in [:text, :image]
  end

  def supports_content_type?(:claude, content_type) do
    content_type in [:text, :image, :document]
  end

  def supports_content_type?(_, _), do: false

  # Gemini formatting

  @spec format_for_gemini([ContentItem.t()], String.t()) :: map()
  defp format_for_gemini(content_items, prompt_text) do
    parts = if prompt_text && prompt_text != "" do
      [%{text: prompt_text}]
    else
      []
    end

    media_parts = content_items_to_gemini_parts(content_items)

    %{
      role: "user",
      parts: parts ++ media_parts
    }
  end

  @spec content_items_to_gemini_parts([ContentItem.t()]) :: [map()]
  defp content_items_to_gemini_parts(content_items) do
    Enum.map(content_items, &content_item_to_gemini_part/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec content_item_to_gemini_part(ContentItem.t()) :: map() | nil
  defp content_item_to_gemini_part(%ContentItem{type: :text, data: text}) do
    %{text: text}
  end

  defp content_item_to_gemini_part(%ContentItem{type: type, data: data, mime_type: mime_type})
       when type in [:image, :document] do
    %{
      inline_data: %{
        data: Base.encode64(data),
        mime_type: mime_type
      }
    }
  end

  defp content_item_to_gemini_part(%ContentItem{type: type, file_path: file_path}) do
    # Fallback for unsupported content types
    file_description = if file_path, do: file_path, else: "content"
    %{text: "[#{String.upcase(to_string(type))} CONTENT: #{file_description}]"}
  end

  # OpenAI formatting

  @spec format_for_openai([ContentItem.t()], String.t()) :: map()
  defp format_for_openai(content_items, prompt_text) do
    content = if prompt_text && prompt_text != "" do
      [%{type: "text", text: prompt_text}]
    else
      []
    end

    media_content = content_items_to_openai_parts(content_items)

    %{
      role: "user",
      content: content ++ media_content
    }
  end

  @spec content_items_to_openai_parts([ContentItem.t()]) :: [map()]
  defp content_items_to_openai_parts(content_items) do
    Enum.map(content_items, &content_item_to_openai_part/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec content_item_to_openai_part(ContentItem.t()) :: map() | nil
  defp content_item_to_openai_part(%ContentItem{type: :text, data: text}) do
    %{type: "text", text: text}
  end

  defp content_item_to_openai_part(%ContentItem{type: :image, data: data, mime_type: mime_type}) do
    %{
      type: "image_url",
      image_url: %{
        url: "data:#{mime_type};base64,#{Base.encode64(data)}"
      }
    }
  end

  defp content_item_to_openai_part(%ContentItem{type: type, file_path: file_path}) do
    # OpenAI doesn't support other multimodal types, convert to text
    file_description = if file_path, do: file_path, else: "content"
    %{
      type: "text",
      text: "[#{String.upcase(to_string(type))} CONTENT: #{file_description}]"
    }
  end

  # Claude formatting

  @spec format_for_claude([ContentItem.t()], String.t()) :: map()
  defp format_for_claude(content_items, prompt_text) do
    content = if prompt_text && prompt_text != "" do
      [%{type: "text", text: prompt_text}]
    else
      []
    end

    media_content = content_items_to_claude_parts(content_items)

    %{
      role: "user",
      content: content ++ media_content
    }
  end

  @spec content_items_to_claude_parts([ContentItem.t()]) :: [map()]
  defp content_items_to_claude_parts(content_items) do
    Enum.map(content_items, &content_item_to_claude_part/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec content_item_to_claude_part(ContentItem.t()) :: map() | nil
  defp content_item_to_claude_part(%ContentItem{type: :text, data: text}) do
    %{type: "text", text: text}
  end

  defp content_item_to_claude_part(%ContentItem{type: :image, data: data, mime_type: mime_type}) do
    %{
      type: "image",
      source: %{
        type: "base64",
        media_type: mime_type,
        data: Base.encode64(data)
      }
    }
  end

  defp content_item_to_claude_part(%ContentItem{type: :document, data: data, mime_type: mime_type}) 
       when mime_type == "application/pdf" do
    %{
      type: "document",
      source: %{
        type: "base64",
        media_type: mime_type,
        data: Base.encode64(data)
      }
    }
  end

  defp content_item_to_claude_part(%ContentItem{type: type, file_path: file_path}) do
    # For unsupported types, convert to text description
    file_description = if file_path, do: file_path, else: "content"
    %{
      type: "text",
      text: "[#{String.upcase(to_string(type))} CONTENT: #{file_description}]"
    }
  end
end
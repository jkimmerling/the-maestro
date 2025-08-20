defmodule TheMaestro.Prompts.MultiModal.Processors.TextProcessor do
  @moduledoc """
  Specialized processor for text content including plain text, instructions,
  descriptions, and natural language content.
  """

  @doc """
  Processes text content with linguistic analysis and intent detection.
  """
  @spec process(map(), map()) :: map()
  def process(%{type: :text, content: content} = _item, _context) do
    %{
      intent: detect_intent(content),
      topics: extract_topics(content),
      complexity: assess_complexity(content),
      sentiment: analyze_sentiment(content),
      entities: extract_entities(content),
      language_quality: assess_language_quality(content),
      accessibility: enhance_text_accessibility(content)
    }
  end

  defp detect_intent(content) do
    cond do
      String.contains?(content, ["bug", "error", "issue", "problem"]) -> :debugging
      String.contains?(content, ["implement", "create", "build"]) -> :implementation
      String.contains?(content, ["explain", "what", "how"]) -> :explanation
      String.contains?(content, ["analyze", "review"]) -> :analysis
      true -> :general
    end
  end

  defp extract_topics(content) do
    # Simple keyword-based topic extraction
    topics = []

    topics =
      if String.contains?(content, ["auth", "login", "credential"]),
        do: [:authentication | topics],
        else: topics

    topics =
      if String.contains?(content, ["error", "fail", "issue"]),
        do: [:error | topics],
        else: topics

    topics =
      if String.contains?(content, ["security", "secure"]), do: [:security | topics], else: topics

    topics =
      if String.contains?(content, ["test", "testing"]), do: [:testing | topics], else: topics

    topics
  end

  defp assess_complexity(content) do
    word_count = String.split(content) |> length()

    cond do
      word_count < 10 -> :low
      word_count < 50 -> :moderate
      true -> :high
    end
  end

  defp analyze_sentiment(content) do
    cond do
      String.contains?(content, ["error", "fail", "problem", "issue"]) -> :negative
      String.contains?(content, ["good", "great", "success", "work"]) -> :positive
      true -> :neutral
    end
  end

  defp extract_entities(content) do
    # Simple entity extraction
    entities = []

    # File references
    entities =
      if Regex.match?(~r/\w+\.\w+/, content), do: [:file_reference | entities], else: entities

    # Function references
    entities =
      if Regex.match?(~r/\w+\(\)/, content), do: [:function_reference | entities], else: entities

    entities
  end

  defp assess_language_quality(_content) do
    %{
      readability: :good,
      grammar: :correct,
      clarity: :clear,
      completeness: :complete
    }
  end

  defp enhance_text_accessibility(_content) do
    %{
      reading_level: :college,
      structure_clear: true,
      context_sufficient: true,
      improvements_suggested: []
    }
  end
end

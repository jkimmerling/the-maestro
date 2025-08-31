defmodule TheMaestro.Streaming.GeminiHandler do
  @moduledoc """
  Google Gemini-specific streaming event handler.

  Handles Google Gemini API streaming events, including:
  - Text content streaming
  - Function call results
  - Usage statistics
  - Error conditions

  ## Gemini Event Format

  Gemini uses a different streaming format compared to OpenAI and Anthropic.
  Events typically contain `candidates` with `content` parts that include:
  - Text parts with `text` field
  - Function call parts with `functionCall` field
  - Usage information in separate fields

  ## State Management

  The handler maintains minimal state since Gemini typically sends
  more complete chunks rather than fine-grained deltas.

  ## Function Call Support

  Gemini function calls are typically sent as complete objects
  rather than streamed deltas, making them easier to handle.

  """

  use TheMaestro.Streaming.StreamHandler

  require Logger

  @doc """
  Handle Gemini streaming events.
  """
  def handle_event(%{event_type: "error", data: error_data}, _opts) do
    [error_message("Stream error: #{error_data}")]
  end

  def handle_event(%{event_type: "done", data: "[DONE]"}, _opts) do
    [done_message()]
  end

  def handle_event(%{event_type: event_type, data: data}, opts)
      when event_type in ["message", "delta"] do
    case safe_json_decode(data) do
      {:ok, event} -> handle_gemini_event(event, opts)
      {:error, reason} -> [error_message(reason)]
    end
  end

  def handle_event(_event, _opts) do
    # Ignore unknown event types
    []
  end

  # Handle parsed Gemini events
  defp handle_gemini_event(event, _opts) do
    messages = []

    # Extract candidates
    candidates = Map.get(event, "candidates", [])

    # Process each candidate
    messages =
      Enum.reduce(candidates, messages, fn candidate, acc ->
        handle_candidate(candidate, acc)
      end)

    # Extract usage information if present
    messages =
      if usage = Map.get(event, "usageMetadata") do
        usage_msg =
          usage_message(%{
            prompt_tokens: Map.get(usage, "promptTokenCount", 0),
            completion_tokens: Map.get(usage, "candidatesTokenCount", 0),
            total_tokens: Map.get(usage, "totalTokenCount", 0)
          })

        [usage_msg | messages]
      else
        messages
      end

    Enum.reverse(messages)
  end

  # Handle a single candidate
  defp handle_candidate(candidate, messages) do
    content = Map.get(candidate, "content", %{})
    parts = Map.get(content, "parts", [])

    # Process each part
    Enum.reduce(parts, messages, fn part, acc ->
      handle_content_part(part, acc)
    end)
  end

  # Handle different types of content parts
  defp handle_content_part(%{"text" => text}, messages) when is_binary(text) and text != "" do
    [content_message(text) | messages]
  end

  defp handle_content_part(%{"functionCall" => function_call}, messages) do
    alias TheMaestro.Streaming.{Function, FunctionCall}
    # Convert Gemini function call to standard format
    function_call_data = %FunctionCall{
      id: Map.get(function_call, "id", generate_call_id()),
      function: %Function{
        name: Map.get(function_call, "name"),
        arguments: Jason.encode!(Map.get(function_call, "args", %{}))
      }
    }

    [function_call_message([function_call_data]) | messages]
  end

  defp handle_content_part(_part, messages) do
    # Ignore unknown part types
    messages
  end

  # Generate a unique call ID for function calls
  defp generate_call_id do
    ("call_" <> :crypto.strong_rand_bytes(8)) |> Base.url_encode64(padding: false)
  end
end

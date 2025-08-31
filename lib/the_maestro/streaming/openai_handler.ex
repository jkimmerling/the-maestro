defmodule TheMaestro.Streaming.OpenAIHandler do
  @moduledoc """
  OpenAI-specific streaming event handler.

  Handles OpenAI ChatGPT API streaming events, including:
  - Text content deltas
  - Function call streaming
  - Usage statistics
  - Error conditions
  - Reasoning/thinking content (O3 models)

  ## OpenAI Event Types

  - `response.output_text.delta` - Streaming text content
  - `response.message_content.delta` - Message content deltas
  - `response.output_item.added` - New items (function calls, messages)
  - `response.function_call_arguments.delta` - Function call arguments
  - `response.output_item.done` - Completed items
  - `response.completed` - Stream completion with usage data

  ## State Management

  The handler maintains state in the process dictionary to track:
  - Function calls being assembled across multiple events
  - Text accumulation for reasoning JSON detection
  - Usage statistics from completion events

  ## Reasoning Support

  OpenAI O3 models may return structured reasoning JSON that needs special formatting:

      {"reasoning": "thinking process", "answer": "final answer"}

  This is converted to readable format:

      "Thinking: thinking process\\n\\nfinal answer"

  """

  use TheMaestro.Streaming.StreamHandler

  require Logger

  # Process dictionary keys for state management
  @function_calls_key :openai_function_calls
  @text_accumulator_key :openai_text_accumulator

  @doc """
  Handle OpenAI streaming events.
  """
  def handle_event(%{event_type: "error", data: error_data}, _opts) do
    [error_message("Stream error: #{error_data}")]
  end

  def handle_event(%{event_type: "done", data: "[DONE]"}, _opts) do
    # Clean up state and emit done message
    cleanup_state()
    [done_message()]
  end

  def handle_event(%{event_type: event_type, data: data}, opts) when event_type in ["message", "delta"] do
    case safe_json_decode(data) do
      {:ok, event} -> handle_openai_event(event, opts)
      {:error, reason} -> [error_message(reason)]
    end
  end

  def handle_event(_event, _opts) do
    # Ignore unknown event types
    []
  end

  # Handle parsed OpenAI events
  defp handle_openai_event(%{"type" => "response.output_text.delta"} = event, _opts) do
    case Map.get(event, "delta") do
      nil -> []
      delta -> handle_text_delta(delta)
    end
  end

  defp handle_openai_event(%{"type" => "response.message_content.delta"} = event, _opts) do
    case Map.get(event, "delta") do
      nil -> []
      delta -> handle_text_delta(delta)
    end
  end

  defp handle_openai_event(%{"type" => "response.output_item.added"} = event, _opts) do
    case get_in(event, ["item", "type"]) do
      "function_call" -> handle_function_call_start(event)
      "message" -> handle_message_item(event)
      _ -> []
    end
  end

  defp handle_openai_event(%{"type" => "response.function_call_arguments.delta"} = event, _opts) do
    handle_function_arguments_delta(event)
    [] # Don't emit messages until function call is complete
  end

  defp handle_openai_event(%{"type" => "response.output_item.done"} = event, _opts) do
    case get_in(event, ["item", "type"]) do
      "function_call" -> handle_function_call_done(event)
      "message" -> handle_message_done(event)
      _ -> []
    end
  end

  defp handle_openai_event(%{"type" => "response.completed"} = event, _opts) do
    messages = []

    # Extract usage data if present
    messages = if usage = get_in(event, ["response", "usage"]) do
      usage_msg = usage_message(%{
        prompt_tokens: Map.get(usage, "input_tokens", 0),
        completion_tokens: Map.get(usage, "output_tokens", 0),
        total_tokens: Map.get(usage, "total_tokens", 0)
      })
      [usage_msg | messages]
    else
      messages
    end

    # Clean up state
    cleanup_state()

    # Add done message
    [done_message(%{response_id: get_in(event, ["response", "id"])}) | messages]
  end

  defp handle_openai_event(event, _opts) do
    # Log unknown events for debugging
    Logger.debug("Unknown OpenAI event type: #{inspect(event)}")
    []
  end

  # Handle text deltas with reasoning detection
  defp handle_text_delta(delta) when is_binary(delta) do
    trimmed = String.trim(delta)

    if numeric_text?(trimmed) do
      [content_message(delta)]
    else
      handle_non_numeric_delta(delta)
    end
  end

  defp handle_text_delta(nil), do: []

  defp numeric_text?(text), do: Regex.match?(~r/^\d+(\.\d+)?$/, text)

  defp handle_non_numeric_delta(delta) do
    accumulator = get_text_accumulator()
    new_accumulator = accumulator <> delta

    case detect_reasoning_json(new_accumulator) do
      {:complete, reasoning, answer} ->
        put_text_accumulator("")
        base = [content_message("Thinking: #{reasoning}\n\n")]
        maybe_add_answer(base, answer)

      {:incomplete} ->
        put_text_accumulator(new_accumulator)
        []

      {:not_reasoning} ->
        put_text_accumulator("")
        [content_message(new_accumulator)]
    end
  end

  defp maybe_add_answer(messages, answer) when is_binary(answer) and answer != "" do
    [content_message(answer) | messages]
  end

  defp maybe_add_answer(messages, _), do: messages

  # Handle function call start
  defp handle_function_call_start(event) do
    item = Map.get(event, "item", %{})
    function_calls = get_function_calls()

    call_data = %{
      id: Map.get(item, "call_id") || Map.get(item, "id"),
      name: Map.get(item, "name", ""),
      arguments: Map.get(item, "arguments", "")
    }

    new_calls = Map.put(function_calls, call_data.id, call_data)
    put_function_calls(new_calls)

    [] # Don't emit until complete
  end

  # Handle function call arguments delta
  defp handle_function_arguments_delta(event) do
    item_id = Map.get(event, "item_id")
    delta = Map.get(event, "delta", "")

    if item_id do
      function_calls = get_function_calls()
      if Map.has_key?(function_calls, item_id) do
        call_data = Map.get(function_calls, item_id)
        updated_call = %{call_data | arguments: call_data.arguments <> delta}
        new_calls = Map.put(function_calls, item_id, updated_call)
        put_function_calls(new_calls)
      end
    end
  end

  # Handle completed function call
  defp handle_function_call_done(event) do
    item = Map.get(event, "item", %{})
    item_id = Map.get(item, "id")

    if item_id do
      function_calls = get_function_calls()
      if call_data = Map.get(function_calls, item_id) do
        # Update with final arguments if provided
        final_arguments = Map.get(item, "arguments", call_data.arguments)

        # Create function call message
        function_call = %{
          id: call_data.id,
          type: "function",
          function: %{
            name: call_data.name,
            arguments: final_arguments
          }
        }

        # Remove from tracking
        new_calls = Map.delete(function_calls, item_id)
        put_function_calls(new_calls)

        [function_call_message([function_call])]
      else
        []
      end
    else
      []
    end
  end

  # Handle message items (may contain reasoning)
  defp handle_message_item(event) do
    case get_in(event, ["item", "content"]) do
      [%{"type" => "text", "text" => text}] ->
        case parse_reasoning_json(text) do
          {:ok, reasoning, answer} ->
            base = [content_message("Thinking: #{reasoning}\n\n")]
            maybe_add_answer(base, answer)

          {:error, _} ->
            [content_message(text)]
        end

      _ ->
        []
    end
  end

  # Handle completed message items
  defp handle_message_done(event) do
    put_text_accumulator("") # Reset accumulator at message boundaries
    handle_message_item(event)
  end

  # Reasoning JSON detection and parsing
  defp detect_reasoning_json(text) do
    trimmed = String.trim(text)

    cond do
      # Check if it looks like JSON with reasoning
      String.starts_with?(trimmed, "{") and String.contains?(trimmed, "\"reasoning\"") ->
        case parse_reasoning_json(text) do
          {:ok, reasoning, answer} -> {:complete, reasoning, answer}
          {:error, _} -> {:incomplete}
        end

      # Check if it looks like the start of JSON
      String.starts_with?(trimmed, "{") ->
        {:incomplete}

      # Not JSON-like
      true ->
        {:not_reasoning}
    end
  end

  defp parse_reasoning_json(text) do
    case Jason.decode(text) do
      {:ok, %{"reasoning" => reasoning} = parsed} ->
        answer = Map.get(parsed, "answer") || Map.get(parsed, "response")
        answer_text = if is_list(answer) do
          Enum.join(answer, " ")
        else
          to_string(answer || "")
        end
        {:ok, reasoning, answer_text}
      {:ok, _} -> {:error, :not_reasoning}
      {:error, reason} -> {:error, reason}
    end
  end

  # State management helpers
  defp get_function_calls do
    Process.get(@function_calls_key, %{})
  end

  defp put_function_calls(calls) do
    Process.put(@function_calls_key, calls)
  end

  defp get_text_accumulator do
    Process.get(@text_accumulator_key, "")
  end

  defp put_text_accumulator(text) do
    Process.put(@text_accumulator_key, text)
  end

  defp cleanup_state do
    Process.delete(@function_calls_key)
    Process.delete(@text_accumulator_key)
  end
end

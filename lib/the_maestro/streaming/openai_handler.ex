defmodule TheMaestro.Streaming.OpenAIHandler do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
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
  @saw_text_delta_key :openai_saw_text_delta
  @emitted_calls_key :openai_emitted_calls

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

  # For ChatGPT backend, event_type may be "response.created", "response.delta", etc.
  # Decode JSON regardless of the event_type and route by the embedded "type" field.
  def handle_event(%{event_type: event_type, data: data}, opts)
      when is_binary(event_type) and is_binary(data) do
    case safe_json_decode(data) do
      {:ok, event} ->
        # Some streams omit the embedded "type" and rely solely on the SSE event name.
        routed =
          if is_binary(Map.get(event, "type")),
            do: event,
            else: Map.put(event, "type", event_type)

        handle_openai_event(routed, opts)

      {:error, reason} ->
        [error_message(reason)]
    end
  end

  def handle_event(_event, _opts) do
    # Ignore unknown event types
    []
  end

  # Handle parsed OpenAI events
  defp handle_openai_event(%{"type" => "response.output_text.delta"} = event, _opts) do
    case Map.get(event, "delta") do
      nil ->
        []

      delta ->
        # Mark that we have seen a delta for this content block to avoid
        # re‑emitting the same text on the corresponding *.done event.
        put_saw_text_delta(true)
        handle_text_delta(delta)
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
      "custom_tool_call" -> handle_custom_tool_call_start(event)
      "message" -> handle_message_item(event)
      _ -> []
    end
  end

  # Initial creation event – no content to emit
  defp handle_openai_event(%{"type" => "response.created"}, _opts), do: []

  # Newer Responses event forms: content_part delta/done with output_text
  defp handle_openai_event(%{"type" => "response.content_part.delta", "part" => part}, _opts) do
    case part do
      %{"type" => "output_text", "text" => text} when is_binary(text) ->
        put_saw_text_delta(true)
        handle_text_delta(text)

      _ ->
        []
    end
  end

  defp handle_openai_event(%{"type" => "response.content_part.done", "part" => part}, _opts) do
    case part do
      %{"type" => "output_text", "text" => text} when is_binary(text) ->
        # If we already streamed deltas for this part, skip re-emitting the full text
        if get_saw_text_delta() do
          put_saw_text_delta(false)
          []
        else
          [content_message(text)]
        end

      _ ->
        []
    end
  end

  # Model has started working but no content yet
  defp handle_openai_event(%{"type" => "response.in_progress"}, _opts) do
    [content_message("", %{thinking: true})]
  end

  # Additional ChatGPT events observed: 'content_part.added' and 'output_text.done'
  defp handle_openai_event(%{"type" => "response.content_part.added", "part" => part}, _opts) do
    case part do
      %{"type" => "output_text", "text" => text} when is_binary(text) and text != "" ->
        put_saw_text_delta(true)
        handle_text_delta(text)

      _ ->
        []
    end
  end

  defp handle_openai_event(%{"type" => "response.output_text.done", "text" => text}, _opts)
       when is_binary(text) do
    # If deltas have been streamed, avoid duplicate emission
    if get_saw_text_delta() do
      put_saw_text_delta(false)
      []
    else
      [content_message(text)]
    end
  end

  defp handle_openai_event(%{"type" => "response.function_call_arguments.delta"} = event, _opts) do
    handle_function_arguments_delta(event)
    # Don't emit messages until function call is complete
    []
  end

  # Some providers emit a terminal event for function call arguments without a
  # corresponding output_item.done. When we see this, try to emit a function_call
  # message using the accumulated name/arguments so downstream can execute tools.
  defp handle_openai_event(%{"type" => "response.function_call_arguments.done"} = event, _opts) do
    item_id = Map.get(event, "item_id")

    if item_id do
      function_calls = get_function_calls()

      if call_data = Map.get(function_calls, item_id) do
        alias TheMaestro.Streaming.{Function, FunctionCall}

        function_call = %FunctionCall{
          id: call_data.id || item_id,
          function: %Function{name: call_data.name, arguments: call_data.arguments}
        }

        # Emit only if we haven't already, otherwise wait for output_item.done
        if already_emitted?(function_call.id) do
          []
        else
          mark_emitted(function_call.id)
          [function_call_message([function_call])]
        end
      else
        []
      end
    else
      []
    end
  end

  defp handle_openai_event(%{"type" => "response.output_item.done"} = event, _opts) do
    case get_in(event, ["item", "type"]) do
      "function_call" -> handle_function_call_done(event)
      "custom_tool_call" -> handle_custom_tool_call_done(event)
      "message" -> handle_message_done(event)
      _ -> []
    end
  end

  defp handle_openai_event(%{"type" => "response.completed"} = event, _opts) do
    messages = []

    # If no deltas were emitted, try to extract any final text present in the response
    texts = extract_texts_from_completed(event)
    messages = Enum.reduce(texts, messages, fn t, acc -> [content_message(t) | acc] end)

    # Extract usage data if present
    messages =
      if usage = get_in(event, ["response", "usage"]) do
        usage_msg =
          usage_message(%{
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

  # ChatGPT backend sometimes emits a generic delta wrapper
  # Example payloads observed in the wild:
  #  - {"type":"response.delta","delta":{"type":"message","content":[{"type":"output_text","text":"Hello"}]}}
  #  - {"type":"response.delta","delta":{"type":"output_text","text":" world"}}
  #  - {"type":"response.delta","delta":{"type":"content_part","index":0,"content_part":{"type":"output_text","text":"!"}}}
  defp handle_openai_event(%{"type" => "response.delta", "delta" => delta}, _opts) do
    extract_texts_from_delta(delta)
    |> Enum.flat_map(&handle_text_delta/1)
  end

  defp handle_openai_event(event, opts) do
    # Optionally log unknown events for debugging
    if log_unknown_events?(opts) do
      Logger.debug("Unknown OpenAI event type: #{inspect(event)}")
    end

    []
  end

  # ===== Helpers for flexible delta shapes =====
  defp extract_texts_from_delta(%{"type" => "output_text", "text" => text}) when is_binary(text),
    do: [text]

  defp extract_texts_from_delta(%{"type" => "message", "content" => parts}) when is_list(parts) do
    parts
    |> Enum.flat_map(&extract_texts_from_delta/1)
  end

  defp extract_texts_from_delta(%{"type" => "content_part", "content_part" => part}),
    do: extract_texts_from_delta(part)

  defp extract_texts_from_delta(%{"type" => "text_delta", "text" => text}) when is_binary(text),
    do: [text]

  defp extract_texts_from_delta(%{"text" => text}) when is_binary(text), do: [text]
  defp extract_texts_from_delta(_), do: []

  defp extract_texts_from_completed(event) do
    cond do
      is_binary(text = get_in(event, ["response", "output_text"])) ->
        [text]

      is_list(out = get_in(event, ["response", "output"])) ->
        out
        |> Enum.flat_map(fn
          %{"type" => "message", "content" => parts} when is_list(parts) ->
            parts |> Enum.flat_map(&extract_texts_from_delta/1)

          _ ->
            []
        end)

      true ->
        []
    end
  end

  defp log_unknown_events?(opts) do
    Keyword.get(opts, :log_unknown_events, false) ||
      System.get_env("STREAM_LOG_UNKNOWN_EVENTS") in ["1", "true", "TRUE"] ||
      Application.get_env(:the_maestro, :log_unknown_stream_events, false)
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
        # Emit only the delta to avoid duplication when providers send cumulative snapshots
        put_text_accumulator("")
        [content_message(delta)]
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

    item_id = Map.get(item, "id")
    call_id = Map.get(item, "call_id")

    new_calls =
      function_calls
      |> maybe_put_key(item_id, call_data)
      |> maybe_put_key(call_id, call_data)

    if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
      IO.puts("\n🔧 function_call.start: item_id=#{inspect(item_id)}, call_id=#{inspect(call_id)}")
    end

    put_function_calls(new_calls)

    # Don't emit until complete
    []
  end

  # Handle function call arguments delta
  defp handle_function_arguments_delta(event) do
    item_id = Map.get(event, "item_id")
    delta = Map.get(event, "delta", "")

    if item_id do
      function_calls = get_function_calls()

      call_data = Map.get(function_calls, item_id)

      if call_data do
        updated_call = %{call_data | arguments: call_data.arguments <> delta}

        new_calls =
          function_calls
          |> maybe_put_key(item_id, updated_call)
          |> maybe_put_key(call_data.id, updated_call)

        if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
          IO.puts(
            "\n🔧 function_call.args.delta: item_id=#{inspect(item_id)} len+=#{byte_size(delta)}"
          )
        end

        put_function_calls(new_calls)
      end
    end
  end

  alias TheMaestro.Streaming.{Function, FunctionCall}

  # Handle completed function call
  defp handle_function_call_done(event) do
    item = Map.get(event, "item", %{})
    item_id = Map.get(item, "id")

    if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
      IO.puts("\n🔍 handle_function_call_done called")
      IO.puts("   item_id: #{inspect(item_id)}")
      IO.puts("   item: #{inspect(item)}")
    end

    if item_id do
      function_calls = get_function_calls()
      call_id = Map.get(item, "call_id")

      # Try to find call_data by item_id first, then by call_id
      call_data = Map.get(function_calls, item_id) || Map.get(function_calls, call_id)

      if call_data do
        # Update with final arguments if provided
        final_arguments = Map.get(item, "arguments", call_data.arguments)

        # Create function call message
        function_call = %FunctionCall{
          id: call_data.id,
          function: %Function{name: call_data.name, arguments: final_arguments}
        }

        # Remove from tracking (delete all potential keys)
        new_calls =
          function_calls
          |> maybe_delete_key(item_id)
          |> maybe_delete_key(call_id)

        put_function_calls(new_calls)

        # Avoid duplicate emission if arguments.done already emitted
        emit =
          if already_emitted?(function_call.id) do
            []
          else
            mark_emitted(function_call.id)
            [function_call_message([function_call])]
          end

        if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
          IO.puts("   Emitting function_call message: #{inspect(emit)}")
        end

        emit
      else
        if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
          IO.puts("   No call_data found in function_calls: #{inspect(function_calls)}")
        end

        []
      end
    else
      if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
        IO.puts("   No item_id found")
      end

      []
    end
  end

  # ===== Custom Tool Calls (e.g., ChatGPT Codex apply_patch) =====
  # Start tracking a custom tool call. Arguments may arrive only at `.done`.
  defp handle_custom_tool_call_start(event) do
    item = Map.get(event, "item", %{})
    function_calls = get_function_calls()

    call_data = %{
      id: Map.get(item, "call_id") || Map.get(item, "id"),
      name: Map.get(item, "name", ""),
      # For custom tools, the payload key is often `input` rather than `arguments`.
      arguments: Map.get(item, "input", "")
    }

    item_id = Map.get(item, "id")
    call_id = Map.get(item, "call_id")

    new_calls =
      function_calls
      |> maybe_put_key(item_id, call_data)
      |> maybe_put_key(call_id, call_data)

    put_function_calls(new_calls)
    []
  end

  # Emit a function_call message for a completed custom tool call.
  defp handle_custom_tool_call_done(event) do
    item = Map.get(event, "item", %{})
    item_id = Map.get(item, "id") || Map.get(item, "call_id")

    if item_id do
      function_calls = get_function_calls()
      final_input = Map.get(item, "input")

      if call_data =
           Map.get(function_calls, item_id) || Map.get(function_calls, Map.get(item, "call_id")) do
        updated_args =
          case final_input do
            nil -> call_data.arguments
            input when is_binary(input) -> input
            other -> to_string(other)
          end

        function_call = %FunctionCall{
          id: call_data.id,
          function: %Function{name: call_data.name, arguments: updated_args}
        }

        # Remove both keys if present
        new_calls =
          function_calls
          |> maybe_delete_key(item_id)
          |> maybe_delete_key(Map.get(item, "call_id"))

        put_function_calls(new_calls)

        [function_call_message([function_call])]
      else
        # If we didn't see a prior `added`, still emit using available fields
        id = item_id
        name = Map.get(item, "name", "")

        args =
          case final_input do
            nil -> ""
            input when is_binary(input) -> input
            other -> to_string(other)
          end

        function_call = %FunctionCall{id: id, function: %Function{name: name, arguments: args}}
        [function_call_message([function_call])]
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
    # Reset accumulator at message boundaries
    put_text_accumulator("")
    put_saw_text_delta(false)
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

        answer_text =
          if is_list(answer) do
            Enum.join(answer, " ")
          else
            to_string(answer || "")
          end

        {:ok, reasoning, answer_text}

      {:ok, _} ->
        {:error, :not_reasoning}

      {:error, reason} ->
        {:error, reason}
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
    Process.delete(@saw_text_delta_key)
    Process.delete(@emitted_calls_key)
  end

  # ChatGPT emits when a new content part is added; sometimes empty text
  defp maybe_put_key(map, nil, _value), do: map
  defp maybe_put_key(map, key, value), do: Map.put(map, key, value)

  defp maybe_delete_key(map, nil), do: map
  defp maybe_delete_key(map, key), do: Map.delete(map, key)

  defp get_saw_text_delta, do: Process.get(@saw_text_delta_key, false)
  defp put_saw_text_delta(val), do: Process.put(@saw_text_delta_key, val)

  defp get_emitted_calls, do: Process.get(@emitted_calls_key, MapSet.new())
  defp put_emitted_calls(set), do: Process.put(@emitted_calls_key, set)

  defp mark_emitted(id) when is_binary(id) do
    set = get_emitted_calls() |> MapSet.put(id)
    put_emitted_calls(set)
  end

  defp already_emitted?(id) when is_binary(id), do: MapSet.member?(get_emitted_calls(), id)
  defp already_emitted?(_), do: false
end

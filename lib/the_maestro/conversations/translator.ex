defmodule TheMaestro.Conversations.Translator do
  @moduledoc """
  Provider-agnostic chat translators.
  """

  @type canonical :: map()
  @type provider :: :openai | :anthropic | :gemini
  @type canonical_event :: map()

  @spec to_provider(canonical(), provider()) :: {:ok, list()} | {:error, term()}
  def to_provider(%{"messages" => msgs} = canon, :openai) do
    base = Enum.map(msgs, &to_openai_msg/1)
    {:ok, append_full_tool_history(base, canon, :openai)}
  end

  def to_provider(%{"messages" => msgs} = canon, :anthropic) do
    base = Enum.map(msgs, &to_anthropic_msg/1)
    {:ok, append_full_tool_history(base, canon, :anthropic)}
  end

  def to_provider(%{"messages" => msgs} = canon, :gemini) do
    base = Enum.map(msgs, &to_gemini_msg/1)
    {:ok, append_full_tool_history(base, canon, :gemini)}
  end

  def to_provider(_c, _), do: {:error, :invalid_canonical}

  @spec from_provider(map() | list() | binary(), provider()) ::
          {:ok, canonical()} | {:error, term()}
  def from_provider(text, _provider) when is_binary(text) do
    {:ok,
     %{
       "messages" => [
         %{"role" => "assistant", "content" => [%{"type" => "text", "text" => text}]}
       ]
     }}
  end

  def from_provider(msgs, :gemini) when is_list(msgs) do
    {:ok,
     %{
       "messages" =>
         Enum.map(msgs, fn %{"role" => role, "parts" => parts} ->
           %{"role" => role, "content" => Enum.map(parts, &gemini_part_to_text/1)}
         end)
     }}
  end

  def from_provider(msgs, _provider) when is_list(msgs) do
    {:ok,
     %{
       "messages" =>
         Enum.map(msgs, fn %{"role" => role, "content" => content} ->
           %{"role" => role, "content" => [%{"type" => "text", "text" => to_string(content)}]}
         end)
     }}
  end

  def from_provider(_payload, _), do: {:error, :unsupported_payload}

  @doc """
  Normalize provider-specific function calls/events into canonical event maps.

  Canonical event forms produced:
  - %{type: "function_call", calls: [%{"id" => id, "name" => name, "arguments" => args_json}]}
  - %{type: "function_call_output", "call_id" => id, "output" => output_json}
  - %{type: "usage", usage: %{prompt_tokens: n, completion_tokens: n, total_tokens: n}}
  - %{type: "content", delta: binary}
  """
  @spec events_to_canonical(provider(), any()) :: {:ok, [canonical_event()]} | {:error, term()}
  def events_to_canonical(:openai, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &openai_evt/1)}
  end

  def events_to_canonical(:anthropic, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &anthropic_evt/1)}
  end

  def events_to_canonical(:gemini, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &gemini_evt/1)}
  end

  def events_to_canonical(_, _), do: {:error, :unsupported_events}

  defp to_openai_msg(%{"role" => "tool", "tool_call_id" => call_id} = m) do
    text = extract_text(m)

    %{
      "role" => "tool",
      "tool_call_id" => call_id,
      "content" => text
    }
  end

  defp to_openai_msg(%{"role" => "assistant", "tool_calls" => tool_calls} = m)
       when is_list(tool_calls) do
    text = extract_text(m)

    # Convert tool_calls to OpenAI format
    openai_tool_calls =
      Enum.map(tool_calls, fn call ->
        %{
          "id" => call["id"],
          "type" => "function",
          "function" => %{
            "name" => call["name"],
            "arguments" => call["arguments"] || "{}"
          }
        }
      end)

    msg = %{"role" => "assistant", "tool_calls" => openai_tool_calls}

    # Only add content if there's actual text
    if String.trim(text) != "" do
      Map.put(msg, "content", text)
    else
      msg
    end
  end

  defp to_openai_msg(%{"role" => role} = m) do
    text = extract_text(m)
    %{"role" => role, "content" => text}
  end

  # Anthropic message conversion functions
  defp to_anthropic_msg(%{"role" => "tool", "tool_call_id" => call_id} = m) do
    text = extract_text(m)
    # Parse the response to get the actual result
    response_data =
      case Jason.decode(text) do
        {:ok, parsed} -> parsed
        _ -> text
      end

    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => call_id,
          "content" => response_data
        }
      ]
    }
  end

  defp to_anthropic_msg(%{"role" => "assistant", "tool_calls" => tool_calls} = m)
       when is_list(tool_calls) do
    text = extract_text(m)

    # Convert tool_calls to Anthropic tool_use blocks
    tool_use_blocks =
      Enum.map(tool_calls, fn call ->
        # Parse arguments if they're JSON string
        input =
          case Jason.decode(call["arguments"] || "{}") do
            {:ok, parsed} -> parsed
            _ -> %{}
          end

        %{
          "type" => "tool_use",
          "id" => call["id"],
          "name" => call["name"],
          "input" => input
        }
      end)

    content_blocks = []

    # Add text content if present
    content_blocks =
      if String.trim(text) != "" do
        [%{"type" => "text", "text" => text} | content_blocks]
      else
        content_blocks
      end

    # Add tool use blocks
    content_blocks = content_blocks ++ tool_use_blocks

    %{
      "role" => "assistant",
      "content" => content_blocks
    }
  end

  defp to_anthropic_msg(%{"role" => role} = m) do
    text = extract_text(m)

    %{
      "role" => role,
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp to_gemini_msg(%{"role" => "tool", "tool_call_id" => call_id} = m) do
    text = extract_text(m)
    # Parse the response to get the actual result
    response_data =
      case Jason.decode(text) do
        {:ok, parsed} -> parsed
        _ -> %{"output" => text}
      end

    # Extract function name from metadata if available
    function_name =
      case m do
        %{"_meta" => %{"function_name" => name}} -> name
        _ -> "tool_response"
      end

    %{
      "role" => "tool",
      "parts" => [
        %{
          "functionResponse" => %{
            "name" => function_name,
            "response" => response_data,
            "id" => call_id
          }
        }
      ]
    }
  end

  defp to_gemini_msg(%{"role" => "assistant", "tool_calls" => tool_calls} = m)
       when is_list(tool_calls) do
    text = extract_text(m)

    # Convert tool_calls to Gemini functionCall parts
    function_call_parts =
      Enum.map(tool_calls, fn call ->
        # Parse arguments if they're JSON string
        args =
          case Jason.decode(call["arguments"] || "{}") do
            {:ok, parsed} -> parsed
            _ -> %{}
          end

        %{
          "functionCall" => %{
            "name" => call["name"],
            "args" => args,
            "id" => call["id"]
          }
        }
      end)

    parts = []

    # Add text part if present
    parts =
      if String.trim(text) != "" do
        [%{"text" => text} | parts]
      else
        parts
      end

    # Add function call parts
    parts = parts ++ function_call_parts

    %{
      "role" => "model",
      "parts" => parts
    }
  end

  defp to_gemini_msg(%{"role" => role} = m) do
    text = extract_text(m)

    gemini_role =
      case role do
        "assistant" -> "model"
        other -> other
      end

    %{"role" => gemini_role, "parts" => [%{"text" => text}]}
  end

  defp extract_text(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{"type" => "text", "text" => t} -> t
      %{"text" => t} -> t
      t when is_binary(t) -> t
      _ -> ""
    end)
    |> Enum.join("\n")
  end

  defp extract_text(%{"content" => t}) when is_binary(t), do: t
  defp extract_text(_), do: ""
  defp gemini_part_to_text(%{"text" => t}), do: %{"type" => "text", "text" => t}
  defp gemini_part_to_text(%{"inlineData" => _}), do: %{"type" => "text", "text" => "[binary]"}
  defp gemini_part_to_text(_), do: %{"type" => "text", "text" => ""}

  # ==== Provider event normalizers ====
  defp openai_evt(%{type: :function_call, tool_calls: calls}) when is_list(calls) do
    [
      %{
        type: "function_call",
        calls:
          for c <- calls do
            case c do
              %TheMaestro.Domain.ToolCall{id: id, name: name, arguments: args} ->
                %{"id" => id, "name" => name, "arguments" => args || ""}

              %{id: id, name: name, arguments: args} ->
                %{"id" => id, "name" => name, "arguments" => args || ""}

              %{id: id, function: %{name: name, arguments: args}} ->
                %{"id" => id, "name" => name, "arguments" => args || ""}
            end
          end
      }
    ]
  end

  defp openai_evt(%{type: :function_call, function_call: calls}) when is_list(calls) do
    [
      %{
        type: "function_call",
        calls:
          for %{id: id, function: %{name: name, arguments: args}} <- calls do
            %{"id" => id, "name" => name, "arguments" => args || ""}
          end
      }
    ]
  end

  defp openai_evt(%{type: :usage, usage: usage}) do
    usage_map = if is_struct(usage), do: Map.from_struct(usage), else: usage
    [%{type: "usage", usage: usage_map}]
  end

  defp openai_evt(%{type: :content, content: delta}) when is_binary(delta),
    do: [%{type: "content", delta: delta}]

  defp openai_evt(_), do: []

  defp anthropic_evt(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    json = Jason.encode!(input)
    [%{type: "function_call", calls: [%{"id" => id, "name" => name, "arguments" => json}]}]
  end

  defp anthropic_evt(%{"type" => "input_json_delta", "delta" => delta}) when is_binary(delta) do
    [%{type: "content", delta: delta}]
  end

  defp anthropic_evt(%{"type" => "message_delta", "usage" => usage}) when is_map(usage) do
    # Map anthropic usage (input_tokens/output_tokens) to canonical keys when present
    usage2 =
      usage
      |> Map.new()
      |> case do
        %{"input_tokens" => p, "output_tokens" => c} ->
          %{prompt_tokens: p, completion_tokens: c, total_tokens: (p || 0) + (c || 0)}

        %{:input_tokens => p, :output_tokens => c} ->
          %{prompt_tokens: p, completion_tokens: c, total_tokens: (p || 0) + (c || 0)}

        other ->
          other
      end

    [%{type: "usage", usage: usage2}]
  end

  defp anthropic_evt(_), do: []

  defp gemini_evt(%{"functionCall" => %{"name" => name} = fc}) do
    args = Map.get(fc, "args") || %{}

    [
      %{
        type: "function_call",
        calls: [
          %{"id" => Ecto.UUID.generate(), "name" => name, "arguments" => Jason.encode!(args)}
        ]
      }
    ]
  end

  defp gemini_evt(%{"candidates" => _} = _chunk), do: []

  defp gemini_evt(%{"text" => delta}) when is_binary(delta),
    do: [%{type: "content", delta: delta}]

  defp gemini_evt(_), do: []

  # ==== Tool history transfer for provider swaps ====
  # Append a human-readable, full-session tool history (calls + outputs) so that
  # a different provider can faithfully see what happened earlier.
  defp append_full_tool_history(msgs, %{"tool_history" => hist} = _canon, provider)
       when is_list(hist) and hist != [] do
    text = build_full_tool_history_text(hist)
    msgs ++ split_tool_history_into_messages(text, provider)
  end

  defp append_full_tool_history(msgs, canon, provider) do
    # Fallback to last-turn event trace if there is no rolling history yet
    case canon do
      %{"events" => events} when is_list(events) and events != [] ->
        trace = build_tool_trace_text(events)

        if trace == "" do
          msgs
        else
          msgs ++ [tool_trace_msg(trace, provider)]
        end

      _ ->
        msgs
    end
  end

  defp tool_trace_msg(text, :gemini), do: %{"role" => "user", "parts" => [%{"text" => text}]}

  defp tool_trace_msg(text, _),
    do: %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}

  defp build_tool_trace_text(events) do
    events
    |> Enum.flat_map(&tool_calls_from_event/1)
    |> format_tool_trace()
  end

  defp format_history_entry(entry) do
    provider = fetch(entry, :provider, "")
    at = fetch(entry, :at)
    calls = fetch(entry, :calls, [])
    outputs = fetch(entry, :outputs, [])

    header = history_header(provider, at)
    lines = [header | history_call_lines(calls) ++ history_output_lines(outputs)]
    Enum.join(lines, "\n")
  end

  defp history_header(provider, at) when is_integer(at),
    do: "Turn @#{at} provider=#{provider}"

  defp history_header(provider, _), do: "Turn provider=#{provider}"

  defp history_call_lines(calls) do
    Enum.map(calls, fn call ->
      name = fetch(call, :name, "")
      args = fetch(call, :arguments, "{}")
      "- call #{name}(#{truncate_args(args)})"
    end)
  end

  defp history_output_lines(outputs) do
    Enum.map(outputs, fn output ->
      id = fetch(output, :id, "")
      data = fetch(output, :output, "")
      "  output[#{id}]: #{truncate_args(data)}"
    end)
  end

  defp tool_calls_from_event(%{type: :function_call, tool_calls: calls}) when is_list(calls),
    do: calls

  defp tool_calls_from_event(%{"type" => :function_call, "tool_calls" => calls})
       when is_list(calls),
       do: calls

  defp tool_calls_from_event(%{"type" => "function_call", "tool_calls" => calls})
       when is_list(calls),
       do: calls

  defp tool_calls_from_event(_), do: []

  defp format_tool_trace([]), do: ""

  defp format_tool_trace(calls) do
    lines =
      Enum.map(calls, fn call ->
        name = fetch(call, :name, "")
        args = fetch(call, :arguments, "{}")
        "- #{name}(#{truncate_args(args)})"
      end)

    [
      "Previous tool calls (Context7 MCP):",
      Enum.join(lines, "\n")
    ]
    |> Enum.join("\n")
  end

  defp fetch(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp truncate_args(args) when is_binary(args) do
    s = String.trim(args)
    if String.length(s) > 200, do: String.slice(s, 0, 200) <> "…", else: s
  end

  defp truncate_args(%{} = m) do
    case Jason.encode(m) do
      {:ok, json} -> truncate_args(json)
      {:error, _} -> "{}"
    end
  end

  defp truncate_args(other), do: to_string(other)
  # keep module open for history helpers below

  defp build_full_tool_history_text(hist) do
    hist
    |> Enum.map(&format_history_entry/1)
    |> Enum.join("\n\n")
  end

  defp split_tool_history_into_messages(text, :gemini) do
    chunks = chunk_text(text, 3500)
    Enum.map(chunks, fn t -> %{"role" => "user", "parts" => [%{"text" => t}]} end)
  end

  defp split_tool_history_into_messages(text, _provider) do
    chunks = chunk_text(text, 3500)

    Enum.map(chunks, fn t ->
      %{"role" => "user", "content" => [%{"type" => "text", "text" => t}]}
    end)
  end

  defp chunk_text(text, max) when is_binary(text) and is_integer(max) do
    if String.length(text) <= max do
      [text]
    else
      do_chunk(text, max, []) |> Enum.reverse()
    end
  end

  defp do_chunk(<<>>, _m, acc), do: acc

  defp do_chunk(text, m, acc) do
    {chunk, rest} = String.split_at(text, m)
    do_chunk(rest, m, [chunk | acc])
  end
end

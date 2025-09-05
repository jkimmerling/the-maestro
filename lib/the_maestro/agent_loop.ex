defmodule TheMaestro.AgentLoop do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Warning.IoInspect
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  @moduledoc """
  Backend agent loop that mirrors Codex tool-turn behavior without LiveView.

  - Sends initial prompt to the provider (Responses API)
  - Streams events, accumulating function_call(s) and partial answer
  - On response.completed: if tool calls exist, executes them and posts a follow-up
    with function_call_output items, streaming the continuation to completion
  - Returns the final text and metadata (tools used)
  """

  alias TheMaestro.Provider

  @type result :: %{
          final_text: String.t(),
          tools: list(map()),
          usage: map()
        }

  @spec run_turn(:openai, String.t(), String.t(), [map()], keyword()) ::
          {:ok, result} | {:error, term()}
  def run_turn(:openai, session_name, model, messages, opts \\ []) when is_list(messages) do
    adapter = Keyword.get(opts, :streaming_adapter)
    session_uuid = Ecto.UUID.generate()

    stream_opts =
      [model: model, session_uuid: session_uuid] ++
        if adapter, do: [streaming_adapter: adapter], else: []

    with {:ok, stream} <- Provider.stream_chat(:openai, session_name, messages, stream_opts) do
      # First turn: capture tool calls and partial answer
      {calls, answer, usage} = drain_stream(stream, :openai)
      calls = dedup_calls_by_id(calls)

      if calls == [] do
        # No tool call: do a short second prompt to ask it to complete? No, we are done.
        {:ok, %{final_text: answer, tools: [], usage: usage || %{}}}
      else
        # Execute tools and post function_call_output
        items = build_function_call_outputs(calls, answer, messages)

        followup_opts =
          [model: model, session_uuid: session_uuid] ++
            if adapter, do: [streaming_adapter: adapter], else: []

        case TheMaestro.Providers.OpenAI.Streaming.stream_tool_followup(
               session_name,
               items,
               followup_opts
             ) do
          {:ok, stream2} ->
            {_calls2, answer2, usage2} = drain_stream(stream2, :openai)
            {:ok, %{final_text: answer2, tools: calls, usage: usage2 || %{}}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @spec run_turn(:anthropic, String.t(), String.t(), [map()], keyword()) ::
          {:ok, result} | {:error, term()}
  def run_turn(:anthropic, session_name, model, messages, opts) when is_list(messages) do
    adapter = Keyword.get(opts, :streaming_adapter)

    stream_opts =
      [model: model] ++ if(adapter, do: [streaming_adapter: adapter], else: [])

    with {:ok, stream} <- Provider.stream_chat(:anthropic, session_name, messages, stream_opts) do
      {calls, answer, usage} = drain_stream_generic(stream, :anthropic)
      calls = dedup_calls_by_id(calls)

      if calls == [] do
        {:ok, %{final_text: answer, tools: [], usage: usage || %{}}}
      else
        # Build Anthropic follow-up items: tool_use + tool_result path
        {anth_msgs, _outputs} = build_anthropic_tool_followup(messages, calls)

        case TheMaestro.Providers.Anthropic.Streaming.stream_tool_followup(
               session_name,
               anth_msgs,
               model: model
             ) do
          {:ok, stream2} ->
            {_calls2, answer2, usage2} = drain_stream_generic(stream2, :anthropic)
            {:ok, %{final_text: answer2, tools: calls, usage: usage2 || %{}}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp drain_stream(stream, _provider) do
    # Parse SSE events directly to avoid UI pipeline dependencies
    sse = TheMaestro.Providers.Http.StreamingAdapter.parse_sse_events(stream)

    # Debug: log events if requested
    if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
      IO.puts("\n🔍 Streaming events:")

      Enum.each(sse, fn ev ->
        IO.inspect(ev, label: "Event", limit: :infinity)
      end)
    end

    messages =
      Stream.flat_map(sse, fn ev ->
        TheMaestro.Streaming.OpenAIHandler.handle_event(ev, [])
      end)

    Enum.reduce(messages, {[], "", %{}}, fn msg, {calls, text, usage} ->
      # Debug messages if requested
      if System.get_env("DEBUG_STREAM_EVENTS") == "1" do
        IO.inspect(msg, label: "Message")
      end

      case msg.type do
        :function_call ->
          new_calls =
            (msg.function_call || [])
            |> Enum.map(fn fc ->
              %{"id" => fc.id, "name" => fc.function.name, "arguments" => fc.function.arguments}
            end)

          {calls ++ new_calls, text, usage}

        :content ->
          {calls, text <> (msg.content || ""), usage}

        :usage ->
          {calls, text, msg.usage || usage}

        :done ->
          {calls, text, usage}

        _ ->
          {calls, text, usage}
      end
    end)
  end

  defp drain_stream_generic(stream, provider) do
    messages = TheMaestro.Streaming.parse_stream(stream, provider, log_unknown_events: true)

    Enum.reduce(messages, {[], "", %{}}, fn msg, {calls, text, usage} ->
      case msg.type do
        :function_call ->
          new_calls =
            (msg.function_call || [])
            |> Enum.map(fn fc ->
              %{"id" => fc.id, "name" => fc.function.name, "arguments" => fc.function.arguments}
            end)

          {calls ++ new_calls, text, usage}

        :content ->
          {calls, text <> (msg.content || ""), usage}

        :usage ->
          {calls, text, msg.usage || usage}

        :done ->
          {calls, text, usage}

        _ ->
          {calls, text, usage}
      end
    end)
  end

  defp build_function_call_outputs(calls, prior_answer_text, original_messages) do
    base_cwd = File.cwd!()

    assistant_msg =
      case prior_answer_text || "" do
        "" ->
          []

        text ->
          [
            %{
              "type" => "message",
              "role" => "assistant",
              "content" => [%{"type" => "output_text", "text" => text}]
            }
          ]
      end

    user_msgs =
      original_messages
      |> Enum.filter(&(Map.get(&1, "role") == "user" or Map.get(&1, :role) == "user"))
      |> Enum.map(fn m ->
        text = Map.get(m, "content") || Map.get(m, :content) || ""

        %{
          "type" => "message",
          "role" => "user",
          "content" => [%{"type" => "input_text", "text" => to_string(text)}]
        }
      end)

    fc_and_outputs =
      Enum.flat_map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        # 1) Include the original function_call item so ChatGPT can correlate call_id
        func_item = %{
          "type" => "function_call",
          "call_id" => id,
          "name" => name,
          "arguments" => args || ""
        }

        # 2) Execute tool and include the function_call_output item
        output =
          case String.downcase(name || "") do
            "shell" ->
              with {:ok, json} <- Jason.decode(args || "{}"),
                   {:ok, payload} <- TheMaestro.Tools.Shell.run(json, base_cwd: base_cwd) do
                payload
              else
                _ ->
                  Jason.encode!(%{
                    "output" => "shell error",
                    "metadata" => %{"exit_code" => 1, "duration_seconds" => 0.0}
                  })
              end

            "apply_patch" ->
              with {:ok, json} <- Jason.decode(args || "{}"),
                   input when is_binary(input) <- Map.get(json, "input"),
                   {:ok, payload} <- TheMaestro.Tools.ApplyPatch.run(input, base_cwd: base_cwd) do
                payload
              else
                _ ->
                  Jason.encode!(%{
                    "output" => "apply_patch error",
                    "metadata" => %{"exit_code" => 1, "duration_seconds" => 0.0}
                  })
              end

            _ ->
              Jason.encode!(%{
                "output" => "unsupported tool",
                "metadata" => %{"exit_code" => 1, "duration_seconds" => 0.0}
              })
          end

        out_item = %{"type" => "function_call_output", "call_id" => id, "output" => output}

        [func_item, out_item]
      end)

    # Order: last user message(s) -> prior assistant text -> function_call + output
    user_msgs ++ assistant_msg ++ fc_and_outputs
  end

  defp dedup_calls_by_id(calls) when is_list(calls) do
    calls
    |> Enum.uniq_by(& &1["id"])
  end

  # ===== Anthropic follow-up builders =====
  defp build_anthropic_tool_followup(original_messages, calls) do
    base_cwd = File.cwd!()

    # Assistant tool_use content from pending calls
    tool_uses =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        input =
          case Jason.decode(args || "") do
            {:ok, parsed} -> parsed
            _ -> %{}
          end

        %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
      end)

    # Execute tools and build tool_results
    outputs =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        case String.downcase(name || "") do
          "bash" ->
            with {:ok, json} <- Jason.decode(args || "{}"),
                 cmd when is_binary(cmd) <- Map.get(json, "command") do
              timeout_ms =
                case Map.get(json, "timeout") do
                  t when is_integer(t) -> t
                  t when is_float(t) -> trunc(t)
                  _ -> nil
                end

              shell_args =
                %{"command" => ["bash", "-lc", cmd]}
                |> maybe_put_timeout(shell_timeout: timeout_ms)

              case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid bash arguments"}}
            end

          "shell" ->
            with {:ok, json} <- Jason.decode(args || "{}") do
              case TheMaestro.Tools.Shell.run(json, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid shell arguments"}}
            end

          other ->
            {id, {:error, "unsupported tool: #{other}"}}
        end
      end)

    tool_results =
      Enum.map(outputs, fn {id, result} ->
        case result do
          {:ok, payload} -> %{"type" => "tool_result", "tool_use_id" => id, "content" => payload}
          {:error, reason} -> %{"type" => "tool_result", "tool_use_id" => id, "content" => to_string(reason)}
        end
      end)

    # Use the last user message as context
    last_user =
      original_messages
      |> Enum.reverse()
      |> Enum.find(fn m -> (Map.get(m, "role") || Map.get(m, :role)) == "user" end)

    last_user_blocks =
      case last_user do
        %{} ->
          text = Map.get(last_user, "content") || Map.get(last_user, :content) || ""
          [%{"type" => "text", "text" => to_string(text)}]

        _ ->
          [%{"type" => "text", "text" => ""}]
      end

    anth_messages =
      [
        %{"role" => "user", "content" => last_user_blocks},
        %{"role" => "assistant", "content" => tool_uses},
        %{"role" => "user", "content" => tool_results}
      ]

    {anth_messages, outputs}
  end

  defp maybe_put_timeout(map, shell_timeout: nil), do: map
  defp maybe_put_timeout(map, shell_timeout: t) when is_integer(t) and t > 0,
    do: Map.put(map, "timeout_ms", t)
end

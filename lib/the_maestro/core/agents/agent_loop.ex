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
  require Logger

  @type result :: %{
          final_text: String.t(),
          tools: list(map()),
          usage: map()
        }

  @spec run_turn(:openai | :anthropic | :gemini, String.t(), String.t(), [map()], keyword()) ::
          {:ok, result} | {:error, term()}
  def run_turn(_provider, _session_name, _model, _messages, _opts \\ [])

  def run_turn(:openai, session_name, model, messages, opts) when is_list(messages) do
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
        # No tool call: turn is complete
        {:ok, %{final_text: answer, tools: [], usage: usage || %{}}}
      else
        # Execute tools, accumulate complete follow-up history, and loop until no more calls
        followup_opts =
          [model: model, session_uuid: session_uuid] ++
            if adapter, do: [streaming_adapter: adapter], else: []

        # Initial follow-up items include: original user message(s), assistant text, calls + outputs
        history_items = build_function_call_outputs(calls, answer, messages)
        used_calls = calls
        last_answer = answer

        # bounded loop to avoid accidental infinite cycles
        max_iters = 5

        {final_answer, all_calls, final_usage} =
          Enum.reduce_while(
            1..max_iters,
            {last_answer, used_calls, usage, history_items},
            fn _iter, {prev_answer, acc_calls, _prev_usage, acc_items} ->
              case TheMaestro.Providers.OpenAI.Streaming.stream_tool_followup(
                     session_name,
                     acc_items,
                     followup_opts
                   ) do
                {:ok, stream_n} ->
                  {new_calls, new_answer, usage_n} = drain_stream(stream_n, :openai)
                  new_calls = dedup_calls_by_id(new_calls)

                  # If no additional calls, we are done
                  if new_calls == [] do
                    {:halt, {new_answer || prev_answer, acc_calls, usage_n || %{}}}
                  else
                    # Append only the new assistant message + new call/output items to history
                    new_items = build_function_call_outputs(new_calls, new_answer, [])
                    next_items = acc_items ++ new_items
                    next_calls = acc_calls ++ new_calls
                    {:cont, {new_answer, next_calls, usage_n || %{}, next_items}}
                  end

                {:error, reason} ->
                  Logger.error("OpenAI follow-up streaming error: #{inspect(reason)}")
                  {:halt, {prev_answer, acc_calls, %{}}}
              end
            end
          )

        {:ok, %{final_text: final_answer, tools: all_calls, usage: final_usage || %{}}}
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
        # Build Anthropic follow-up items using shared builder (full history + assistant text + tool_use + tool_result)
        base_cwd = resolve_workspace_root(:anthropic, session_name)

        {anth_msgs, _outputs} =
          TheMaestro.Followups.Anthropic.build(messages, calls, answer, base_cwd: base_cwd)

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

  defp resolve_workspace_root(provider, session_name) do
    # Prefer OAuth session, then API key. Fallback to File.cwd!/expanded.
    auth =
      TheMaestro.SavedAuthentication.get_by_provider_and_name(provider, :oauth, session_name) ||
        TheMaestro.SavedAuthentication.get_by_provider_and_name(provider, :api_key, session_name)

    case auth do
      %{id: auth_id} ->
        case TheMaestro.Conversations.latest_session_for_auth_id(auth_id) do
          nil ->
            File.cwd!() |> Path.expand()

          s ->
            wd = s.working_dir
            if is_binary(wd) and wd != "", do: Path.expand(wd), else: File.cwd!() |> Path.expand()
        end

      _ ->
        File.cwd!() |> Path.expand()
    end
  end

  @spec run_turn(:gemini, String.t(), String.t(), [map()], keyword()) ::
          {:ok, result} | {:error, term()}
  def run_turn(:gemini, session_name, model, messages, opts) when is_list(messages) do
    adapter = Keyword.get(opts, :streaming_adapter)

    stream_opts =
      [model: model] ++ if(adapter, do: [streaming_adapter: adapter], else: [])

    with {:ok, stream} <- Provider.stream_chat(:gemini, session_name, messages, stream_opts) do
      {calls, answer, usage} = drain_stream_generic(stream, :gemini)
      calls = dedup_calls_by_id(calls)

      if calls == [] do
        {:ok, %{final_text: answer, tools: [], usage: usage || %{}}}
      else
        # Execute tools and stream follow-ups until completion
        followup_contents = build_gemini_tool_followup(messages, calls, prior_answer_text: answer)

        case TheMaestro.Providers.Gemini.Streaming.stream_tool_followup(
               session_name,
               followup_contents,
               model: model
             ) do
          {:ok, stream2} ->
            {calls2, answer2, usage2} = drain_stream_generic(stream2, :gemini)

            # If the model issues additional function calls, loop once more.
            calls2 = dedup_calls_by_id(calls2)

            if calls2 == [] do
              {:ok, %{final_text: answer2, tools: calls, usage: usage2 || %{}}}
            else
              contents3 = build_gemini_tool_followup(messages, calls2, prior_answer_text: answer2)

              case TheMaestro.Providers.Gemini.Streaming.stream_tool_followup(
                     session_name,
                     contents3,
                     model: model
                   ) do
                {:ok, stream3} ->
                  {_calls3, answer3, usage3} = drain_stream_generic(stream3, :gemini)
                  {:ok, %{final_text: answer3, tools: calls ++ calls2, usage: usage3 || %{}}}

                {:error, reason} ->
                  {:error, reason}
              end
            end

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
  # extractors moved to TheMaestro.Followups.Anthropic and Tools.Runtime

  # ===== Gemini follow-up builder =====
  defp build_gemini_tool_followup(original_messages, calls, opts) do
    base_cwd = File.cwd!()
    prior_answer_text = Keyword.get(opts, :prior_answer_text, "")

    # Build tool responses by executing each call
    outputs =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        case exec_gemini_tool(name, args, base_cwd) do
          {:ok, response_map} -> {id, name, {:ok, response_map}}
          {:error, msg} -> {id, name, {:error, msg}}
        end
      end)

    # Build functionResponse parts preserving call ids and names
    fr_parts =
      Enum.map(outputs, fn {id, name, result} ->
        response =
          case result do
            {:ok, map} -> map
            {:error, msg} -> %{"error" => to_string(msg)}
          end

        %{"functionResponse" => %{"name" => name, "id" => id, "response" => response}}
      end)

    # Build assistant functionCall parts echoing the model's prior function calls
    fc_parts =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        decoded_args =
          case Jason.decode(args || "{}") do
            {:ok, m} when is_map(m) -> m
            _ -> %{}
          end

        %{"functionCall" => %{"name" => name, "id" => id, "args" => decoded_args}}
      end)

    # Use the last user message as continuity context
    last_user =
      original_messages
      |> Enum.reverse()
      |> Enum.find(fn m -> (Map.get(m, "role") || Map.get(m, :role)) == "user" end)

    user_text =
      case last_user do
        %{} = m -> Map.get(m, "content") || Map.get(m, :content) || ""
        _ -> ""
      end

    user_content =
      [%{"text" => to_string(user_text)}]
      |> Enum.reject(fn p -> (p["text"] || "") == "" end)

    tool_msg = %{"role" => "tool", "parts" => fr_parts}
    assistant_fc_msg = %{"role" => "assistant", "parts" => fc_parts}

    base =
      if user_content == [] do
        []
      else
        [%{"role" => "user", "parts" => user_content}]
      end

    # Include prior assistant text as regular assistant content part if present
    assistant_part =
      case String.trim(prior_answer_text || "") do
        "" -> []
        txt -> [%{"role" => "assistant", "parts" => [%{"text" => txt}]}]
      end

    base ++ assistant_part ++ [assistant_fc_msg, tool_msg]
  end

  defp exec_gemini_tool(name, args_json, base_cwd) do
    name = String.downcase(to_string(name || ""))

    case Jason.decode(args_json || "{}") do
      {:ok, args} -> do_exec_gemini_tool(name, args, base_cwd)
      _ -> {:error, "invalid tool arguments"}
    end
  end

  defp do_exec_gemini_tool("run_shell_command", args, base_cwd) do
    cmd = Map.get(args, "command") || Map.get(args, :command)
    dir = Map.get(args, "directory") || Map.get(args, :directory)

    if is_binary(cmd) and byte_size(String.trim(cmd)) > 0 do
      shell_args = %{"command" => ["bash", "-lc", cmd]}

      shell_args =
        if is_binary(dir) and dir != "", do: Map.put(shell_args, "workdir", dir), else: shell_args

      case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
        {:ok, payload_json} ->
          case Jason.decode(payload_json) do
            {:ok, map} -> {:ok, map}
            _ -> {:ok, %{"output" => payload_json}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "missing command"}
    end
  end

  defp do_exec_gemini_tool("list_directory", args, base_cwd) do
    path = Map.get(args, "path") || base_cwd
    path = Path.expand(path, base_cwd)
    # Execute in the target path as working directory to avoid shell quoting needs
    shell_args = %{"command" => ["bash", "-lc", "ls -la"], "workdir" => path}

    case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
      {:ok, payload_json} ->
        case Jason.decode(payload_json) do
          {:ok, map} -> {:ok, map}
          _ -> {:ok, %{"output" => payload_json}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_exec_gemini_tool(other, args, base_cwd) do
    # Accept our generic name too
    case other do
      "shell" ->
        do_exec_gemini_tool(
          "run_shell_command",
          Map.put(
            args,
            "command",
            Map.get(args, "command") || Enum.join(Map.get(args, "argv") || [], " ")
          ),
          base_cwd
        )

      _ ->
        {:error, "unsupported tool: #{other}"}
    end
  end
end

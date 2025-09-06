defmodule TheMaestroWeb.SessionChatLive do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Readability.PreferCaseTrivialWith
  # credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Provider
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session =
      Conversations.get_session!(id)
      |> TheMaestro.Repo.preload(agent: [:saved_authentication, :base_system_prompt, :persona])

    {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:session, session)
     |> assign(:message, "")
     |> assign(:messages, current_messages(session.id))
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_id, nil)
     |> assign(:stream_task, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:summary, compute_summary(current_messages(session.id)))
     |> assign(:editing_latest, false)
     |> assign(:latest_json, nil)}
  end

  @impl true
  def handle_event("change", %{"message" => msg}, socket) do
    {:noreply, assign(socket, :message, msg)}
  end

  @impl true
  def handle_event("send", _params, socket) do
    msg = String.trim(socket.assigns.message || "")

    if msg == "" do
      {:noreply, socket}
    else
      {:noreply, start_streaming_turn(socket, msg)}
    end
  end

  @impl true
  def handle_event("start_edit_latest", _params, socket) do
    case Conversations.latest_snapshot(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      entry ->
        {:noreply,
         socket
         |> assign(:editing_latest, true)
         |> assign(:latest_json, Jason.encode!(entry.combined_chat, pretty: true))}
    end
  end

  @impl true
  def handle_event("cancel_edit_latest", _params, socket) do
    {:noreply, assign(socket, editing_latest: false, latest_json: nil)}
  end

  @impl true
  def handle_event("save_edit_latest", %{"json" => json}, socket) do
    with {:ok, map} <-
           Jason.decode(json),
         latest when not is_nil(latest) <-
           Conversations.latest_snapshot(socket.assigns.session.id),
         {:ok, _} <-
           Conversations.update_chat_entry(latest, %{
             combined_chat: map,
             edit_version: latest.edit_version + 1
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Latest snapshot updated")
       |> assign(:editing_latest, false)
       |> assign(:latest_json, nil)
       |> assign(:history, Conversations.list_chat_entries(socket.assigns.session.id))}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{inspect(e)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not save latest snapshot")}
    end
  end

  # ===== Streaming turn handling =====
  defp start_streaming_turn(socket, user_text) do
    session = socket.assigns.session
    latest = Conversations.latest_snapshot(session.id)

    canonical = (latest && latest.combined_chat) || %{"messages" => []}

    updated =
      put_in(canonical, ["messages"], (canonical["messages"] || []) ++ [user_msg(user_text)])

    # Persist user snapshot turn
    {:ok, _} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "user",
        provider: nil,
        request_headers: %{},
        response_headers: %{},
        combined_chat: updated,
        edit_version: 0
      })

    # Optimistically update UI conversation
    ui_messages =
      (socket.assigns.messages || []) ++
        [%{"role" => "user", "content" => [%{"type" => "text", "text" => user_text}]}]

    # Determine provider/model
    provider =
      session.agent.saved_authentication.provider |> to_string() |> String.to_existing_atom()

    model = pick_model_for_session(session, provider)
    auth_type = session.agent.saved_authentication.auth_type
    auth_name = session.agent.saved_authentication.name
    {:ok, provider_msgs} = Translator.to_provider(updated, provider)

    # Cancel any prior stream
    if task = socket.assigns.stream_task do
      Process.exit(task, :kill)
    end

    stream_id = Ecto.UUID.generate()
    parent = self()

    t0 = System.monotonic_time(:millisecond)

    task =
      Task.start_link(fn ->
        case call_provider(
               provider,
               session.agent.saved_authentication.name,
               provider_msgs,
               model
             ) do
          {:ok, stream} ->
            for msg <-
                  TheMaestro.Streaming.parse_stream(stream, provider, log_unknown_events: true),
                do: send(parent, {:ai_stream, stream_id, msg})

            # Gemini streams do not emit an explicit :done message; signal completion.
            if provider == :gemini do
              send(parent, {:ai_stream, stream_id, %{type: :done}})
            end

          {:error, reason} ->
            send(parent, {:ai_stream, stream_id, %{type: :error, error: inspect(reason)}})
            send(parent, {:ai_stream, stream_id, %{type: :done}})
        end
      end)
      |> elem(1)

    socket
    |> assign(:message, "")
    |> assign(:messages, ui_messages)
    |> assign(:streaming?, true)
    |> assign(:partial_answer, "")
    |> assign(:stream_id, stream_id)
    |> assign(:stream_task, task)
    |> assign(:pending_canonical, updated)
    |> assign(:used_provider, provider)
    |> assign(:used_model, model)
    |> assign(:used_auth_type, auth_type)
    |> assign(:used_auth_name, auth_name)
    |> assign(:used_usage, nil)
    |> assign(:tool_calls, [])
    |> assign(:used_t0_ms, t0)
    |> assign(:event_buffer, [])
    |> assign(:retry_attempts, 0)
  end

  defp user_msg(text), do: %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}

  defp assistant_msg(text),
    do: %{"role" => "assistant", "content" => [%{"type" => "text", "text" => text}]}

  defp assistant_msg_with_meta(text, meta) when is_map(meta) do
    assistant_msg(text) |> Map.put("_meta", meta)
  end

  defp default_model_for_session(session, :openai) do
    case session.agent.saved_authentication.auth_type do
      :oauth -> "gpt-5"
      _ -> "gpt-4o"
    end
  end

  defp default_model_for_session(_session, :anthropic), do: "claude-3-5-sonnet"

  defp default_model_for_session(session, :gemini) do
    case session.agent.saved_authentication.auth_type do
      :oauth -> "gemini-2.5-pro"
      _ -> "gemini-1.5-pro-latest"
    end
  end

  defp default_model_for_session(_session, _), do: ""

  # Try to pick a valid model from the provider's list; fallback to defaults
  defp pick_model_for_session(session, provider) do
    chosen = session.agent.model_id

    if is_binary(chosen) and chosen != "" do
      chosen
    else
      choose_model_from_provider(session, provider)
    end
  end

  defp choose_model_from_provider(session, provider) do
    default = default_model_for_session(session, provider)
    session_name = session.agent.saved_authentication.name
    auth_type = session.agent.saved_authentication.auth_type

    case Provider.list_models(provider, auth_type, session_name) do
      {:ok, models} when is_list(models) and models != [] ->
        ids = Enum.map(models, & &1.id)
        if default in ids, do: default, else: hd(ids)

      _ ->
        default
    end
  end

  # Return {:ok, stream}
  defp call_provider(:openai, session_name, messages, model),
    do: OpenAI.Streaming.stream_chat(session_name, messages, model: model)

  defp call_provider(:gemini, session_name, messages, model),
    do: Gemini.Streaming.stream_chat(session_name, messages, model: model)

  defp call_provider(:anthropic, session_name, messages, model),
    do: Anthropic.Streaming.stream_chat(session_name, messages, model: model)

  require Logger

  @impl true
  # Show thinking indicator until first text arrives
  def handle_info(
        {:ai_stream, id, %{type: :content, metadata: %{thinking: true}}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "thinking", at: now_ms()})
     |> assign(thinking?: true)}
  end

  def handle_info(
        {:ai_stream, id, %{type: :content, content: chunk}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    current = socket.assigns.partial_answer || ""
    delta = dedup_delta(current, chunk)
    new_partial = current <> delta

    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "content", delta: delta, at: now_ms()})
     |> assign(partial_answer: new_partial, thinking?: false)}
  end

  # Capture function/tool calls as they arrive and accumulate them for UI/persistence
  def handle_info(
        {:ai_stream, id, %{type: :function_call, function_call: calls}},
        %{assigns: %{stream_id: id}} = socket
      )
      when is_list(calls) do
    new =
      Enum.map(calls, fn %{id: cid, function: %{name: name, arguments: args}} ->
        %{"id" => cid, "name" => name, "arguments" => args || ""}
      end)

    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "function_call", calls: new, at: now_ms()})
     |> assign(:tool_calls, (socket.assigns.tool_calls || []) ++ new)
     |> assign(:pending_tool_calls, (socket.assigns.pending_tool_calls || []) ++ new)}
  end

  def handle_info(
        {:ai_stream, id, %{type: :error, error: err}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    Logger.error("stream error: #{inspect(err)}")

    # Handle Anthropic overloads with bounded backoff retries
    attempts = socket.assigns[:retry_attempts] || 0

    if socket.assigns[:used_provider] == :anthropic and anth_overloaded?(err) and attempts < 2 do
      # Cancel current stream task if running
      if task = socket.assigns.stream_task do
        Process.exit(task, :kill)
      end

      next = attempts + 1
      delay_ms = next * 750
      Process.send_after(self(), {:retry_stream, next}, delay_ms)

      {:noreply,
       socket
       |> push_event(%{
         kind: "ai",
         type: "error",
         error: "Anthropic overloaded — retrying (attempt #{next}/2) in #{delay_ms}ms",
         at: now_ms()
       })
       |> put_flash(:info, "Anthropic overloaded — retrying (#{next}/2) in #{delay_ms}ms")
       |> assign(thinking?: false)
       |> assign(:retry_attempts, next)}
    else
      {:noreply,
       socket
       |> push_event(%{kind: "ai", type: "error", error: err, at: now_ms()})
       |> put_flash(:error, "Provider error: #{err}")
       |> assign(thinking?: false)}
    end
  end

  @impl true
  def handle_info(
        {:ai_stream, id, %{type: :usage, usage: usage}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    # Accumulate latest usage for this stream to attach on finalize
    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "usage", usage: usage, at: now_ms()})
     |> assign(:used_usage, usage)}
  end

  def handle_info({:ai_stream, id, %{type: :done}}, %{assigns: %{stream_id: id}} = socket) do
    socket = push_event(socket, %{kind: "ai", type: "done", at: now_ms()})

    case socket.assigns[:pending_tool_calls] do
      calls when is_list(calls) and calls != [] ->
        with {:ok, socket2} <- run_pending_tools_and_follow_up(socket, calls) do
          {:noreply, assign(socket2, :pending_tool_calls, [])}
        else
          _ -> {:noreply, finalize_no_tools(socket)}
        end

      _ ->
        {:noreply, finalize_no_tools(socket)}
    end
  end

  # Ignore stale stream messages
  def handle_info({:ai_stream, _other, _msg}, socket), do: {:noreply, socket}

  # Internal: retry the current provider call after a backoff
  def handle_info({:retry_stream, _attempt} = _msg, socket) do
    # Only retry if we still have a pending canonical and we are on a supported provider
    case socket.assigns do
      %{pending_canonical: canon, used_provider: provider}
      when is_map(canon) and not is_nil(provider) ->
        model =
          socket.assigns.used_model || default_model_for_session(socket.assigns.session, provider)

        {:ok, provider_msgs} = Translator.to_provider(canon, provider)

        # Start a fresh streaming task with a new stream id
        parent = self()
        stream_id = Ecto.UUID.generate()

        task =
          Task.start_link(fn ->
            case call_provider(provider, socket.assigns.used_auth_name, provider_msgs, model) do
              {:ok, stream} ->
                for msg <-
                      TheMaestro.Streaming.parse_stream(stream, provider,
                        log_unknown_events: true
                      ),
                    do: send(parent, {:ai_stream, stream_id, msg})

              {:error, reason} ->
                send(parent, {:ai_stream, stream_id, %{type: :error, error: inspect(reason)}})
                send(parent, {:ai_stream, stream_id, %{type: :done}})
            end
          end)
          |> elem(1)

        {:noreply,
         socket
         |> assign(:stream_id, stream_id)
         |> assign(:stream_task, task)
         |> assign(:used_provider, provider)
         |> assign(:used_model, model)
         |> assign(:used_usage, nil)
         |> assign(:thinking?, false)}

      _ ->
        {:noreply, socket}
    end
  end

  # Internal tool signals (defensive: accept with or without ref wrapper)
  def handle_info({:__shell_done__, {out, status}}, socket) do
    {:noreply,
     push_event(socket, %{
       kind: "internal",
       type: "shell_done",
       exit_code: status,
       out: out,
       at: now_ms()
     })}
  end

  def handle_info({ref, {:__shell_done__, {out, status}}}, socket) when is_reference(ref) do
    {:noreply,
     push_event(socket, %{
       kind: "internal",
       type: "shell_done",
       exit_code: status,
       out: out,
       at: now_ms()
     })}
  end

  # Catch-all to ignore unrelated messages (e.g., internal task signals)
  def handle_info(_other, socket), do: {:noreply, socket}

  # ===== Event logging helpers =====
  defp now_ms, do: System.system_time(:millisecond)

  defp push_event(%{assigns: assigns} = socket, ev) when is_map(ev) do
    buf = assigns[:event_buffer] || []
    assign(socket, :event_buffer, buf ++ [ev])
  end

  # Detect Anthropic overloaded errors from error strings
  defp anth_overloaded?(err) when is_binary(err) do
    down = String.downcase(err)

    cond do
      String.contains?(down, "overloaded_error") ->
        true

      String.contains?(down, "\"overloaded\"") ->
        true

      true ->
        case :binary.match(err, "{") do
          {idx, _} ->
            json = String.slice(err, idx..-1)

            case Jason.decode(json) do
              {:ok, %{"error" => %{"type" => t}}} when is_binary(t) ->
                String.contains?(String.downcase(t), "overloaded")

              {:ok, %{"type" => t}} when is_binary(t) ->
                String.contains?(String.downcase(t), "overloaded")

              _ ->
                false
            end

          :nomatch ->
            false
        end
    end
  end

  defp effective_provider(socket, session) do
    socket.assigns.used_provider ||
      session.agent.saved_authentication.provider |> to_string() |> String.to_existing_atom()
  end

  defp build_req_meta(socket, session, provider) do
    %{
      "provider" => Atom.to_string(provider),
      "model" => socket.assigns.used_model || default_model_for_session(session, provider),
      "auth_type" =>
        to_string(socket.assigns.used_auth_type || session.agent.saved_authentication.auth_type),
      "auth_name" => socket.assigns.used_auth_name || session.agent.saved_authentication.name,
      "usage" => socket.assigns.used_usage || %{}
    }
  end

  defp finalize_no_tools(socket) do
    session = socket.assigns.session
    final_text = socket.assigns.partial_answer || ""

    provider = effective_provider(socket, session)
    req_meta = build_req_meta(socket, session, provider)

    updated = socket.assigns.pending_canonical || %{"messages" => []}

    updated2 =
      put_in(
        updated,
        ["messages"],
        updated["messages"] ++ [assistant_msg_with_meta(final_text, req_meta)]
      )

    updated2 = Map.put(updated2, "events", socket.assigns.event_buffer || [])

    persist_assistant_turn(
      session,
      final_text,
      req_meta,
      updated2,
      socket.assigns.used_usage,
      socket.assigns.tool_calls
    )

    meta = %{
      "provider" => req_meta["provider"],
      "model" => req_meta["model"],
      "auth_type" => req_meta["auth_type"],
      "auth_name" => req_meta["auth_name"],
      "usage" => req_meta["usage"],
      "tools" => socket.assigns.tool_calls
    }

    messages = append_assistant_message(socket.assigns.messages || [], final_text, meta)

    socket
    |> assign(:streaming?, false)
    |> assign(:partial_answer, "")
    |> assign(:stream_task, nil)
    |> assign(:stream_id, nil)
    |> assign(:pending_canonical, nil)
    |> assign(:thinking?, false)
    |> assign(:used_usage, nil)
    |> assign(:tool_calls, [])
    |> assign(:summary, compute_summary(messages))
    |> assign(:messages, messages)
  end

  defp run_pending_tools_and_follow_up(socket, calls) do
    base_cwd =
      case socket.assigns.session.working_dir do
        wd when is_binary(wd) and wd != "" -> Path.expand(wd)
        _ -> File.cwd!() |> Path.expand()
      end

    outputs =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        case String.downcase(name || "") do
          "bash" ->
            with {:ok, json} <- Jason.decode(args),
                 cmd when is_binary(cmd) <- Map.get(json, "command") do
              timeout_ms =
                case Map.get(json, "timeout") do
                  t when is_integer(t) -> t
                  t when is_float(t) -> trunc(t)
                  _ -> nil
                end

              shell_args =
                %{"command" => ["bash", "-lc", cmd]}
                |> maybe_put_timeout(timeout_ms)

              case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid bash arguments"}}
            end

          "shell" ->
            with {:ok, json} <- Jason.decode(args) do
              case TheMaestro.Tools.Shell.run(json, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid shell arguments"}}
            end

          "run_shell_command" ->
            with {:ok, json} <- Jason.decode(args) do
              cmd = Map.get(json, "command")
              dir = Map.get(json, "directory")
              if is_binary(cmd) and byte_size(String.trim(cmd)) > 0 do
                shell_args = %{"command" => ["bash", "-lc", cmd]}
                shell_args = if is_binary(dir) and dir != "", do: Map.put(shell_args, "workdir", dir), else: shell_args
                case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
                  {:ok, payload} -> {id, {:ok, payload}}
                  {:error, reason} -> {id, {:error, to_string(reason)}}
                end
              else
                {id, {:error, "missing command"}}
              end
            else
              _ -> {id, {:error, "invalid run_shell_command arguments"}}
            end

          "list_directory" ->
            with {:ok, json} <- Jason.decode(args) do
              path = Map.get(json, "path") || base_cwd
              path = Path.expand(path, base_cwd)
              shell_args = %{"command" => ["bash", "-lc", "ls -la"], "workdir" => path}
              case TheMaestro.Tools.Shell.run(shell_args, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid list_directory arguments"}}
            end

          "apply_patch" ->
            with {:ok, json} <- Jason.decode(args),
                 input when is_binary(input) <- Map.get(json, "input") do
              case TheMaestro.Tools.ApplyPatch.run(input, base_cwd: base_cwd) do
                {:ok, payload} -> {id, {:ok, payload}}
                {:error, reason} -> {id, {:error, to_string(reason)}}
              end
            else
              _ -> {id, {:error, "invalid apply_patch arguments"}}
            end

          other ->
            {id, {:error, "unsupported tool: #{other}"}}
        end
      end)

    # Include both the function_call item (so ChatGPT can correlate by call_id)
    # and the function_call_output item with the executed tool result.
    fc_items =
      Enum.map(socket.assigns.pending_tool_calls || [], fn %{
                                                             "id" => id,
                                                             "name" => name,
                                                             "arguments" => args
                                                           } ->
        %{"type" => "function_call", "call_id" => id, "name" => name, "arguments" => args || ""}
      end)

    out_items =
      Enum.map(outputs, fn {id, result} ->
        output =
          case result do
            {:ok, payload} ->
              payload

            {:error, msg} ->
              Jason.encode!(%{
                "output" => msg,
                "metadata" => %{"exit_code" => 1, "duration_seconds" => 0.0}
              })
          end

        %{"type" => "function_call_output", "call_id" => id, "output" => output}
      end)

    # Include prior assistant message for context continuity
    # Include last user message for continuity (convert to input_text)
    last_user_text =
      (socket.assigns.messages || [])
      |> Enum.reverse()
      |> Enum.find_value(fn m ->
        if m["role"] == "user", do: m["content"] |> List.first() |> Map.get("text"), else: nil
      end)

    user_ctx_items =
      case last_user_text do
        nil ->
          []

        text ->
          [
            %{
              "type" => "message",
              "role" => "user",
              "content" => [%{"type" => "input_text", "text" => text}]
            }
          ]
      end

    prior_msg =
      case socket.assigns.partial_answer || "" do
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

    items = user_ctx_items ++ prior_msg ++ fc_items ++ out_items

    provider = effective_provider(socket, socket.assigns.session)
    model = socket.assigns.used_model
    session_name = socket.assigns.session.agent.saved_authentication.name

    parent = self()
    new_stream_id = Ecto.UUID.generate()

    task =
      Task.start_link(fn ->
        case provider do
          :openai ->
            case TheMaestro.Providers.OpenAI.Streaming.stream_tool_followup(session_name, items,
                   model: model
                 ) do
              {:ok, stream} ->
                for msg <-
                      TheMaestro.Streaming.parse_stream(stream, provider,
                        log_unknown_events: true
                      ),
                    do: send(parent, {:ai_stream, new_stream_id, msg})

              {:error, reason} ->
                send(parent, {:ai_stream, new_stream_id, %{type: :error, error: inspect(reason)}})
                send(parent, {:ai_stream, new_stream_id, %{type: :done}})
            end

          :anthropic ->
            # Build Anthropic follow-up messages with tool_use + tool_result blocks
            canon = socket.assigns.pending_canonical || %{"messages" => []}
            prev_msgs = canon["messages"] || []

            last_user =
              prev_msgs
              |> Enum.reverse()
              |> Enum.find(
                %{"role" => "user", "content" => [%{"type" => "text", "text" => ""}]},
                fn m ->
                  (m["role"] || "") == "user"
                end
              )

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

            # User tool_result content from executed outputs
            tool_results =
              Enum.map(outputs, fn {id, result} ->
                case result do
                  {:ok, payload} ->
                    %{"type" => "tool_result", "tool_use_id" => id, "content" => payload}

                  {:error, reason} ->
                    %{
                      "type" => "tool_result",
                      "tool_use_id" => id,
                      "content" => to_string(reason)
                    }
                end
              end)

            anth_messages =
              [
                # Prior user message for context
                %{
                  "role" => "user",
                  "content" => last_user["content"] || [%{"type" => "text", "text" => ""}]
                },
                # Assistant tool_use blocks we received
                %{"role" => "assistant", "content" => tool_uses},
                # Our tool results
                %{"role" => "user", "content" => tool_results}
              ]

            case TheMaestro.Providers.Anthropic.Streaming.stream_tool_followup(
                   session_name,
                   anth_messages,
                   model: model
                 ) do
              {:ok, stream} ->
                for msg <-
                      TheMaestro.Streaming.parse_stream(stream, provider,
                        log_unknown_events: true
                      ),
                    do: send(parent, {:ai_stream, new_stream_id, msg})

              {:error, reason} ->
                send(parent, {:ai_stream, new_stream_id, %{type: :error, error: inspect(reason)}})
                send(parent, {:ai_stream, new_stream_id, %{type: :done}})
            end

          :gemini ->
            # Build Gemini functionResponse-based follow-up
            last_user =
              (socket.assigns.messages || [])
              |> Enum.reverse()
              |> Enum.find(fn m -> (m["role"] || "") == "user" end) || %{}

            last_user_parts =
              case last_user do
                %{"content" => content} when is_list(content) ->
                  # Convert OpenAI style [{"type"=>"input_text","text"=>..}] or text parts to Gemini
                  text =
                    case content do
                      [%{"type" => "input_text", "text" => t} | _] -> t
                      [%{"type" => "text", "text" => t} | _] -> t
                      _ -> ""
                    end

                  if text == "", do: [], else: [%{"text" => text}]

                _ -> []
              end

            # Map outputs (id -> result) and attach names
            call_lookup = Map.new(socket.assigns.pending_tool_calls || [], &{&1["id"], &1})

            fr_parts =
              Enum.map(outputs, fn {id, result} ->
                name = (call_lookup[id] || %{})["name"] || "run_shell_command"
                response =
                  case result do
                    {:ok, payload} ->
                      case Jason.decode(payload) do
                        {:ok, map} -> map
                        _ -> %{"output" => payload}
                      end

                    {:error, reason} -> %{"error" => to_string(reason)}
                  end

                %{"functionResponse" => %{"name" => name, "id" => id, "response" => response}}
              end)

            # Echo assistant functionCall parts for each pending call
            fc_parts =
              Enum.map(socket.assigns.pending_tool_calls || [], fn call ->
                args =
                  case Jason.decode(call["arguments"] || "{}") do
                    {:ok, m} -> m
                    _ -> %{}
                  end

                %{"functionCall" => %{"name" => call["name"], "id" => call["id"], "args" => args}}
              end)

            contents =
              (if last_user_parts == [], do: [], else: [%{"role" => "user", "parts" => last_user_parts}]) ++
                [%{"role" => "assistant", "parts" => fc_parts}] ++
                [%{"role" => "tool", "parts" => fr_parts}]

            case TheMaestro.Providers.Gemini.Streaming.stream_tool_followup(
                   session_name,
                   contents,
                   model: model
                 ) do
              {:ok, stream} ->
                for msg <-
                      TheMaestro.Streaming.parse_stream(stream, provider,
                        log_unknown_events: true
                      ),
                    do: send(parent, {:ai_stream, new_stream_id, msg})

                # Signal completion for Gemini to trigger finalization
                send(parent, {:ai_stream, new_stream_id, %{type: :done}})

              {:error, reason} ->
                send(parent, {:ai_stream, new_stream_id, %{type: :error, error: inspect(reason)}})
                send(parent, {:ai_stream, new_stream_id, %{type: :done}})
            end

          _ ->
            send(
              parent,
              {:ai_stream, new_stream_id,
               %{type: :error, error: "follow-up only supported for :openai and :anthropic"}}
            )

            send(parent, {:ai_stream, new_stream_id, %{type: :done}})
        end
      end)
      |> elem(1)

    {:ok,
     socket
     |> assign(:partial_answer, "")
     |> assign(:stream_id, new_stream_id)
     |> assign(:stream_task, task)
     |> assign(:used_usage, nil)
     |> assign(:thinking?, false)}
  end

  defp maybe_put_timeout(map, nil), do: map
  defp maybe_put_timeout(map, t) when is_integer(t) and t > 0, do: Map.put(map, "timeout_ms", t)

  defp persist_assistant_turn(_session, final_text, _req_meta, _updated2, _used_usage, _tools)
       when final_text == "",
       do: :ok

  defp persist_assistant_turn(session, _final_text, req_meta, updated2, used_usage, tools) do
    req_hdrs = %{
      "provider" => req_meta["provider"],
      "model" => req_meta["model"],
      "auth_type" => req_meta["auth_type"],
      "auth_name" => req_meta["auth_name"]
    }

    resp_hdrs = %{"usage" => used_usage || %{}, "tools" => tools || []}

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "assistant",
        provider: req_meta["provider"],
        request_headers: req_hdrs,
        response_headers: resp_hdrs,
        combined_chat: updated2,
        edit_version: 0
      })

    {:ok, _} =
      Conversations.update_session(session, %{
        latest_chat_entry_id: entry.id,
        last_used_at: DateTime.utc_now()
      })

    :ok
  end

  defp append_assistant_message(messages, final_text, meta) do
    messages ++
      [
        %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => final_text}],
          "_meta" => meta
        }
      ]
  end

  defp dedup_delta(current, chunk) when is_binary(current) and is_binary(chunk) do
    cond do
      chunk == "" ->
        ""

      String.starts_with?(chunk, current) ->
        binary_part(chunk, byte_size(current), byte_size(chunk) - byte_size(current))

      # snapshot smaller than what we have
      String.starts_with?(current, chunk) ->
        ""

      true ->
        chunk
    end
  end

  defp current_messages(session_id) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-2 text-xs opacity-70">
        <%= if s = @summary do %>
          <span>last: {s.provider}, {s.model}, {s.auth_type}
            {if s.auth_name, do: "(" <> s.auth_name <> ")"}</span>
          <span class="ml-2">avg latency: {s.avg_latency_ms} ms</span>
        <% end %>
      </div>
      <.header>
        Chat: {@session.name || "Session"}
        <:actions>
          <.button navigate={~p"/dashboard"}>Back</.button>
        </:actions>
      </.header>

      <div class="space-y-2">
        <%= for msg <- @messages do %>
          <div class={"p-2 rounded " <> if msg["role"] == "user", do: "bg-base-200", else: "bg-base-100"}>
            <div class="text-xs opacity-70">
              {msg["role"]}
              <%= if m = msg["_meta"] do %>
                ( {m["provider"]}, {m["model"]}, {m["auth_type"]}
                <%= if u = m["usage"] do %>
                  , total {compact_int(token_total(u))}
                <% end %>
                <%= if m["latency_ms"] do %>
                  , {m["latency_ms"]}ms
                <% end %>
                )
              <% end %>
            </div>
            <div class="whitespace-pre-wrap text-sm">
              <.render_text chat={%{"messages" => [msg]}} />
            </div>
            <%= if m = msg["_meta"] do %>
              <details class="mt-1 opacity-70 text-xs">
                <summary>details</summary>
                <div>provider: {m["provider"]}</div>
                <div>model: {m["model"]}</div>
                <div>auth: {m["auth_type"]} ({m["auth_name"]})</div>
                <%= if u = m["usage"] do %>
                  <div>
                    tokens: prompt {compact_int(u["prompt_tokens"] || u[:prompt_tokens] || 0)}, completion {compact_int(
                      u["completion_tokens"] || u[:completion_tokens] || 0
                    )}, total {compact_int(token_total(u))}
                  </div>
                <% end %>
                <%= if is_list(m["tools"]) and m["tools"] != [] do %>
                  <div class="mt-1">tools:</div>
                  <ul class="list-disc ml-4">
                    <%= for t <- m["tools"] do %>
                      <li><code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 120)}</li>
                    <% end %>
                  </ul>
                <% end %>
                <%= if m["latency_ms"] do %>
                  <div>latency: {m["latency_ms"]} ms</div>
                <% end %>
              </details>
            <% end %>
          </div>
        <% end %>

        <%= if @streaming? and is_list(@tool_calls) and @tool_calls != [] do %>
          <div class="p-2 rounded bg-base-100">
            <div class="text-xs opacity-70">tool activity</div>
            <ul class="list-disc ml-4 text-sm">
              <%= for t <- @tool_calls do %>
                <li><code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 160)}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%= if @streaming? and @partial_answer == "" and @thinking? do %>
          <div class="p-2 rounded bg-base-100">
            <div class="text-xs opacity-70">assistant</div>
            <div class="opacity-70 italic text-sm">thinking…</div>
          </div>
        <% end %>

        <%= if @streaming? and @partial_answer != "" do %>
          <div class="p-2 rounded bg-base-100">
            <div class="text-xs opacity-70">
              assistant
              <%= if @used_provider do %>
                ( {Atom.to_string(@used_provider)}, {@used_model}, {to_string(@used_auth_type || "")}
                <%= if u = @used_usage do %>
                  , total {compact_int(token_total(u))}
                <% end %>
                )
              <% end %>
            </div>
            <div class="whitespace-pre-wrap text-sm">{@partial_answer}</div>
            <%= if u = @used_usage do %>
              <details class="mt-1 opacity-70 text-xs">
                <summary>details</summary>
                <div>provider: {Atom.to_string(@used_provider)}</div>
                <div>model: {@used_model}</div>
                <div>auth: {to_string(@used_auth_type || "")} ({@used_auth_name})</div>
                <div>
                  tokens: prompt {compact_int(u[:prompt_tokens] || u["prompt_tokens"] || 0)}, completion {compact_int(
                    u[:completion_tokens] || u["completion_tokens"] || 0
                  )}, total {compact_int(token_total(u))}
                </div>
              </details>
            <% end %>
          </div>
        <% end %>
      </div>

      <.form for={%{}} phx-submit="send" class="mt-4">
        <textarea
          name="message"
          class="textarea textarea-bordered w-full"
          rows="3"
          value={@message}
          phx-change="change"
        ></textarea>
        <div class="mt-2">
          <button type="submit" class="btn btn-primary">Send</button>
        </div>
      </.form>

      <div class="mt-6">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-md font-semibold">Latest Snapshot</h3>
          <%= if @editing_latest do %>
            <button class="btn btn-xs" phx-click="cancel_edit_latest">Cancel</button>
          <% else %>
            <button class="btn btn-xs" phx-click="start_edit_latest">Edit</button>
          <% end %>
        </div>
        <%= if @editing_latest do %>
          <.form for={%{}} phx-submit="save_edit_latest">
            <textarea
              name="json"
              class="textarea textarea-bordered w-full font-mono text-xs"
              rows="10"
            ><%= @latest_json %></textarea>
            <div class="mt-2">
              <button type="submit" class="btn btn-primary btn-sm">Save Snapshot</button>
            </div>
          </.form>
        <% else %>
          <div class="text-xs opacity-70">
            Editing allows trimming or correcting the current context (full copy). Changes bump edit_version.
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :chat, :map, required: true

  defp render_text(assigns) do
    messages = Map.get(assigns.chat, "messages", [])

    text =
      messages
      |> Enum.map(fn %{"role" => role, "content" => parts} ->
        role <>
          ": " <>
          (parts
           |> Enum.map(fn
             %{"type" => "text", "text" => t} -> t
             %{"text" => t} -> t
             t when is_binary(t) -> t
             _ -> ""
           end)
           |> Enum.join("\n"))
      end)
      |> Enum.join("\n\n")

    assigns = assign(assigns, :text, text)

    ~H"""
    {@text}
    """
  end

  # ===== Helpers for summary/formatting =====
  defp token_total(u) do
    u["total_tokens"] || u[:total_tokens] ||
      (u["prompt_tokens"] || u[:prompt_tokens] || 0) +
        (u["completion_tokens"] || u[:completion_tokens] || 0)
  end

  defp compact_int(n) when is_integer(n) and n >= 1000 do
    :erlang.float_to_binary(n / 1000, [:compact, {:decimals, 1}]) <> "k"
  end

  defp compact_int(n) when is_integer(n), do: Integer.to_string(n)
  defp compact_int(_), do: "0"

  defp compute_summary(messages) when is_list(messages) do
    assistants =
      messages
      |> Enum.filter(&(&1["role"] == "assistant"))

    last = assistants |> List.last()

    latencies =
      assistants
      |> Enum.map(fn m -> get_in(m, ["_meta", "latency_ms"]) end)
      |> Enum.filter(&is_integer/1)

    avg =
      case latencies do
        [] -> nil
        list -> div(Enum.sum(list), length(list))
      end

    if last && last["_meta"] do
      m = last["_meta"]

      %{
        provider: m["provider"],
        model: m["model"],
        auth_type: m["auth_type"],
        auth_name: m["auth_name"],
        avg_latency_ms: avg || 0
      }
    else
      nil
    end
  end

  defp compute_summary(_), do: nil
end

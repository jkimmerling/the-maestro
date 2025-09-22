defmodule TheMaestro.Sessions.Manager do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  @moduledoc "Session-scoped streaming manager."

  use GenServer
  require Logger

  alias Ecto.Adapters.SQL.Sandbox, as: RepoSandbox
  alias Phoenix.PubSub
  alias TheMaestro.{Auth, Conversations, Repo}
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Followups.Anthropic, as: AnthFollowups
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  alias TheMaestro.Streaming
  alias TheMaestro.Domain.{StreamEnvelope, StreamEvent}
  alias TheMaestro.Tools.Runtime, as: ToolsRuntime

  @dialyzer {:nowarn_function, finalize_and_persist: 3}

  @type session_entry :: %{
          task: pid() | nil,
          stream_id: String.t() | nil,
          acc: %{
            text: String.t(),
            tool_calls: list(),
            usage: map() | nil,
            events: list(),
            meta: map(),
            frames: list(),
            frame_idx: non_neg_integer()
          }
        }

  @type state :: %{optional(String.t()) => session_entry()}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  def subscribe(session_id) when is_binary(session_id) do
    PubSub.subscribe(TheMaestro.PubSub, topic(session_id))
  end

  def start_stream(session_id, provider, session_name, provider_messages, model, opts \\ [])
      when is_binary(session_id) and is_atom(provider) do
    GenServer.call(
      __MODULE__,
      {:start_stream, session_id, provider, session_name, provider_messages, model, opts},
      30_000
    )
  end

  def run_followup(session_id, provider, session_name, items, model, opts \\ [])
      when is_binary(session_id) and is_atom(provider) do
    GenServer.call(
      __MODULE__,
      {:run_followup, session_id, provider, session_name, items, model, opts},
      30_000
    )
  end

  def cancel(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:cancel, session_id})
  end

  # ---- Todo state (in-memory, session-scoped) ----
  def set_todos(session_id, todos) when is_binary(session_id) and is_list(todos) do
    GenServer.call(__MODULE__, {:set_todos, session_id, todos})
  end

  def get_todos(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_todos, session_id})
  end

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(
        {:start_stream, session_id, provider, session_name, provider_messages, model, opts},
        from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()
    t0_ms = Keyword.get(opts, :t0_ms, System.monotonic_time(:millisecond))
    owner_pid = Keyword.get(opts, :sandbox_owner) || sandbox_owner(from)

    meta = %{
      session_id: session_id,
      provider: provider,
      session_name: session_name,
      model: model,
      t0_ms: t0_ms,
      sandbox_owner: owner_pid
    }

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        maybe_allow_sandbox(owner_pid)

        result =
          do_call_provider(
            provider,
            session_name,
            provider_messages,
            model,
            Keyword.put_new(opts, :decl_session_id, session_id)
          )

        case result do
          {:ok, stream} ->
            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{
              type: :thinking,
              raw: %{thinking: true}
            })
            GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :thinking, nil})

            # Emit a user_text frame sourced from the last snapshot
            case Conversations.latest_snapshot(session_id) do
              %Conversations.ChatEntry{} = latest_entry ->
                if ut = last_user_text_from(latest_entry) do
                  if is_binary(ut) and ut != "" do
                    GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :user_text, ut})
                  end
                end

              _ -> :ok
            end

            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish_both(session_id, stream_id, msg)

              case msg do
                %TheMaestro.Domain.StreamEvent{type: :content, content: chunk, raw: raw} ->
                  reason? = is_map(raw) and ((raw[:thinking] || raw["thinking"]) || (raw[:reasoning] || raw["reasoning"]))
                  if reason? do
                    payload = if is_binary(chunk) and chunk != "", do: %{"content" => chunk}, else: nil
                    GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :thinking, payload})
                  else
                    if is_binary(chunk) do
                      GenServer.cast(__MODULE__, {:acc_content, session_id, stream_id, chunk})
                      GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :content, chunk})
                    end
                  end

                %TheMaestro.Domain.StreamEvent{type: :function_call, tool_calls: calls}
                when is_list(calls) ->
                  GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})
                  GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :function_call, calls})

                %TheMaestro.Domain.StreamEvent{type: :usage, usage: usage} ->
                  GenServer.cast(__MODULE__, {:acc_usage, session_id, stream_id, usage})
                  GenServer.cast(__MODULE__, {:frame_event, session_id, stream_id, :usage, usage})

                _ ->
                  :ok
              end
            end

            # Gemini may not emit :done
            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})
            GenServer.cast(__MODULE__, {:stream_done, session_id, stream_id})

          {:error, reason} ->
            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{
              type: :error,
              error: inspect(reason)
            })

            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})
        end
      end)

    entry = %{
      task: task,
      stream_id: stream_id,
      acc: %{text: "", tool_calls: [], usage: nil, events: [], meta: meta, frames: [], frame_idx: 0}
    }

    {:reply, {:ok, stream_id}, put_in(st, [session_id], entry)}
  end

  def handle_call(
        {:run_followup, session_id, provider, session_name, items, model, opts},
        from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()
    owner_pid = Keyword.get(opts, :sandbox_owner) || sandbox_owner(from)

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        maybe_allow_sandbox(owner_pid)

        result =
          case provider do
            :openai ->
              OpenAI.Streaming.stream_tool_followup(session_name, items,
                model: model,
                decl_session_id: session_id
              )

            :anthropic ->
              Anthropic.Streaming.stream_tool_followup(session_name, items,
                model: model,
                decl_session_id: session_id
              )

            :gemini ->
              Gemini.Streaming.stream_tool_followup(session_name, items,
                model: model,
                decl_session_id: session_id
              )
          end

        case result do
          {:ok, stream} ->
            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish_both(session_id, stream_id, msg)
            end

            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})

          {:error, reason} ->
            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{
              type: :error,
              error: inspect(reason)
            })

            publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})
        end
      end)

    {:reply, {:ok, stream_id}, put_in(st, [session_id], %{task: task, stream_id: stream_id})}
  end

  def handle_call({:cancel, session_id}, _from, st) do
    st = cancel_if_running(st, session_id)
    {:reply, :ok, st}
  end

  def handle_call({:set_todos, session_id, todos}, _from, st) do
    st =
      update_in(st, [session_id, :acc, :meta], fn meta ->
        meta = meta || %{}
        Map.put(meta, :todos, normalize_todos(todos))
      end)

    {:reply, :ok, st}
  end

  def handle_call({:get_todos, session_id}, _from, st) do
    todos = get_in(st, [session_id, :acc, :meta, :todos]) || []
    {:reply, todos, st}
  end

  @impl true
  def handle_cast({:acc_content, session_id, _stream_id, chunk}, st) do
    st =
      update_in(st, [session_id, :acc], fn acc ->
        if acc do
          meta = acc.meta || %{}
          last_chunk = meta[:last_content_chunk]
          # Guard against duplicated large chunks (e.g., after SSE retry)
          if duplicate_large_chunk?(acc.text, last_chunk, chunk) do
            acc
          else
            events = acc.events ++ [%{type: :content, at: now_ms(), size: byte_size(chunk)}]
            new_meta = Map.put(meta, :last_content_chunk, chunk)
            %{acc | text: acc.text <> chunk, events: events, meta: new_meta}
          end
        else
          acc
        end
      end)

    {:noreply, st}
  end

  def handle_cast({:acc_calls, session_id, _stream_id, calls}, st) do
    st =
      update_in(st, [session_id, :acc], fn acc ->
        if acc do
          new =
            Enum.map(calls, fn
              %{id: cid, function: %{name: name, arguments: args}} ->
                %{"id" => cid, "name" => name, "arguments" => args || ""}

              %TheMaestro.Domain.ToolCall{id: cid, name: name, arguments: args} ->
                %{"id" => cid, "name" => name, "arguments" => args || ""}

              %{id: cid, name: name, arguments: args} ->
                %{"id" => cid, "name" => name, "arguments" => args || ""}

              %{"id" => cid, "name" => name, "arguments" => args} ->
                %{"id" => cid, "name" => name, "arguments" => args || ""}
            end)

          %{
            acc
            | tool_calls: (acc.tool_calls || []) ++ new,
              events: acc.events ++ [%{type: :function_call, at: now_ms(), count: length(new)}]
          }
        else
          acc
        end
      end)

    {:noreply, st}
  end

  def handle_cast({:acc_usage, session_id, _stream_id, usage}, st) do
    st =
      update_in(st, [session_id, :acc], fn acc ->
        if acc,
          do: %{
            acc
            | usage: usage_to_map(usage),
              events: acc.events ++ [%{type: :usage, at: now_ms(), usage: usage_to_map(usage)}]
          },
          else: acc
      end)

    {:noreply, st}
  end

  def handle_cast({:frame_event, session_id, stream_id, type, payload}, st) do
    case Map.get(st, session_id) do
      %{stream_id: ^stream_id, acc: acc} ->
        {frame, acc2} = build_frame(acc, type, payload)
        publish_turn_frame(session_id, stream_id, frame)
        {:noreply, put_in(st, [session_id, :acc], acc2)}

      _ ->
        {:noreply, st}
    end
  end

  def handle_cast({:stream_done, session_id, stream_id}, st) do
    case Map.get(st, session_id) do
      %{stream_id: ^stream_id, acc: acc} ->
        new_state =
          case acc do
            %{tool_calls: calls} when is_list(calls) and calls != [] ->
              run_tools_and_followup(session_id, stream_id, st)

            _ ->
              finalize_and_persist(session_id, stream_id, st)
              st
          end

        {:noreply, new_state}

      _ ->
        {:noreply, st}
    end
  end

  def handle_cast({:stream_done_followup, session_id, stream_id}, st) do
    case Map.get(st, session_id) do
      %{stream_id: ^stream_id, acc: acc} ->
        calls = (acc && acc.tool_calls) || []
        rounds = (acc && acc.meta && acc.meta[:followup_rounds]) || 0

        new_state =
          if is_list(calls) and calls != [] and rounds < 3 do
            run_tools_and_followup(session_id, stream_id, st)
          else
            finalize_and_persist(session_id, stream_id, st)
            st
          end

        {:noreply, new_state}

      _ ->
        {:noreply, st}
    end
  end

  defp do_call_provider(:openai, session_name, messages, model, opts),
    do:
      OpenAI.Streaming.stream_chat(session_name, messages,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp do_call_provider(:gemini, session_name, messages, model, opts),
    do:
      Gemini.Streaming.stream_chat(session_name, messages,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp do_call_provider(:anthropic, session_name, messages, model, opts),
    do:
      Anthropic.Streaming.stream_chat(session_name, messages,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp do_call_provider(other, _s, _m, _model, _opts),
    do: {:error, {:unsupported_provider, other}}

  defp cancel_if_running(st, session_id) do
    case Map.get(st, session_id) do
      %{task: pid} when is_pid(pid) ->
        Process.exit(pid, :kill)
        Map.delete(st, session_id)

      _ ->
        st
    end
  end

  defp publish(session_id, message) do
    PubSub.broadcast(TheMaestro.PubSub, topic(session_id), message)
  end

  @spec publish_both(String.t(), String.t(), map() | TheMaestro.Domain.StreamEvent.t()) :: :ok
  defp publish_both(session_id, stream_id, msg) do
    ev = to_stream_event(msg)

    envelope = %StreamEnvelope{
      session_id: session_id,
      stream_id: stream_id,
      event: ev,
      at_ms: now_ms()
    }

    # Typed envelope (single, canonical shape)
    publish(session_id, {:session_stream, envelope})
    :ok
  end

  @spec to_stream_event(map() | StreamEvent.t()) :: StreamEvent.t()
  defp to_stream_event(%StreamEvent{} = ev), do: ev
  defp to_stream_event(%{} = m), do: StreamEvent.new!(m)

  defp topic(session_id), do: "session:" <> session_id
  defp turn_topic(session_id, stream_id), do: "turn:" <> session_id <> ":" <> stream_id

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp sandbox_owner({pid, _ref}) when is_pid(pid), do: pid
  defp sandbox_owner(_), do: nil

  defp maybe_allow_sandbox(owner_pid) when is_pid(owner_pid) do
    if Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox) do
      try do
        RepoSandbox.allow(Repo, owner_pid, self())
        :ok
      rescue
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp maybe_allow_sandbox(_), do: :ok

  # Consider chunks >= 200 bytes and skip if identical to the last chunk
  # or if the accumulated text already ends with the incoming chunk.
  defp duplicate_large_chunk?(acc_text, last_chunk, chunk) do
    cond do
      not is_binary(chunk) -> false
      byte_size(chunk) < 200 -> false
      is_binary(last_chunk) and last_chunk == chunk -> true
      is_binary(acc_text) and String.ends_with?(acc_text, chunk) -> true
      true -> false
    end
  end

  defp publish_turn_frame(session_id, stream_id, frame_map) when is_map(frame_map) do
    PubSub.broadcast(TheMaestro.PubSub, turn_topic(session_id, stream_id), {:turn_frame, frame_map})
    :ok
  end

  defp build_frame(%{frame_idx: idx, frames: frames} = acc, type, payload) do
    alias TheMaestro.Domain.TurnFrame

    base = %{
      id: Ecto.UUID.generate(),
      idx: idx,
      at_ms: now_ms(),
      role: "assistant",
      kind: kind_for(type),
      payload: payload_to_map(type, payload),
      thought?: type in [:thinking],
      collapsed?: type in [:thinking, :function_call]
    }

    frame = TurnFrame.new!(base) |> TurnFrame.to_map()
    acc2 = %{acc | frame_idx: idx + 1, frames: frames ++ [frame]}
    {frame, acc2}
  end

  defp kind_for(:thinking), do: "assistant_thinking"
  defp kind_for(:content), do: "assistant_text"
  defp kind_for(:user_text), do: "user_text"
  defp kind_for(:function_call), do: "function_call"
  defp kind_for(:usage), do: "usage"
  defp kind_for(:tool_result), do: "tool_result"
  defp kind_for(:finalized), do: "final"
  defp kind_for(_), do: "event"

  defp payload_to_map(:content, chunk) when is_binary(chunk), do: %{"delta" => chunk}
  defp payload_to_map(:function_call, calls) when is_list(calls),
    do: %{"calls" => Enum.map(calls, &map_call/1)}

  defp payload_to_map(:usage, %{} = usage), do: usage
  defp payload_to_map(:thinking, _), do: %{}
  defp payload_to_map(:user_text, text) when is_binary(text), do: %{"text" => text}
  defp payload_to_map(:finalized, %{} = m),
    do: %{"content" => Map.get(m, :content) || Map.get(m, "content"), "meta" => Map.get(m, :meta) || Map.get(m, "meta")}

  defp payload_to_map(_t, p) when is_map(p), do: p
  defp payload_to_map(_t, _), do: %{}

  defp map_call(%TheMaestro.Domain.ToolCall{id: id, name: name, arguments: args}),
    do: %{"id" => id, "name" => name, "arguments" => args}

  defp map_call(%{"id" => id, "name" => name, "arguments" => args}),
    do: %{"id" => id, "name" => name, "arguments" => to_string(args || "")}

  defp map_call(%{id: id, name: name, arguments: args}),
    do: %{"id" => id, "name" => name, "arguments" => to_string(args || "")}

  defp map_call(other), do: %{"repr" => inspect(other)}

  defp timeline_enabled? do
    Application.get_env(:the_maestro, :chat_full_timeline, false)
  end

  defp maybe_put_frames(canon, thread_id, turn_index, frames) do
    if timeline_enabled?() and is_binary(thread_id) and is_integer(turn_index) do
      alias TheMaestro.Domain.CombinedChat
      canon
      |> CombinedChat.from_map()
      |> CombinedChat.put_turn_frames(thread_id, turn_index, frames)
      |> CombinedChat.to_map()
    else
      canon
    end
  end

  defp finalize_and_persist(session_id, stream_id, st) do
    case Map.get(st, session_id) do
      %{acc: %{text: text, usage: usage, meta: meta, events: events}} ->
        maybe_allow_sandbox(meta[:sandbox_owner])
        case Conversations.latest_snapshot(session_id) do
          %Conversations.ChatEntry{} = latest ->
      session = Conversations.get_session_with_auth!(session_id)
      provider = meta.provider
      model = meta.model
      {auth_type, auth_name} = auth_meta_from_session(session)
      latency = max(now_ms() - (meta.t0_ms || now_ms()), 0)

      req_meta = %{
        "provider" => Atom.to_string(provider),
        "model" => model,
        "auth_type" => to_string(auth_type),
        "auth_name" => auth_name,
        "usage" => usage || %{},
        "latency_ms" => latency
      }

      # Extract complete tool call and response data from current session and history
      current_tool_calls = Map.get(st[session_id].acc, :tool_calls, [])
      tool_history = (meta && meta[:tool_history_acc]) || []

      # Convert tool history to call_id -> response mapping
      tool_responses =
        Enum.flat_map(tool_history, fn history_entry ->
          outputs = history_entry[:outputs] || history_entry["outputs"] || []

          # Create mapping from call_id to response
          Enum.map(outputs, fn output ->
            call_id = output[:id] || output["id"]
            response_data = output[:output] || output["output"]
            {call_id, response_data}
          end)
        end)
        |> Map.new()

      updated2 =
        case String.trim(to_string(text || "")) do
          "" ->
            # No assistant text to append; only update events timeline
            (latest.combined_chat || %{"messages" => []})
            |> Map.put("events", events || [])
            |> maybe_append_tool_history(meta)

          _ ->
            canon0 = latest.combined_chat || %{"messages" => []}

            canon1 =
              if assistant_needs_append?(canon0, text) do
                # Include complete tool data on the appended assistant message
                canon0
                |> append_assistant_with_tools(
                  text,
                  req_meta,
                  current_tool_calls,
                  Map.to_list(tool_responses)
                )
              else
                canon0
              end

            canon1
            |> Map.put("events", events || [])
            |> maybe_append_tool_history(meta)
        end

      turn_idx = Conversations.next_turn_index(session_id)

      {:ok, entry} =
        Conversations.create_chat_entry(%{
          session_id: session_id,
          turn_index: turn_idx,
          actor: "assistant",
          provider: Atom.to_string(provider),
          request_headers: %{
            "provider" => Atom.to_string(provider),
            "model" => model,
            "auth_type" => to_string(auth_type),
            "auth_name" => auth_name
          },
          response_headers: %{
            "usage" => usage || %{},
            "tools" => Map.get(st[session_id].acc, :tool_calls, []),
            "tool_history" => (meta && meta[:tool_history_acc]) || []
          },
          combined_chat:
            maybe_put_frames(updated2, latest.thread_id, turn_idx, Map.get(st[session_id].acc, :frames, [])),
          edit_version: 0,
          thread_id: latest.thread_id
        })

      _ =
        Conversations.update_session(session, %{
          latest_chat_entry_id: entry.id,
          last_used_at: DateTime.utc_now()
        })

      _ =
        case Map.get(st[session_id].acc.meta, :t0_ms) do
          ms when is_integer(ms) ->
            Conversations.link_logs_to_chat_entry!(session_id, ms, entry.id)

          _ ->
            :ok
        end

          alias TheMaestro.Domain.{StreamEvent, Usage}
          usage_struct = if usage, do: Usage.new!(usage), else: nil

          publish_both(session_id, stream_id, %StreamEvent{
            type: :finalized,
            content: text,
            usage: usage_struct,
            raw: %{meta: req_meta}
          })

          {final_frame, _} =
            build_frame(Map.get(st[session_id], :acc), :finalized, %{content: text, meta: req_meta})

          publish_turn_frame(session_id, stream_id, final_frame)

        _ ->
          :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_append_tool_history(canon, meta) do
    hist = (meta && meta[:tool_history_acc]) || []

    if hist == [] do
      canon
    else
      existing = Map.get(canon, "tool_history", [])
      Map.put(canon, "tool_history", existing ++ hist)
    end
  end

  # New function to append assistant message with complete tool calls and responses
  defp append_assistant_with_tools(
         %{"messages" => msgs} = canon,
         text,
         req_meta,
         tool_calls,
         tool_responses
       ) do
    assistant_msg = %{
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => text}],
      "_meta" => req_meta
    }

    # Add tool_calls if they exist
    assistant_msg =
      if tool_calls != nil and tool_calls != [] do
        Map.put(assistant_msg, "tool_calls", tool_calls)
      else
        assistant_msg
      end

    # Add tool responses as separate messages for each response
    tool_response_msgs =
      Enum.map(tool_responses, fn {call_id, response} ->
        # Find the function name for this call_id from tool_calls
        function_name =
          Enum.find_value(tool_calls || [], fn call ->
            if call["id"] == call_id, do: call["name"]
          end) || "unknown_function"

        %{
          "role" => "tool",
          "tool_call_id" => call_id,
          "content" => [%{"type" => "text", "text" => Jason.encode!(response)}],
          "_meta" => %{"response_type" => "tool_result", "function_name" => function_name}
        }
      end)

    Map.put(
      canon,
      "messages",
      msgs ++ [assistant_msg] ++ tool_response_msgs
    )
  end

  defp run_tools_and_followup(session_id, stream_id, st) do
    entry = Map.get(st, session_id)
    acc = entry.acc
    provider = acc.meta.provider
    model = acc.meta.model
    session = Conversations.get_session_with_auth!(session_id)
    {_, session_name} = auth_meta_from_session(session)
    base_cwd = resolve_base_cwd(session)
    latest = Conversations.latest_snapshot(session_id)
    last_user_text = last_user_text_from(latest)

    # Deduplicate by (name,args) across rounds to avoid re-running identical calls
    executed = (acc.meta && acc.meta[:executed_calls]) || MapSet.new()

    calls_all = acc.tool_calls || []

    calls_to_run =
      Enum.reject(calls_all, fn %{"name" => name, "arguments" => args} ->
        sig = make_call_sig(name, args)
        MapSet.member?(executed, sig)
      end)
      |> maybe_guard_resolve_once()

    # If nothing new to execute, finalize instead of looping
    if calls_to_run == [] do
      finalize_and_persist(session_id, stream_id, st)
      st
    else
      owner_pid = acc.meta && acc.meta[:sandbox_owner]

      outputs = exec_tools(session_id, calls_to_run, base_cwd)

      if timeline_enabled?() do
        Enum.each(outputs, fn {id, result} ->
          preview =
            case result do
              {:ok, payload} when is_binary(payload) -> String.slice(payload, 0, 200)
              {:ok, payload} -> to_string(payload) |> String.slice(0, 200)
              {:error, reason} -> to_string(reason)
            end

          GenServer.cast(__MODULE__, {
            :frame_event,
            session_id,
            stream_id,
            :tool_result,
            %{"tool_call_id" => id, "preview" => preview}
          })
        end)
      end

      items =
        case provider do
          :openai -> build_openai_items(last_user_text, acc.text, acc.tool_calls || [], outputs)
          :anthropic -> build_anthropic_items(latest, acc.text, acc.tool_calls || [], outputs)
          :gemini -> build_gemini_items(last_user_text, acc.text, acc.tool_calls || [], outputs)
        end

      # Follow-up stream publishes under the SAME stream_id for UI continuity
      # bump follow-up round counter to prevent infinite loops
      history_entry = %{
        provider: provider,
        at: now_ms(),
        calls:
          Enum.map(calls_to_run, fn %{"id" => id, "name" => name, "arguments" => args} ->
            %{"id" => id, "name" => name, "arguments" => args}
          end),
        outputs:
          Enum.map(outputs, fn {id, result} ->
            %{"id" => id, "output" => tool_output_payload(result)}
          end)
      }

      st =
        update_in(st, [session_id, :acc, :meta], fn meta ->
          meta = meta || %{}

          executed2 =
            Enum.reduce(calls_to_run, executed, fn %{"name" => n, "arguments" => a}, accset ->
              MapSet.put(accset, make_call_sig(n, a))
            end)

          meta
          |> Map.update(:followup_rounds, 1, &(&1 + 1))
          |> Map.put(:executed_calls, executed2)
          |> Map.update(:tool_history_acc, [history_entry], fn l -> l ++ [history_entry] end)
        end)

      {:ok, _task} =
        Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
          maybe_allow_sandbox(owner_pid)

          result =
            do_followup_provider(provider, session_name, items, model,
              decl_session_id: session_id
            )

          case result do
            {:ok, stream} ->
              for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
                publish_both(session_id, stream_id, msg)

                case msg do
                  %TheMaestro.Domain.StreamEvent{type: :content, content: chunk}
                  when is_binary(chunk) ->
                    GenServer.cast(__MODULE__, {:acc_content, session_id, stream_id, chunk})

                  %TheMaestro.Domain.StreamEvent{type: :function_call, tool_calls: calls}
                  when is_list(calls) ->
                    GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})

                  %TheMaestro.Domain.StreamEvent{type: :usage, usage: usage} ->
                    GenServer.cast(__MODULE__, {:acc_usage, session_id, stream_id, usage})

                  _ ->
                    :ok
                end
              end

              publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})
              GenServer.cast(__MODULE__, {:stream_done_followup, session_id, stream_id})

            {:error, reason} ->
              publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{
                type: :error,
                error: inspect(reason)
              })

              publish_both(session_id, stream_id, %TheMaestro.Domain.StreamEvent{type: :done})
              GenServer.cast(__MODULE__, {:stream_done_followup, session_id, stream_id})
          end
        end)

      # reset accumulators for follow-up turn (keep meta and t0)
      st =
        put_in(st, [session_id, :acc], %{
          text: "",
          tool_calls: [],
          usage: nil,
          events: acc.events,
          meta: acc.meta
        })

      st
    end
  end

  defp do_followup_provider(:openai, session_name, items, model, opts),
    do:
      OpenAI.Streaming.stream_tool_followup(session_name, items,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp do_followup_provider(:anthropic, session_name, items, model, opts),
    do:
      Anthropic.Streaming.stream_tool_followup(session_name, items,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp do_followup_provider(:gemini, session_name, items, model, opts),
    do:
      Gemini.Streaming.stream_tool_followup(session_name, items,
        model: model,
        decl_session_id: Keyword.get(opts, :decl_session_id)
      )

  defp resolve_base_cwd(session) do
    case session.working_dir do
      wd when is_binary(wd) and wd != "" -> Path.expand(wd)
      _ -> File.cwd!() |> Path.expand()
    end
  end

  defp exec_tools(session_id, calls, base_cwd) do
    Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
      case ToolsRuntime.exec(session_id, name, args, base_cwd) do
        {:ok, payload} -> {id, {:ok, payload}}
        {:error, reason} -> {id, {:error, to_string(reason)}}
      end
    end)
  end

  defp usage_to_map(%TheMaestro.Domain.Usage{} = u), do: Map.from_struct(u)
  defp usage_to_map(%{} = m), do: m
  defp usage_to_map(nil), do: nil

  defp build_openai_items(last_user_text, _partial_answer, calls, outputs) do
    # Mimic Codex: include the last user message to keep the model on task,
    # then echo function_call(s) and provide function_call_output(s).

    user_items =
      case last_user_text && String.trim(to_string(last_user_text)) do
        text when is_binary(text) and text != "" ->
          [
            %{
              "type" => "message",
              "role" => "user",
              "content" => [%{"type" => "input_text", "text" => text}]
            }
          ]

        _ ->
          []
      end

    fc_items =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        %{"type" => "function_call", "call_id" => id, "name" => name, "arguments" => args || ""}
      end)

    out_items =
      Enum.map(outputs, fn {id, result} ->
        %{
          "type" => "function_call_output",
          "call_id" => id,
          "output" => tool_output_payload(result)
        }
      end)

    user_items ++ fc_items ++ out_items
  end

  defp assistant_needs_append?(%{"messages" => msgs}, text) when is_list(msgs) do
    case List.last(msgs) do
      %{"role" => "assistant", "content" => [%{"type" => "text", "text" => t} | _]} ->
        String.trim(to_string(t)) != String.trim(to_string(text))

      _ ->
        true
    end
  end

  defp assistant_needs_append?(_, _), do: true

  defp build_anthropic_items(latest_entry, partial_answer, calls, outputs) do
    canon = (latest_entry && latest_entry.combined_chat) || %{"messages" => []}
    {:ok, prev_msgs} = Translator.to_provider(canon, :anthropic)

    {anth_messages, _} =
      AnthFollowups.build(prev_msgs, calls, partial_answer,
        base_cwd: resolve_base_cwd(Conversations.get_session!(latest_entry.session_id)),
        outputs: outputs
      )

    anth_messages
  end

  defp build_gemini_items(last_user_text, _partial_answer, calls, outputs) do
    # Cloud Code expects conversation continuity. Send:
    # 1) the last user message (text only),
    # 2) the model functionCall echo(s),
    # 3) the tool functionResponse(s).

    fc_parts =
      Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
        decoded_args =
          case Jason.decode(args || "{}") do
            {:ok, %{} = m} -> m
            _ -> %{}
          end

        %{"functionCall" => %{"name" => name, "args" => decoded_args, "id" => id}}
      end)

    fr_parts =
      Enum.map(outputs, fn {id, result} ->
        payload = tool_output_payload(result)
        response = maybe_decode_json(payload)

        %{
          "functionResponse" => %{
            "name" => find_name_for_call(id, calls),
            "response" => response,
            "id" => id
          }
        }
      end)

    user_parts =
      if is_binary(last_user_text) and String.trim(last_user_text) != "",
        do: [%{"text" => last_user_text}],
        else: []

    msgs = []

    msgs =
      if user_parts == [], do: msgs, else: msgs ++ [%{"role" => "user", "parts" => user_parts}]

    msgs = if fc_parts == [], do: msgs, else: msgs ++ [%{"role" => "model", "parts" => fc_parts}]
    msgs = if fr_parts == [], do: msgs, else: msgs ++ [%{"role" => "tool", "parts" => fr_parts}]
    msgs
  end

  defp tool_output_payload({:ok, payload}), do: payload

  defp tool_output_payload({:error, msg}),
    do:
      Jason.encode!(%{
        "output" => msg,
        "metadata" => %{"exit_code" => 1, "duration_seconds" => 0.0}
      })

  defp find_name_for_call(id, calls) do
    case Enum.find(calls, fn c -> c["id"] == id end) do
      %{"name" => name} -> name
      _ -> "tool"
    end
  end

  defp maybe_decode_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = map} -> map
      {:ok, list} when is_list(list) -> list
      _ -> payload
    end
  end

  defp maybe_decode_json(other), do: other

  defp make_call_sig(name, args_json) do
    n = to_string(name || "")

    case {n, Jason.decode(args_json || "{}")} do
      {"resolve-library-id", {:ok, %{"libraryName" => lib}}} ->
        canon =
          lib
          |> to_string()
          |> String.trim()
          |> String.downcase()
          |> String.replace(~r/\s+/u, " ")

        n <> "|" <> Jason.encode!(%{"libraryName" => canon})

      {"get-library-docs", {:ok, %{} = m}} ->
        lib_id = to_string(Map.get(m, "context7CompatibleLibraryID", ""))

        topic =
          m
          |> Map.get("topic", "")
          |> to_string()
          |> String.downcase()
          |> String.trim()
          |> String.replace(~r/\s+/u, " ")

        n <> "|" <> Jason.encode!(%{"context7CompatibleLibraryID" => lib_id, "topic" => topic})

      {_other, {:ok, %{} = m}} ->
        n <> "|" <> Jason.encode!(m)

      {_other, _} ->
        n <> "|{}"
    end
  end

  # Allow at most one resolve-library-id execution per follow-up turn
  defp maybe_guard_resolve_once(calls) when is_list(calls) do
    {kept, _seen} =
      Enum.reduce(calls, {[], false}, fn %{"name" => name} = c, {acc, seen?} ->
        if name == "resolve-library-id" do
          if seen?, do: {acc, true}, else: {[c | acc], true}
        else
          {[c | acc], seen?}
        end
      end)

    Enum.reverse(kept)
  end

  defp last_user_text_from(%Conversations.ChatEntry{} = latest) do
    (latest.combined_chat["messages"] || [])
    |> Enum.reverse()
    |> Enum.find_value(fn m ->
      if m["role"] == "user",
        do: (m["content"] || []) |> List.first() |> Map.get("text"),
        else: nil
    end)
  end

  defp last_user_text_from(_), do: nil

  defp auth_meta_from_session(session) do
    saved = session.saved_authentication

    cond do
      match?(%Ecto.Association.NotLoaded{}, saved) and session.auth_id ->
        sa = Auth.get_saved_authentication!(session.auth_id)
        {sa.auth_type, sa.name}

      is_map(saved) ->
        {saved.auth_type, saved.name}

      true ->
        {:oauth, "default"}
    end
  end

  defp normalize_todos(list) when is_list(list) do
    Enum.map(list, fn item ->
      %{
        content: to_string(item[:content] || item["content"] || ""),
        activeForm: to_string(item[:activeForm] || item["activeForm"] || ""),
        status: normalize_status(item[:status] || item["status"])
      }
    end)
  end

  defp normalize_todos(_), do: []

  defp normalize_status(s) when s in ["pending", :pending], do: "pending"
  defp normalize_status(s) when s in ["in_progress", :in_progress], do: "in_progress"
  defp normalize_status(s) when s in ["completed", :completed], do: "completed"
  defp normalize_status(_), do: "pending"
end

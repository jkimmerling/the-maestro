defmodule TheMaestro.Sessions.Manager do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  @moduledoc """
  Session-scoped streaming manager.

  - Supervises provider streaming tasks under `TheMaestro.Sessions.TaskSup`
  - Publishes streaming events on `"session:" <> session_id` via `TheMaestro.PubSub`
  - Provides APIs to start/cancel streams and run tool follow-ups
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias TheMaestro.{Auth, Conversations}
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Followups.Anthropic, as: AnthFollowups
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  alias TheMaestro.Streaming
  alias TheMaestro.Tools.Runtime, as: ToolsRuntime

  @type session_entry :: %{
          task: pid() | nil,
          stream_id: String.t() | nil,
          acc: %{
            text: String.t(),
            tool_calls: list(),
            usage: map() | nil,
            events: list(),
            meta: map()
          }
        }

  @type state :: %{optional(String.t()) => session_entry()}

  # Public API

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

  # GenServer
  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(
        {:start_stream, session_id, provider, session_name, provider_messages, model, opts},
        _from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()
    t0_ms = Keyword.get(opts, :t0_ms, System.monotonic_time(:millisecond))

    meta = %{
      session_id: session_id,
      provider: provider,
      session_name: session_name,
      model: model,
      t0_ms: t0_ms
    }

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        result = do_call_provider(provider, session_name, provider_messages, model)

        case result do
          {:ok, stream} ->
            publish_both(session_id, stream_id, %{type: :thinking, metadata: %{thinking: true}})

            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish_both(session_id, stream_id, msg)

              case msg do
                %{type: :content, content: chunk} when is_binary(chunk) ->
                  GenServer.cast(__MODULE__, {:acc_content, session_id, stream_id, chunk})

                %{type: :function_call, tool_calls: calls} when is_list(calls) ->
                  GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})

                %{type: :function_call, function_call: calls} when is_list(calls) ->
                  GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})

                %{type: :usage, usage: usage} when is_map(usage) ->
                  GenServer.cast(__MODULE__, {:acc_usage, session_id, stream_id, usage})

                _ ->
                  :ok
              end
            end

            # Gemini may not emit :done
            publish_both(session_id, stream_id, %{type: :done})
            GenServer.cast(__MODULE__, {:stream_done, session_id, stream_id})

          {:error, reason} ->
            publish_both(session_id, stream_id, %{type: :error, error: inspect(reason)})
            publish_both(session_id, stream_id, %{type: :done})
        end
      end)

    entry = %{
      task: task,
      stream_id: stream_id,
      acc: %{text: "", tool_calls: [], usage: nil, events: [], meta: meta}
    }

    {:reply, {:ok, stream_id}, put_in(st, [session_id], entry)}
  end

  def handle_call(
        {:run_followup, session_id, provider, session_name, items, model, _opts},
        _from,
        st
      ) do
    st = cancel_if_running(st, session_id)
    stream_id = Ecto.UUID.generate()

    {:ok, task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        result =
          case provider do
            :openai ->
              OpenAI.Streaming.stream_tool_followup(session_name, items, model: model)

            :anthropic ->
              Anthropic.Streaming.stream_tool_followup(session_name, items, model: model)

            :gemini ->
              Gemini.Streaming.stream_tool_followup(session_name, items, model: model)
          end

        case result do
          {:ok, stream} ->
            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish_both(session_id, stream_id, msg)
            end

            publish_both(session_id, stream_id, %{type: :done})

          {:error, reason} ->
            publish_both(session_id, stream_id, %{type: :error, error: inspect(reason)})
            publish_both(session_id, stream_id, %{type: :done})
        end
      end)

    {:reply, {:ok, stream_id}, put_in(st, [session_id], %{task: task, stream_id: stream_id})}
  end

  def handle_call({:cancel, session_id}, _from, st) do
    st = cancel_if_running(st, session_id)
    {:reply, :ok, st}
  end

  # Accumulation
  @impl true
  def handle_cast({:acc_content, session_id, _stream_id, chunk}, st) do
    st =
      update_in(st, [session_id, :acc], fn acc ->
        if acc do
          events = acc.events ++ [%{type: :content, at: now_ms(), size: byte_size(chunk)}]
          %{acc | text: acc.text <> chunk, events: events}
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
            | usage: usage,
              events: acc.events ++ [%{type: :usage, at: now_ms(), usage: usage}]
          },
          else: acc
      end)

    {:noreply, st}
  end

  def handle_cast({:stream_done, session_id, stream_id}, st) do
    case Map.get(st, session_id) do
      %{stream_id: ^stream_id, acc: acc} ->
        case acc do
          %{tool_calls: calls} when is_list(calls) and calls != [] ->
            run_tools_and_followup(session_id, stream_id, st)

          _ ->
            finalize_and_persist(session_id, stream_id, st)
        end

        {:noreply, st}

      _ ->
        {:noreply, st}
    end
  end

  defp do_call_provider(:openai, session_name, messages, model),
    do: OpenAI.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(:gemini, session_name, messages, model),
    do: Gemini.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(:anthropic, session_name, messages, model),
    do: Anthropic.Streaming.stream_chat(session_name, messages, model: model)

  defp do_call_provider(other, _s, _m, _model), do: {:error, {:unsupported_provider, other}}

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

  defp publish_both(session_id, stream_id, msg_map) do
    compat = compat_msg_map(msg_map)
    publish(session_id, {:ai_stream, stream_id, compat})
    publish(session_id, {:ai_stream2, session_id, stream_id, compat})
  end

  defp topic(session_id), do: "session:" <> session_id

  defp now_ms, do: System.monotonic_time(:millisecond)

  # ----- Finalization & follow-ups -----

  defp finalize_and_persist(session_id, stream_id, st) do
    with %{acc: %{text: text, usage: usage, meta: meta, events: events}} <-
           Map.get(st, session_id),
         %Conversations.ChatEntry{} = latest <- Conversations.latest_snapshot(session_id) do
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

      updated2 =
        (latest.combined_chat || %{"messages" => []})
        |> append_assistant(text, req_meta)
        |> Map.put("events", events || [])

      {:ok, entry} =
        Conversations.create_chat_entry(%{
          session_id: session_id,
          turn_index: Conversations.next_turn_index(session_id),
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
            "tools" => Map.get(st[session_id].acc, :tool_calls, [])
          },
          combined_chat: updated2,
          edit_version: 0,
          thread_id: latest.thread_id
        })

      _ =
        Conversations.update_session(session, %{
          latest_chat_entry_id: entry.id,
          last_used_at: DateTime.utc_now()
        })

      publish_both(session_id, stream_id, %{
        type: :finalized,
        content: text,
        usage: usage || %{},
        meta: req_meta
      })
    else
      _ -> :ok
    end
  end

  defp append_assistant(%{"messages" => msgs} = canon, text, req_meta) do
    Map.put(
      canon,
      "messages",
      msgs ++
        [
          %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => text}],
            "_meta" => req_meta
          }
        ]
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

    outputs = exec_tools(acc.tool_calls || [], base_cwd)

    items =
      case provider do
        :openai -> build_openai_items(last_user_text, acc.text, acc.tool_calls || [], outputs)
        :anthropic -> build_anthropic_items(latest, acc.text, acc.tool_calls || [], outputs)
        :gemini -> build_gemini_items(last_user_text, acc.text, acc.tool_calls || [], outputs)
      end

    # Follow-up stream publishes under the SAME stream_id for UI continuity
    {:ok, _task} =
      Task.Supervisor.start_child(TheMaestro.Sessions.TaskSup, fn ->
        result = do_followup_provider(provider, session_name, items, model)

        case result do
          {:ok, stream} ->
            for msg <- Streaming.parse_stream(stream, provider, log_unknown_events: true) do
              publish_both(session_id, stream_id, msg)

              case msg do
                %{type: :content, content: chunk} when is_binary(chunk) ->
                  GenServer.cast(__MODULE__, {:acc_content, session_id, stream_id, chunk})

                %{type: :function_call, tool_calls: calls} when is_list(calls) ->
                  GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})

                %{type: :function_call, function_call: calls} when is_list(calls) ->
                  GenServer.cast(__MODULE__, {:acc_calls, session_id, stream_id, calls})

                %{type: :usage, usage: usage} when is_map(usage) ->
                  GenServer.cast(__MODULE__, {:acc_usage, session_id, stream_id, usage})

                _ ->
                  :ok
              end
            end

            publish_both(session_id, stream_id, %{type: :done})
            GenServer.cast(__MODULE__, {:stream_done_followup, session_id, stream_id})

          {:error, reason} ->
            publish_both(session_id, stream_id, %{type: :error, error: inspect(reason)})
            publish_both(session_id, stream_id, %{type: :done})
            GenServer.cast(__MODULE__, {:stream_done_followup, session_id, stream_id})
        end
      end)

    # reset accumulators for follow-up turn (keep meta and t0)
    _st =
      put_in(st, [session_id, :acc], %{
        text: "",
        tool_calls: [],
        usage: nil,
        events: acc.events,
        meta: acc.meta
      })
  end

  # Compatibility: ensure published event includes legacy keys for downstream consumers
  defp compat_msg_map(%{type: :function_call, tool_calls: calls} = m) when is_list(calls) do
    legacy =
      Enum.map(calls, fn
        %TheMaestro.Domain.ToolCall{id: id, name: name, arguments: args} ->
          %{id: id, function: %{name: name, arguments: args || ""}}

        %{"id" => id, "name" => name, "arguments" => args} ->
          %{id: id, function: %{name: name, arguments: args || ""}}

        %{id: id, name: name, arguments: args} ->
          %{id: id, function: %{name: name, arguments: args || ""}}

        other ->
          other
      end)

    m
    |> Map.put(:function_call, legacy)
  end

  defp compat_msg_map(m), do: m

  defp do_followup_provider(:openai, session_name, items, model),
    do: OpenAI.Streaming.stream_tool_followup(session_name, items, model: model)

  defp do_followup_provider(:anthropic, session_name, items, model),
    do: Anthropic.Streaming.stream_tool_followup(session_name, items, model: model)

  defp do_followup_provider(:gemini, session_name, items, model),
    do: Gemini.Streaming.stream_tool_followup(session_name, items, model: model)

  defp resolve_base_cwd(session) do
    case session.working_dir do
      wd when is_binary(wd) and wd != "" -> Path.expand(wd)
      _ -> File.cwd!() |> Path.expand()
    end
  end

  defp exec_tools(calls, base_cwd) do
    Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
      case ToolsRuntime.exec(name, args, base_cwd) do
        {:ok, payload} -> {id, {:ok, payload}}
        {:error, reason} -> {id, {:error, to_string(reason)}}
      end
    end)
  end

  defp build_openai_items(last_user_text, partial_answer, calls, outputs) do
    user_ctx_items =
      if is_binary(last_user_text) and last_user_text != "",
        do: [
          %{
            "type" => "message",
            "role" => "user",
            "content" => [%{"type" => "input_text", "text" => last_user_text}]
          }
        ],
        else: []

    prior_msg =
      if partial_answer != "",
        do: [
          %{
            "type" => "message",
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => partial_answer}]
          }
        ],
        else: []

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

    user_ctx_items ++ prior_msg ++ fc_items ++ out_items
  end

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

  defp build_gemini_items(last_user_text, partial_answer, calls, outputs) do
    last_user_parts =
      if is_binary(last_user_text) and last_user_text != "",
        do: [%{"text" => last_user_text}],
        else: []

    prior_parts = if partial_answer != "", do: [%{"text" => partial_answer}], else: []

    fc_items =
      Enum.map(calls, fn %{"id" => id, "name" => name} ->
        %{"functionCall" => %{"name" => name, "args" => %{}, "id" => id}}
      end)

    out_items =
      Enum.map(outputs, fn {id, result} ->
        %{
          "functionResponse" => %{
            "name" => find_name_for_call(id, calls),
            "response" => tool_output_payload(result),
            "id" => id
          }
        }
      end)

    [] ++
      if(last_user_parts == [], do: [], else: [%{"role" => "user", "parts" => last_user_parts}]) ++
      if(prior_parts == [], do: [], else: [%{"role" => "model", "parts" => prior_parts}]) ++
      fc_items ++ out_items
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
end

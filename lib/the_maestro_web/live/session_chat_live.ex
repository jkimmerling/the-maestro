defmodule TheMaestroWeb.SessionChatLive do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # credo:disable-for-this-file Credo.Check.Readability.PreferCaseTrivialWith
  # credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Provider
  alias TheMaestro.SuppliedContext
  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Conversations.get_session_with_auth!(id)

    {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)
    TheMaestro.Chat.subscribe(session.id)

    # Determine current thread (latest) for display
    tid = Conversations.latest_thread_id(session.id)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:session, session)
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, (tid && Conversations.thread_label(tid)) || nil)
     |> assign(:message, "")
     |> assign(:messages, current_messages_for(session.id, tid))
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_id, nil)
     |> assign(:stream_task, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:followup_history, [])
     |> assign(:summary, compute_summary(current_messages_for(session.id, tid)))
     |> assign(:editing_latest, false)
     |> assign(:latest_json, nil)
     |> assign(:show_config, false)
     |> assign(:config_form, %{})
     |> assign(:config_models, [])
     |> assign(:config_persona_options, [])
     |> assign(:show_clear_confirm, false)
     |> assign(:show_persona_modal, false)
     |> assign(:persona_form, %{})
     |> assign(:show_memory_modal, false)
     |> assign(:memory_editor_text, nil)}
  end

  @impl true
  def handle_event("change", %{"message" => msg}, socket) do
    {:noreply, assign(socket, :message, msg)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, %{assigns: %{session: %{id: current_id}}} = socket)
      when is_binary(id) and id != current_id do
    # Unsubscribe from old session topic and rehydrate assigns for new session
    _ = TheMaestro.Chat.unsubscribe(current_id)

    session = Conversations.get_session_with_auth!(id)
    {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)
    :ok = TheMaestro.Chat.subscribe(session.id)

    tid = Conversations.latest_thread_id(session.id)
    msgs = current_messages_for(session.id, tid)

    {:noreply,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:session, session)
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, (tid && Conversations.thread_label(tid)) || nil)
     |> assign(:message, "")
     |> assign(:messages, msgs)
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_id, nil)
     |> assign(:stream_task, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:followup_history, [])
     |> assign(:summary, compute_summary(msgs))
     |> assign(:editing_latest, false)
     |> assign(:latest_json, nil)
     |> assign(:show_config, false)
     |> assign(:config_form, %{})
     |> assign(:config_models, [])
     |> assign(:config_persona_options, [])
     |> assign(:show_clear_confirm, false)
     |> assign(:show_persona_modal, false)
     |> assign(:persona_form, %{})
     |> assign(:show_memory_modal, false)
     |> assign(:memory_editor_text, nil)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

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

  # ==== Toolbar events ====
  @impl true
  def handle_event("new_thread", _params, socket) do
    {:ok, tid} = Conversations.new_thread(socket.assigns.session)

    msgs = current_messages_for(socket.assigns.session.id, tid)

    {:noreply,
     socket
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, Conversations.thread_label(tid))
     |> assign(:messages, msgs)
     |> assign(:summary, compute_summary(msgs))
     |> put_flash(:info, "Started new chat thread")}
  end

  @impl true
  def handle_event("confirm_clear_chat", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, true)}
  end

  @impl true
  def handle_event("cancel_clear_chat", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, false)}
  end

  @impl true
  def handle_event("do_clear_chat", _params, socket) do
    case socket.assigns.current_thread_id do
      tid when is_binary(tid) ->
        {:ok, _} = Conversations.delete_thread_entries(tid)

        {:noreply,
         socket
         |> assign(:show_clear_confirm, false)
         |> assign(:messages, [])
         |> assign(:summary, nil)
         |> put_flash(:info, "Cleared current chat thread")}

      _ ->
        {:noreply, assign(socket, :show_clear_confirm, false)}
    end
  end

  @impl true
  def handle_event("rename_thread", %{"label" => label}, socket) do
    case socket.assigns.current_thread_id do
      tid when is_binary(tid) and label != "" ->
        {:ok, _} = Conversations.set_thread_label(tid, label)
        {:noreply, assign(socket, :current_thread_label, label)}

      _ ->
        {:noreply, socket}
    end
  end

  # ==== Config modal events ====
  @impl true
  def handle_event("open_config", _params, socket) do
    form0 = %{
      "provider" => default_provider(socket.assigns.session),
      "auth_id" => socket.assigns.session.auth_id,
      "model_id" => socket.assigns.session.model_id,
      "working_dir" => socket.assigns.session.working_dir
    }

    {:noreply,
     socket
     |> assign(:config_form, form0)
     |> assign(:config_models, [])
     |> load_auth_options(form0)
     |> load_persona_options()
     |> assign(:show_config, true)}
  end

  @impl true
  def handle_event("close_config", _params, socket) do
    {:noreply, assign(socket, :show_config, false)}
  end

  @impl true
  def handle_event("validate_config", params, socket) do
    form = Map.merge(socket.assigns.config_form || %{}, params)
    socket = assign(socket, :config_form, form)

    # If provider changed, reload auth options and clear model list
    socket =
      if Map.has_key?(params, "provider") do
        # Reload provider-specific auth options and ensure auth_id selection is valid
        socket = socket |> load_auth_options(form) |> assign(:config_models, [])
        new_form = socket.assigns.config_form
        opts = new_form["auth_options"] || []

        new_auth_id =
          case opts do
            [{_label, id} | _] -> id
            _ -> nil
          end

        assign(socket, :config_form, Map.put(new_form, "auth_id", new_auth_id))
      else
        socket
      end

    # If auth_id changed, load models
    socket =
      if Map.has_key?(params, "auth_id") do
        models = list_models_for_form(socket.assigns.config_form)
        assign(socket, :config_models, models)
      else
        socket
      end

    # If persona_id changed, mirror into persona_json
    socket =
      if Map.has_key?(params, "persona_id") do
        case get_persona_for_form(form) do
          nil ->
            socket

          %TheMaestro.SuppliedContext.SuppliedContextItem{} = p ->
            pj =
              Jason.encode!(%{
                "name" => p.name,
                "version" => p.version || 1,
                "persona_text" => p.text
              })

            assign(socket, :config_form, Map.put(socket.assigns.config_form, "persona_json", pj))
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # ==== Persona modal ====
  @impl true
  def handle_event("open_persona_modal", _params, socket) do
    {:noreply, socket |> assign(:show_persona_modal, true) |> assign(:persona_form, %{})}
  end

  @impl true
  def handle_event("cancel_persona_modal", _params, socket) do
    {:noreply, assign(socket, :show_persona_modal, false)}
  end

  @impl true
  def handle_event("save_persona", %{"name" => name, "prompt_text" => text}, socket) do
    case SuppliedContext.create_item(%{type: :persona, name: name, text: text, version: 1}) do
      {:ok, persona} ->
        pj =
          Jason.encode!(%{
            "name" => persona.name,
            "version" => persona.version || 1,
            "persona_text" => persona.text
          })

        socket =
          socket
          |> load_persona_options()
          |> assign(
            :config_form,
            (socket.assigns.config_form || %{})
            |> Map.put("persona_id", persona.id)
            |> Map.put("persona_json", pj)
          )

        {:noreply,
         socket |> assign(:show_persona_modal, false) |> put_flash(:info, "Persona created")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create persona: #{inspect(changeset.errors)}")}
    end
  end

  # ==== Memory modal ====
  @impl true
  def handle_event("open_memory_modal", _params, socket) do
    mem =
      socket.assigns.config_form["memory_json"] ||
        Jason.encode!(socket.assigns.session.memory || %{})

    {:noreply, socket |> assign(:show_memory_modal, true) |> assign(:memory_editor_text, mem)}
  end

  @impl true
  def handle_event("cancel_memory_modal", _params, socket) do
    {:noreply, assign(socket, :show_memory_modal, false)}
  end

  @impl true
  def handle_event("save_memory_modal", %{"memory_json" => txt}, socket) do
    case Jason.decode(txt) do
      {:ok, %{} = _map} ->
        socket =
          assign(socket, :config_form, Map.put(socket.assigns.config_form, "memory_json", txt))

        {:noreply,
         socket |> assign(:show_memory_modal, false) |> put_flash(:info, "Memory updated")}

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "Memory JSON must be an object")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("save_config", params, socket) do
    # Decode JSON fields safely
    with {:ok, persona} <-
           safe_decode(
             params["persona_json"] || Jason.encode!(socket.assigns.session.persona || %{})
           ),
         {:ok, memory} <-
           safe_decode(
             params["memory_json"] || Jason.encode!(socket.assigns.session.memory || %{})
           ),
         {:ok, tools} <-
           safe_decode(params["tools_json"] || Jason.encode!(socket.assigns.session.tools || %{})),
         {:ok, mcps} <-
           safe_decode(params["mcps_json"] || Jason.encode!(socket.assigns.session.mcps || %{})) do
      attrs = %{
        "auth_id" => params["auth_id"] || socket.assigns.session.auth_id,
        "model_id" => params["model_id"] || socket.assigns.session.model_id,
        "working_dir" => params["working_dir"] || socket.assigns.session.working_dir,
        "persona" => persona,
        "memory" => memory,
        "tools" => tools,
        "mcps" => mcps
      }

      case Conversations.update_session(socket.assigns.session, attrs) do
        {:ok, updated} ->
          socket = assign(socket, :session, updated)
          apply_behavior = params["apply"] || "now"

          socket =
            if apply_behavior == "now" and socket.assigns.streaming? do
              # Cancel existing stream and restart using current pending canonical or latest snapshot
              _ = TheMaestro.Chat.cancel_turn(updated.id)
              provider = provider_from_session(updated)

              canon =
                socket.assigns.pending_canonical ||
                  (Conversations.latest_snapshot(updated.id) ||
                     %{combined_chat: %{"messages" => []}})
                  |> Map.get(:combined_chat, %{"messages" => []})

              {:ok, provider_msgs} = Translator.to_provider(canon, provider)
              model = pick_model_for_session(updated, provider)

              {:ok, stream_id} =
                TheMaestro.Chat.start_stream(
                  updated.id,
                  provider,
                  elem(auth_meta_from_session(updated), 1),
                  provider_msgs,
                  model
                )

              socket
              |> assign(:stream_id, stream_id)
              |> assign(:used_provider, provider)
              |> assign(:used_model, model)
              |> assign(:used_usage, nil)
              |> assign(:thinking?, true)
            else
              socket
            end

          {:noreply,
           socket
           |> assign(:show_config, false)
           |> put_flash(
             :info,
             if(apply_behavior == "now",
               do: "Config applied and stream restarted",
               else: "Config saved; applied next turn"
             )
           )}

        {:error, changeset} ->
          {:noreply,
           put_flash(socket, :error, "Failed to save config: #{inspect(changeset.errors)}")}
      end
    else
      {:error, {:decode, field, reason}} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON for #{field}: #{inspect(reason)}")}
    end
  end

  # ===== Streaming turn handling =====
  defp start_streaming_turn(socket, user_text) do
    session = socket.assigns.session
    latest = Conversations.latest_snapshot(session.id)

    canonical = (latest && latest.combined_chat) || %{"messages" => []}

    updated =
      put_in(canonical, ["messages"], (canonical["messages"] || []) ++ [user_msg(user_text)])

    # Ensure we have a thread to attach this turn to
    {tid, socket} =
      case socket.assigns[:current_thread_id] do
        id when is_binary(id) ->
          {id, socket}

        _ ->
          {:ok, new_tid} = TheMaestro.Chat.ensure_thread(session.id)
          {new_tid, assign(socket, :current_thread_id, new_tid)}
      end

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
        thread_id: tid,
        edit_version: 0
      })

    # Optimistically update UI conversation
    ui_messages =
      (socket.assigns.messages || []) ++
        [%{"role" => "user", "content" => [%{"type" => "text", "text" => user_text}]}]

    # Determine provider/model
    provider =
      provider_from_session(session)

    model = pick_model_for_session(session, provider)
    {auth_type, auth_name} = auth_meta_from_session(session)
    {:ok, provider_msgs} = Translator.to_provider(updated, provider)

    t0 = System.monotonic_time(:millisecond)

    {:ok, stream_id} =
      TheMaestro.Chat.start_stream(
        session.id,
        provider,
        auth_name,
        provider_msgs,
        model
      )

    socket
    |> assign(:message, "")
    |> assign(:messages, ui_messages)
    |> assign(:streaming?, true)
    |> assign(:partial_answer, "")
    |> assign(:stream_id, stream_id)
    |> assign(:stream_task, nil)
    |> assign(:pending_canonical, updated)
    |> assign(:followup_history, [])
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
    {auth_type, _} = auth_meta_from_session(session)

    case auth_type do
      :oauth -> "gpt-5"
      _ -> "gpt-4o"
    end
  end

  defp default_model_for_session(_session, :anthropic), do: "claude-3-5-sonnet"

  defp default_model_for_session(session, :gemini) do
    {auth_type, _} = auth_meta_from_session(session)

    case auth_type do
      :oauth -> "gemini-2.5-pro"
      _ -> "gemini-1.5-pro-latest"
    end
  end

  defp default_model_for_session(_session, _), do: ""

  # Try to pick a valid model from the provider's list; fallback to defaults
  defp pick_model_for_session(session, provider) do
    chosen = session.model_id

    if is_binary(chosen) and chosen != "" do
      chosen
    else
      choose_model_from_provider(session, provider)
    end
  end

  defp choose_model_from_provider(session, provider) do
    default = default_model_for_session(session, provider)
    {auth_type, session_name} = auth_meta_from_session(session)

    case Provider.list_models(provider, auth_type, session_name) do
      {:ok, models} when is_list(models) and models != [] ->
        ids = Enum.map(models, & &1.id)
        if default in ids, do: default, else: hd(ids)

      _ ->
        default
    end
  end

  # Provider calls moved to TheMaestro.Sessions.Manager

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
     |> assign(:used_usage, usage)
     |> assign(
       :summary,
       (fn ->
          msgs = socket.assigns.messages || []
          # Keep summary updated to reflect latest token totals
          compute_summary(msgs)
        end).()
     )}
  end

  def handle_info({:ai_stream, id, %{type: :done}}, %{assigns: %{stream_id: id}} = socket) do
    # Manager now owns finalization and tool follow-ups; we only mark UI state
    {:noreply, push_event(socket, %{kind: "ai", type: "done", at: now_ms()})}
  end

  # Ignore stale stream messages (ids that do not match current stream)
  def handle_info(
        {:ai_stream, other_id, _msg},
        %{assigns: %{stream_id: id}} = socket
      )
      when other_id != id do
    {:noreply, socket}
  end

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
        {:ok, stream_id} =
          TheMaestro.Chat.start_stream(
            socket.assigns.session.id,
            provider,
            socket.assigns.used_auth_name,
            provider_msgs,
            model
          )

        {:noreply,
         socket
         |> assign(:stream_id, stream_id)
         |> assign(:stream_task, nil)
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

  # (moved catch-all to bottom to avoid shadowing specialized clauses)

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

  # ---- Session helpers (derive provider/auth from SavedAuth) ----
  defp provider_from_session(session) do
    saved = session.saved_authentication

    cond do
      match?(%Ecto.Association.NotLoaded{}, saved) and session.auth_id ->
        sa = Auth.get_saved_authentication!(session.auth_id)
        to_provider_atom(sa.provider)

      is_map(saved) ->
        to_provider_atom(saved.provider)

      true ->
        # Fallback to openai to avoid crashes; will be corrected on next turn
        :openai
    end
  end

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

  defp default_provider(session) do
    saved = session.saved_authentication
    (saved && to_string(saved.provider)) || "openai"
  end

  defp load_auth_options(socket, form) do
    provider_value = form["provider"] || default_provider(socket.assigns.session)

    # Accept provider as string for Auth context (it normalizes input)
    opts =
      Auth.list_saved_authentications_by_provider(provider_value)
      |> Enum.map(fn sa ->
        label = "#{sa.name} (#{Atom.to_string(sa.auth_type)})"
        {label, sa.id}
      end)

    assign(socket, :config_form, Map.put(form, "auth_options", opts))
  end

  defp load_persona_options(socket) do
    opts =
      SuppliedContext.list_items(:persona)
      |> Enum.map(fn p -> {p.name, p.id} end)

    socket
    |> assign(:config_persona_options, opts)
  end

  defp get_persona_for_form(form) do
    case form["persona_id"] do
      nil ->
        nil

      "" ->
        nil

      id ->
        try do
          SuppliedContext.get_item!(to_string(id))
        rescue
          _ -> nil
        end
    end
  end

  defp list_models_for_form(form) do
    with p when is_binary(p) <- form["provider"],
         a when a not in [nil, ""] <- form["auth_id"] do
      provider = to_provider_atom(p)
      auth = Auth.get_saved_authentication!(a)

      case TheMaestro.Provider.list_models(provider, auth.auth_type, auth.name) do
        {:ok, models} -> Enum.map(models, & &1.id)
        {:error, _} -> []
      end
    else
      _ -> []
    end
  end

  # Convert a provider string to a known atom safely; default to :openai
  defp to_provider_atom(p) when is_atom(p), do: p

  defp to_provider_atom(p) when is_binary(p) do
    allowed = TheMaestro.Provider.list_providers()
    allowed_strings = Enum.map(allowed, &Atom.to_string/1)

    if p in allowed_strings do
      String.to_existing_atom(p)
    else
      :openai
    end
  end

  defp safe_decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      {:ok, _} -> {:error, {:decode, :json, :must_be_object}}
      {:error, reason} -> {:error, {:decode, :json, reason}}
    end
  end

  # IDs are binary_id strings now; no integer casting

  defp effective_provider(socket, session) do
    socket.assigns.used_provider || provider_from_session(session)
  end

  defp build_req_meta(socket, session, provider) do
    {auth_type, auth_name} = auth_meta_from_session(session)

    %{
      "provider" => Atom.to_string(provider),
      "model" => socket.assigns.used_model || default_model_for_session(session, provider),
      "auth_type" => to_string(socket.assigns.used_auth_type || auth_type),
      "auth_name" => socket.assigns.used_auth_name || auth_name,
      "usage" => socket.assigns.used_usage || %{}
    }
  end

  # Manager publishes a :finalized event with the persisted meta and text
  def handle_info(
        {:ai_stream, id, %{type: :finalized, content: final_text, meta: req_meta, usage: usage}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    meta = Map.put(req_meta || %{}, "usage", usage || %{})
    messages = append_assistant_message(socket.assigns.messages || [], final_text || "", meta)

    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_task, nil)
     |> assign(:stream_id, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:followup_history, [])
     |> assign(:thinking?, false)
     |> assign(:used_usage, nil)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:summary, compute_summary(messages))
     |> assign(:messages, messages)}
  end

  # Catch-all to ignore unrelated messages (e.g., internal task signals)
  def handle_info(_other, socket), do: {:noreply, socket}

  # moved to orchestrator
  defp run_pending_tools_and_follow_up(socket, _calls), do: {:ok, socket}
  # (old in-LV follow-up logic removed; handled by orchestrator)

  # moved to orchestrator

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

  defp current_messages_for(session_id, nil) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  defp current_messages_for(_session_id, thread_id) when is_binary(thread_id) do
    case Conversations.latest_snapshot_for_thread(thread_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; SESSION CHAT: {@session.name || "Session"} &lt;&lt;&lt;
            </h1>
            <div class="flex items-center gap-2">
              <%= if @current_thread_label do %>
                <form phx-submit="rename_thread" class="flex items-center gap-2">
                  <input
                    type="text"
                    name="label"
                    value={@current_thread_label}
                    class="input input-xs"
                  />
                  <button class="btn btn-xs" type="submit">Rename</button>
                </form>
              <% end %>
              <button class="btn btn-amber btn-xs" phx-click="new_thread">Start New Chat</button>
              <button class="btn btn-red btn-xs" phx-click="confirm_clear_chat">Clear Chat</button>
              <button class="btn btn-blue btn-xs" phx-click="open_config">Config</button>
            </div>
            <.link
              navigate={~p"/dashboard"}
              class="px-4 py-2 rounded transition-all duration-200 btn-amber"
              data-hotkey="alt+b"
              data-hotkey-seq="g d"
              data-hotkey-label="Go to Dashboard"
            >
              <.icon name="hero-arrow-left" class="inline mr-2 w-4 h-4" /> BACK
            </.link>
          </div>

          <div class="sticky top-0 z-10 bg-black/90 border-b border-amber-600 -mt-2 mb-4 py-2 px-2 text-xs text-amber-300">
            <%= if s = @summary do %>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
                <div class="glow">
                  last: {s.provider}, {s.model}, {s.auth_type}{if s.auth_name,
                    do: "(" <> s.auth_name <> ")"}
                </div>
                <div>avg latency: {s.avg_latency_ms} ms</div>
                <%= if s[:total_tokens] do %>
                  <div>last turn tokens: {compact_int(s.total_tokens)}</div>
                <% end %>
              </div>
            <% else %>
              <div class="opacity-70">No summary yet</div>
            <% end %>
          </div>

          <div class="space-y-3">
            <%= for msg <- @messages do %>
              <div class={"terminal-card p-3 " <> if msg["role"] == "user", do: "terminal-border-amber", else: "terminal-border-blue"}>
                <div class="text-xs opacity-80">
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
                <div class="whitespace-pre-wrap text-sm text-amber-200">
                  <.render_text chat={%{"messages" => [msg]}} />
                </div>
                <%= if m = msg["_meta"] do %>
                  <details class="mt-1 opacity-80 text-xs">
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
                          <li>
                            <code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 120)}
                          </li>
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
              <div class="terminal-card terminal-border-amber p-3">
                <div class="text-xs opacity-80">tool activity</div>
                <ul class="list-disc ml-4 text-sm text-amber-200">
                  <%= for t <- @tool_calls do %>
                    <li><code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 160)}</li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%= if @streaming? and @partial_answer == "" and @thinking? do %>
              <div class="terminal-card terminal-border-blue p-3">
                <div class="text-xs opacity-80">assistant</div>
                <div class="opacity-80 italic text-sm text-amber-200">thinking…</div>
              </div>
            <% end %>

            <%= if @streaming? and @partial_answer != "" do %>
              <div class="terminal-card terminal-border-blue p-3">
                <div class="text-xs opacity-80">
                  assistant
                  <%= if @used_provider do %>
                    ( {Atom.to_string(@used_provider)}, {@used_model}, {to_string(
                      @used_auth_type || ""
                    )}
                    <%= if u = @used_usage do %>
                      , total {compact_int(token_total(u))}
                    <% end %>
                    )
                  <% end %>
                </div>
                <div class="whitespace-pre-wrap text-sm text-amber-200">{@partial_answer}</div>
                <%= if u = @used_usage do %>
                  <details class="mt-1 opacity-80 text-xs">
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

          <.form for={%{}} phx-submit="send" class="mt-6">
            <textarea
              id="chat-input"
              name="message"
              class="textarea-terminal"
              rows="4"
              value={@message}
              phx-change="change"
              phx-hook="ChatInput"
            ></textarea>
            <div class="mt-2">
              <button type="submit" class="px-4 py-2 rounded transition-all duration-200 btn-blue">
                Send
              </button>
            </div>
          </.form>

          <div class="mt-8">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-lg font-bold text-green-400 glow">LATEST_SNAPSHOT.JSON</h3>
              <%= if @editing_latest do %>
                <button class="px-2 py-1 rounded text-xs btn-amber" phx-click="cancel_edit_latest">
                  CANCEL
                </button>
              <% else %>
                <button class="px-2 py-1 rounded text-xs btn-amber" phx-click="start_edit_latest">
                  EDIT
                </button>
              <% end %>
            </div>
            <%= if @editing_latest do %>
              <.form for={%{}} phx-submit="save_edit_latest">
                <textarea
                  name="json"
                  class="textarea-terminal font-mono text-xs"
                  rows="10"
                ><%= @latest_json %></textarea>
                <div class="mt-2">
                  <button type="submit" class="px-3 py-1 rounded btn-blue text-sm">
                    Save Snapshot
                  </button>
                </div>
              </.form>
            <% else %>
              <div class="text-xs opacity-80 text-amber-300">
                Editing allows trimming or correcting the current context (full copy). Changes bump edit_version.
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />

      <.modal :if={@show_clear_confirm} id="clear-chat-confirm">
        <div class="p-4">
          <h3 class="text-lg font-bold mb-2">Clear Current Chat?</h3>
          <p class="mb-4">
            This will permanently delete the current thread history. This cannot be undone.
          </p>
          <div class="flex gap-2">
            <button class="btn btn-red" phx-click="do_clear_chat">Delete</button>
            <button class="btn" phx-click="cancel_clear_chat">Cancel</button>
          </div>
        </div>
      </.modal>

      <.modal :if={@show_config} id="session-config-modal">
        <.form
          for={%{}}
          phx-change="validate_config"
          phx-submit="save_config"
          id="session-config-form"
        >
          <h3 class="text-lg font-bold mb-2">Session Config</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label class="text-xs">Provider (filter)</label>
              <select name="provider" class="input">
                <%= for p <- ["openai", "anthropic", "gemini"] do %>
                  <option value={p} selected={@config_form["provider"] == p}>{p}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-xs">Saved Auth</label>
              <select name="auth_id" class="input">
                <%= for {label, id} <- (@config_form["auth_options"] || []) do %>
                  <option value={id} selected={to_string(id) == to_string(@config_form["auth_id"])}>
                    {label}
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-xs">Model</label>
              <select name="model_id" class="input">
                <%= for m <- (@config_models || []) do %>
                  <option value={m} selected={m == @config_form["model_id"]}>{m}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="text-xs">Working Dir</label>
              <input
                type="text"
                name="working_dir"
                value={@config_form["working_dir"] || @session.working_dir}
                class="input"
              />
            </div>
            <div>
              <label class="text-xs">Persona</label>
              <div class="flex gap-2 items-center">
                <select name="persona_id" class="input">
                  <option value="">(custom JSON)</option>
                  <%= for {label, id} <- (@config_persona_options || []) do %>
                    <option
                      value={id}
                      selected={to_string(id) == to_string(@config_form["persona_id"])}
                    >
                      {label}
                    </option>
                  <% end %>
                </select>
                <button type="button" class="btn btn-xs" phx-click="open_persona_modal">
                  Add Persona…
                </button>
              </div>
            </div>
            <div class="md:col-span-2">
              <label class="text-xs">Persona (JSON)</label>
              <textarea name="persona_json" rows="3" class="textarea-terminal"><%= @config_form["persona_json"] || Jason.encode!(@session.persona || %{}) %></textarea>
            </div>
            <div class="md:col-span-2">
              <label class="text-xs">Memory (JSON)</label>
              <textarea name="memory_json" rows="3" class="textarea-terminal"><%= @config_form["memory_json"] || Jason.encode!(@session.memory || %{}) %></textarea>
              <div class="mt-1">
                <button type="button" class="btn btn-xs" phx-click="open_memory_modal">
                  Open Advanced Editor…
                </button>
              </div>
            </div>
            <div class="md:col-span-2">
              <label class="text-xs">Tools (JSON)</label>
              <textarea name="tools_json" rows="3" class="textarea-terminal"><%= @config_form["tools_json"] || Jason.encode!(@session.tools || %{}) %></textarea>
            </div>
            <div class="md:col-span-2">
              <label class="text-xs">MCPs (JSON)</label>
              <textarea name="mcps_json" rows="3" class="textarea-terminal"><%= @config_form["mcps_json"] || Jason.encode!(@session.mcps || %{}) %></textarea>
            </div>
          </div>
          <div class="mt-3">
            <label class="text-xs">When saving while streaming</label>
            <div class="flex gap-3 text-sm">
              <label>
                <input type="radio" name="apply" value="now" checked /> Apply now (restart stream)
              </label>
              <label><input type="radio" name="apply" value="defer" /> Apply on next turn</label>
            </div>
          </div>
          <div class="mt-4 flex gap-2">
            <button class="btn btn-blue" type="submit">Save</button>
            <button class="btn" type="button" phx-click="close_config">Cancel</button>
          </div>
        </.form>
      </.modal>

      <.modal :if={@show_persona_modal} id="persona-modal">
        <.form for={%{}} phx-submit="save_persona" id="persona-form">
          <h3 class="text-lg font-bold mb-2">Add Persona</h3>
          <div class="grid grid-cols-1 gap-2">
            <div>
              <label class="text-xs">Name</label>
              <input type="text" name="name" class="input" />
            </div>
            <div>
              <label class="text-xs">Prompt Text</label>
              <textarea name="prompt_text" rows="6" class="textarea-terminal"></textarea>
            </div>
          </div>
          <div class="mt-3 flex gap-2">
            <button class="btn btn-blue" type="submit">Save</button>
            <button class="btn" type="button" phx-click="cancel_persona_modal">Cancel</button>
          </div>
        </.form>
      </.modal>

      <.modal :if={@show_memory_modal} id="memory-modal">
        <.form for={%{}} phx-submit="save_memory_modal" id="memory-form">
          <h3 class="text-lg font-bold mb-2">Memory — Advanced JSON Editor</h3>
          <textarea name="memory_json" rows="12" class="textarea-terminal"><%= @memory_editor_text %></textarea>
          <div class="mt-3 flex gap-2">
            <button class="btn btn-blue" type="submit">Save</button>
            <button class="btn" type="button" phx-click="cancel_memory_modal">Cancel</button>
          </div>
        </.form>
      </.modal>
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
        avg_latency_ms: avg || 0,
        total_tokens: token_total(m["usage"] || %{})
      }
    else
      nil
    end
  end

  defp compute_summary(_), do: nil
end

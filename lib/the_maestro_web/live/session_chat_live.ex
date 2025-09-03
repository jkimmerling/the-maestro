defmodule TheMaestroWeb.SessionChatLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Provider
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}
  alias TheMaestro.Providers.Anthropic.ToolsTranslator, as: AnthropicTools
  alias TheMaestro.Providers.Gemini.ToolsTranslator, as: GeminiTools
  alias TheMaestro.Providers.OpenAI.ToolsTranslator, as: OpenAITools
  alias TheMaestro.Tools.Router, as: ToolsRouter
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
               session.agent,
               session.agent.saved_authentication.name,
               provider_msgs,
               model
             ) do
          {:ok, stream} ->
            for msg <-
                  TheMaestro.Streaming.parse_stream(stream, provider, log_unknown_events: true),
                do: send(parent, {:ai_stream, stream_id, msg})

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
    |> assign(:used_t0_ms, t0)
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
  defp default_model_for_session(_session, :gemini), do: "gemini-1.5-pro-latest"
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
  defp call_provider(:openai, agent, session_name, messages, model) do
    tools = TheMaestro.Tools.Registry.list_tools(agent)
    tool_decls = OpenAITools.declare_tools(tools)
    OpenAI.Streaming.stream_chat(session_name, messages, model: model, tools: tool_decls)
  end

  defp call_provider(:gemini, agent, session_name, messages, model) do
    tools = TheMaestro.Tools.Registry.list_tools(agent)
    tool_decls = GeminiTools.declare_tools(tools)
    Gemini.Streaming.stream_chat(session_name, messages, model: model, tools: tool_decls)
  end

  defp call_provider(:anthropic, agent, session_name, messages, model) do
    tools = TheMaestro.Tools.Registry.list_tools(agent)
    tool_decls = AnthropicTools.declare_tools(tools)
    Anthropic.Streaming.stream_chat(session_name, messages, model: model, tools: tool_decls)
  end

  require Logger

  @impl true
  # Show thinking indicator until first text arrives
  def handle_info(
        {:ai_stream, id, %{type: :content, metadata: %{thinking: true}}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    {:noreply, assign(socket, thinking?: true)}
  end

  def handle_info(
        {:ai_stream, id, %{type: :content, content: chunk}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    current = socket.assigns.partial_answer || ""
    delta = dedup_delta(current, chunk)
    new_partial = current <> delta
    # Render progressively
    {:noreply, assign(socket, partial_answer: new_partial, thinking?: false)}
  end

  # Tool function calls: execute via Router and continue streaming with injected results
  def handle_info(
        {:ai_stream, id, %{type: :function_call, function_call: calls}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    session = socket.assigns.session
    provider = effective_provider(socket, session)
    model = socket.assigns.used_model || default_model_for_session(session, provider)

    kill_stream_if_any(socket)

    new_canonical = reduce_with_tool_calls(calls || [], socket.assigns.pending_canonical, session)

    {stream_id, task} =
      start_stream_with_canonical(
        new_canonical,
        provider,
        model,
        session.agent.saved_authentication.name,
        session.agent
      )

    {:noreply,
     socket
     |> assign(:stream_task, task)
     |> assign(:stream_id, stream_id)
     |> assign(:pending_canonical, new_canonical)
     |> assign(:thinking?, true)}
  end

  def handle_info(
        {:ai_stream, id, %{type: :error, error: err}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    Logger.error("stream error: #{inspect(err)}")
    {:noreply, socket |> put_flash(:error, "Provider error: #{err}") |> assign(thinking?: false)}
  end

  @impl true
  def handle_info(
        {:ai_stream, id, %{type: :usage, usage: usage}},
        %{assigns: %{stream_id: id}} = socket
      ) do
    # Accumulate latest usage for this stream to attach on finalize
    {:noreply, assign(socket, :used_usage, usage)}
  end

  def handle_info({:ai_stream, id, %{type: :done}}, %{assigns: %{stream_id: id}} = socket) do
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

    persist_assistant_turn(session, final_text, req_meta, updated2, socket.assigns.used_usage)

    meta = %{
      "provider" => req_meta["provider"],
      "model" => req_meta["model"],
      "auth_type" => req_meta["auth_type"],
      "auth_name" => req_meta["auth_name"],
      "usage" => req_meta["usage"]
    }

    messages = append_assistant_message(socket.assigns.messages || [], final_text, meta)

    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_task, nil)
     |> assign(:stream_id, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:used_usage, nil)
     |> assign(:summary, compute_summary(messages))
     |> assign(:messages, messages)}
  end

  # Ignore stale stream messages
  def handle_info({:ai_stream, _other, _msg}, socket), do: {:noreply, socket}

  # ===== Helpers for function-call loop =====
  defp kill_stream_if_any(socket) do
    if task = socket.assigns.stream_task do
      Process.exit(task, :kill)
    end
  end

  defp reduce_with_tool_calls(calls, canonical, session) do
    Enum.reduce(calls, canonical, fn call, acc ->
      call_map = build_call_map(call)
      trust? = (session.agent.tools || %{})["trust"] || false
      result_text = tool_result_text(session.agent, session.id, trust?, call_map)
      put_in(acc, ["messages"], (acc["messages"] || []) ++ [user_msg(result_text)])
    end)
  end

  defp build_call_map(call) do
    %{
      "id" => Map.get(call, :id) || Map.get(call, "id"),
      "function" => %{
        "name" => get_in(call, [:function, :name]) || get_in(call, ["function", "name"]),
        "arguments" =>
          get_in(call, [:function, :arguments]) || get_in(call, ["function", "arguments"]) || "{}"
      }
    }
  end

  defp start_stream_with_canonical(new_canonical, provider, model, session_name, agent) do
    {:ok, provider_msgs} = Translator.to_provider(new_canonical, provider)
    stream_id = Ecto.UUID.generate()
    parent = self()

    task =
      Task.start_link(fn ->
        case call_provider(provider, agent, session_name, provider_msgs, model) do
          {:ok, stream} ->
            for msg <-
                  TheMaestro.Streaming.parse_stream(stream, provider, log_unknown_events: true),
                do: send(parent, {:ai_stream, stream_id, msg})

          {:error, reason} ->
            send(parent, {:ai_stream, stream_id, %{type: :error, error: inspect(reason)}})
            send(parent, {:ai_stream, stream_id, %{type: :done}})
        end
      end)
      |> elem(1)

    {stream_id, task}
  end

  @dialyzer {:nowarn_function, tool_result_text: 4}
  defp tool_result_text(agent, session_id, trust?, call_map) do
    res = ToolsRouter.execute(agent, call_map, session_id: session_id, trust: trust?)

    case res do
      {:ok, data} -> "[tool #{data.name}]:\n\n" <> (to_string(data.text) |> String.trim())
      {:error, reason} -> "[tool_error]: #{inspect(reason)}"
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

  defp persist_assistant_turn(_session, final_text, _req_meta, _updated2, _used_usage)
       when final_text == "",
       do: :ok

  defp persist_assistant_turn(session, _final_text, req_meta, updated2, used_usage) do
    req_hdrs = %{
      "provider" => req_meta["provider"],
      "model" => req_meta["model"],
      "auth_type" => req_meta["auth_type"],
      "auth_name" => req_meta["auth_name"]
    }

    resp_hdrs = %{"usage" => used_usage || %{}}

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
                <%= if m["latency_ms"] do %>
                  <div>latency: {m["latency_ms"]} ms</div>
                <% end %>
              </details>
            <% end %>
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

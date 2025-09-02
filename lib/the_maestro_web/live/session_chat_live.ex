defmodule TheMaestroWeb.SessionChatLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.Translator
  alias TheMaestro.Providers.{Anthropic, Gemini, OpenAI}

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
     |> assign(:history, Conversations.list_chat_entries(session.id))
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
      {:noreply, do_user_and_model_turn(socket, msg)}
    end
  end

  @impl true
  def handle_event("start_edit_latest", _params, socket) do
    case Conversations.latest_snapshot(socket.assigns.session.id) do
      nil -> {:noreply, socket}
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
      _ -> {:noreply, put_flash(socket, :error, "Could not save latest snapshot")}
    end
  end

  defp do_user_and_model_turn(socket, user_text) do
    session = socket.assigns.session
    latest = Conversations.latest_snapshot(session.id)

    canonical = (latest && latest.combined_chat) || %{"messages" => []}
    updated = put_in(canonical, ["messages"], (canonical["messages"] || []) ++ [user_msg(user_text)])

    # Append user snapshot
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

    # Call provider
    provider = session.agent.saved_authentication.provider |> to_string() |> String.to_existing_atom()
    model = default_model(provider)

    {:ok, provider_msgs} = Translator.to_provider(updated, provider)
    {:ok, answer_text, req_hdrs, resp_hdrs} = call_provider(provider, session.agent.saved_authentication.name, provider_msgs, model)

    updated2 = put_in(updated, ["messages"], (updated["messages"] ++ [assistant_msg(answer_text)]))

    {:ok, entry} =
      Conversations.create_chat_entry(%{
        session_id: session.id,
        turn_index: Conversations.next_turn_index(session.id),
        actor: "assistant",
        provider: Atom.to_string(provider),
        request_headers: req_hdrs,
        response_headers: resp_hdrs,
        combined_chat: updated2,
        edit_version: 0
      })

    # Update session pointer
    {:ok, _} =
      Conversations.update_session(session, %{
        latest_chat_entry_id: entry.id,
        last_used_at: DateTime.utc_now()
      })

    socket
    |> assign(:message, "")
    |> assign(:history, Conversations.list_chat_entries(session.id))
  end

  defp user_msg(text), do: %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}
  defp assistant_msg(text), do: %{"role" => "assistant", "content" => [%{"type" => "text", "text" => text}]}

  defp default_model(:openai), do: "gpt-4o"
  defp default_model(:anthropic), do: "claude-3-5-sonnet"
  defp default_model(:gemini), do: "gemini-1.5-pro-latest"
  defp default_model(_), do: ""

  # Return {:ok, text, request_headers, response_headers}
  defp call_provider(:openai, session_name, messages, model) do
    with {:ok, stream} <- OpenAI.Streaming.stream_chat(session_name, messages, model: model) do
      text = stream_to_text(:openai, stream)
      {:ok, text, %{"model" => model, "endpoint" => "/v1/responses", "provider" => "openai"}, %{}}
    end
  end

  defp call_provider(:gemini, session_name, messages, model) do
    with {:ok, stream} <- Gemini.Streaming.stream_chat(session_name, messages, model: model) do
      text = stream_to_text(:gemini, stream)
      {:ok, text, %{"model" => model, "endpoint" => ":streamGenerateContent", "provider" => "gemini"}, %{}}
    end
  end

  defp call_provider(:anthropic, session_name, messages, model) do
    with {:ok, stream} <- Anthropic.Streaming.stream_chat(session_name, messages, model: model) do
      text = stream_to_text(:anthropic, stream)
      {:ok, text, %{"model" => model, "endpoint" => "/v1/messages", "provider" => "anthropic"}, %{}}
    end
  end

  defp stream_to_text(provider, stream) do
    TheMaestro.Streaming.parse_stream(stream, provider)
    |> Enum.reduce("", fn msg, acc ->
      case msg do
        %{type: :content, content: text} when is_binary(text) -> acc <> text
        _ -> acc
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Chat: {@session.name || "Session"}
        <:actions>
          <.button navigate={~p"/dashboard"}>Back</.button>
        </:actions>
      </.header>

      <div class="space-y-2">
        <%= for e <- @history do %>
          <div class="p-2 rounded bg-base-200">
            <div class="text-xs opacity-70">turn {@e.turn_index} • {@e.actor}</div>
            <div class="whitespace-pre-wrap text-sm">
              <%= render_text(e.combined_chat) %>
            </div>
          </div>
        <% end %>
      </div>

      <.form for={%{}} phx-submit="send" class="mt-4">
        <textarea name="message" class="textarea textarea-bordered w-full" rows="3" value={@message} phx-change="change"></textarea>
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
            <textarea name="json" class="textarea textarea-bordered w-full font-mono text-xs" rows="10"><%= @latest_json %></textarea>
            <div class="mt-2">
              <button type="submit" class="btn btn-primary btn-sm">Save Snapshot</button>
            </div>
          </.form>
        <% else %>
          <div class="text-xs opacity-70">Editing allows trimming or correcting the current context (full copy). Changes bump edit_version.</div>
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
        role <> ": " <>
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
    <%= @text %>
    """
  end
end

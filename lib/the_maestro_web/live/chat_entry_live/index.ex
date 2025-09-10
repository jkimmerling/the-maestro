defmodule TheMaestroWeb.ChatEntryLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Chat history
        <:actions>
          <.button variant="primary" navigate={~p"/chat_history/new"}>
            <.icon name="hero-plus" /> New Chat entry
          </.button>
        </:actions>
      </.header>

      <.table
        id="chat_history"
        rows={@streams.chat_history}
        row_click={fn {_id, chat_entry} -> JS.navigate(~p"/chat_history/#{chat_entry}") end}
      >
        <:col :let={{_id, chat_entry}} label="Turn index">{chat_entry.turn_index}</:col>
        <:col :let={{_id, chat_entry}} label="Actor">{chat_entry.actor}</:col>
        <:col :let={{_id, chat_entry}} label="Provider">{chat_entry.provider}</:col>
        <:col :let={{_id, chat_entry}} label="Request headers">
          <.json_viewer data={chat_entry.request_headers || %{}} summary="Request headers" />
        </:col>
        <:col :let={{_id, chat_entry}} label="Response headers">
          <.json_viewer data={chat_entry.response_headers || %{}} summary="Response headers" />
        </:col>
        <:col :let={{_id, chat_entry}} label="Combined chat">
          <.json_viewer data={chat_entry.combined_chat || %{}} summary="Combined chat" />
        </:col>
        <:col :let={{_id, chat_entry}} label="Edit version">{chat_entry.edit_version}</:col>
        <:col :let={{_id, chat_entry}} label="Thread">{chat_entry.thread_id}</:col>
        <:col :let={{_id, chat_entry}} label="Parent thread">{chat_entry.parent_thread_id}</:col>
        <:col :let={{_id, chat_entry}} label="Fork from entry">{chat_entry.fork_from_entry_id}</:col>
        <:col :let={{_id, chat_entry}} label="Thread label">{chat_entry.thread_label}</:col>
        <:col :let={{_id, chat_entry}} label="Session">{chat_entry.session_id}</:col>
        <:action :let={{_id, chat_entry}}>
          <div class="sr-only">
            <.link navigate={~p"/chat_history/#{chat_entry}"}>Show</.link>
          </div>
          <.link navigate={~p"/chat_history/#{chat_entry}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, chat_entry}}>
          <.form for={%{}} phx-submit="attach">
            <input type="hidden" name="_id" value={chat_entry.id} />
            <select name="session_id" class="select select-xs">
              <option value="">Attach to session…</option>
              <%= for {label, sid} <- @session_options do %>
                <option value={sid}>{label}</option>
              <% end %>
            </select>
            <button class="btn btn-xs" type="submit">Attach</button>
          </.form>
          <.link
            phx-click={JS.push("delete", value: %{id: chat_entry.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Chat history")
     |> assign(:session_options, session_options())
     |> stream(:chat_history, Conversations.list_chat_history())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    chat_entry = Conversations.get_chat_entry!(id)
    {:ok, _} = Conversations.delete_chat_entry(chat_entry)

    {:noreply, stream_delete(socket, :chat_history, chat_entry)}
  end

  def handle_event("attach", %{"_id" => id, "session_id" => session_id}, socket) do
    entry = Conversations.get_chat_entry!(id)

    case entry.thread_id do
      tid when is_binary(tid) and tid != "" ->
        Conversations.attach_thread_to_session(tid, session_id)

      _ ->
        Conversations.attach_entry_to_session(entry.id, session_id)
    end

    {:noreply,
     socket
     |> put_flash(:info, "Attached to session")
     |> stream_delete(:chat_history, entry)}
  end

  defp session_options do
    TheMaestro.Conversations.list_sessions_with_auth()
    |> Enum.map(fn s ->
      label =
        s.name || (s.saved_authentication && s.saved_authentication.name) ||
          "sess-" <> String.slice(s.id, 0, 8)

      {label, s.id}
    end)
  end
end

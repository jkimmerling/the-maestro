defmodule TheMaestroWeb.ChatEntryLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Chat entry {@chat_entry.id}
        <:subtitle>This is a chat_entry record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/chat_history"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/chat_history/#{@chat_entry}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit chat_entry
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Turn index">{@chat_entry.turn_index}</:item>
        <:item title="Actor">{@chat_entry.actor}</:item>
        <:item title="Provider">{@chat_entry.provider}</:item>
        <:item title="Request headers">
          <.json_viewer data={@chat_entry.request_headers || %{}} summary="Request headers" />
        </:item>
        <:item title="Response headers">
          <.json_viewer data={@chat_entry.response_headers || %{}} summary="Response headers" />
        </:item>
        <:item title="Combined chat">
          <.json_viewer data={@chat_entry.combined_chat || %{}} summary="Combined chat" />
        </:item>
        <:item title="Edit version">{@chat_entry.edit_version}</:item>
        <:item title="Thread">{@chat_entry.thread_id}</:item>
        <:item title="Parent thread">{@chat_entry.parent_thread_id}</:item>
        <:item title="Fork from entry">{@chat_entry.fork_from_entry_id}</:item>
        <:item title="Thread label">{@chat_entry.thread_label}</:item>
        <:item title="Session">{@chat_entry.session_id}</:item>
      </.list>

      <div class="mt-6 p-4 rounded border border-amber-600/40">
        <h3 class="text-sm font-semibold mb-2">Reattach to a Session</h3>
        <p class="text-xs opacity-70 mb-3">
          Attach this {if @chat_entry.thread_id, do: "thread", else: "entry"} to an existing session.
        </p>
        <.form for={%{}} id="attach-form" phx-submit="attach">
          <input type="hidden" name="_id" value={@chat_entry.id} />
          <select name="session_id" class="select select-sm">
            <option value="">Select a session…</option>
            <%= for {label, sid} <- @session_options do %>
              <option value={sid}>{label}</option>
            <% end %>
          </select>
          <button class="btn btn-sm ml-2" type="submit">Attach</button>
        </.form>
        <%= if @chat_entry.thread_id && @chat_entry.session_id do %>
          <button
            class="btn btn-sm ml-2 btn-error"
            phx-click="detach_thread"
            phx-value-tid={@chat_entry.thread_id}
          >
            Detach Thread
          </button>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Chat entry")
     |> assign(:chat_entry, Conversations.get_chat_entry!(id))
     |> assign(:session_options, session_options())}
  end

  @impl true
  def handle_event("attach", %{"_id" => id, "session_id" => sid}, socket) do
    entry = socket.assigns.chat_entry

    case entry.thread_id do
      tid when is_binary(tid) and tid != "" -> Conversations.attach_thread_to_session(tid, sid)
      _ -> Conversations.attach_entry_to_session(id, sid)
    end

    {:noreply,
     socket
     |> put_flash(:info, "Attached to session")
     |> push_navigate(to: ~p"/chat_history/#{entry}")}
  end

  def handle_event("detach_thread", %{"tid" => tid}, socket) do
    _ = TheMaestro.Conversations.detach_thread(tid)
    entry = %{socket.assigns.chat_entry | session_id: nil}

    {:noreply,
     socket
     |> put_flash(:info, "Thread detached from session")
     |> assign(:chat_entry, entry)}
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

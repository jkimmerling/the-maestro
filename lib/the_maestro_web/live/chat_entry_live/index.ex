defmodule TheMaestroWeb.ChatEntryLive.Index do
  use TheMaestroWeb, :live_view

  alias Phoenix.LiveView.JS
  alias TheMaestro.Conversations

  @impl true
  def mount(_params, _session, socket) do
    orphan_entries = Conversations.list_orphan_chat_entries()

    {:ok,
     socket
     |> assign(:page_title, "Chat Histories")
     |> assign(:chat_summaries, Conversations.list_chat_history_summary())
     |> assign(:session_options, session_options())
     |> assign(:has_orphan_entries, orphan_entries != [])
     |> stream(:orphan_entries, orphan_entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      page_title={@page_title}
      main_class="px-6 py-12 sm:px-8 lg:px-12"
      container_class="mx-auto max-w-6xl space-y-10"
    >
      <.header>
        Chat Histories
        <:actions>
          <.button navigate={~p"/dashboard"} class="btn btn-primary btn-soft">
            <.icon name="hero-arrow-uturn-left" class="size-4 mr-1" /> Back to dashboard
          </.button>
        </:actions>
      </.header>

      <section class="terminal-card border border-amber-600/60 bg-black/70 rounded-lg shadow-lg p-6 space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="text-xl font-semibold uppercase tracking-[0.35em] text-amber-200">
              Active Sessions
            </h2>
            <p class="text-sm text-amber-200/70 mt-1">
              Sessions with persisted chat history. Open any row to jump into the conversation stream.
            </p>
          </div>
          <span class="badge badge-lg badge-outline border-amber-500 text-amber-200">
            {@chat_summaries |> length()} active
          </span>
        </div>

        <div :if={@chat_summaries == []} class="text-sm italic text-amber-200/60">
          No sessions have stored chat history yet. Start chatting with an agent and it will show up here automatically.
        </div>

        <div :if={@chat_summaries != []} class="overflow-x-auto">
          <.table
            id="chat-history-sessions"
            rows={@chat_summaries}
            row_id={fn summary -> "chat-session-#{summary.session.id}" end}
          >
            <:col :let={summary} label="Session">
              <div class="flex flex-col">
                <span class="font-semibold text-amber-100">
                  {display_session_name(summary.session)}
                </span>
                <span class="text-xs text-amber-300/70">
                  Provider: {summary.session.saved_authentication &&
                    summary.session.saved_authentication.provider}
                </span>
              </div>
            </:col>
            <:col :let={summary} label="Messages">
              <span class="badge badge-outline border-amber-400 text-amber-200">
                {summary.message_count}
              </span>
            </:col>
            <:col :let={summary} label="Last Activity">
              {format_session_timestamp(summary.latest_entry, summary.session)}
            </:col>
            <:col :let={summary} label="Last Actor">
              {(summary.latest_entry && summary.latest_entry.actor) || "—"}
            </:col>
            <:action :let={summary}>
              <.link
                class="btn btn-xs btn-primary btn-soft"
                navigate={~p"/sessions/#{summary.session}/chat"}
              >
                <.icon name="hero-chat-bubble-bottom-center-text" class="size-3 mr-1" /> View session
              </.link>
            </:action>
          </.table>
        </div>
      </section>

      <section class="terminal-card border border-amber-600/40 bg-black/60 rounded-lg shadow-lg p-6 space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="text-xl font-semibold uppercase tracking-[0.35em] text-amber-200">
              Detached Entries
            </h2>
            <p class="text-sm text-amber-200/70 mt-1">
              Entries below are not attached to a session. Attach them to keep history consistent or delete if they are obsolete.
            </p>
          </div>
          <div class="flex items-center gap-3">
            <span class="badge badge-outline border-amber-400 text-amber-200">
              {if @has_orphan_entries, do: "Needs review", else: "All clear"}
            </span>
            <.button navigate={~p"/chat_history/new"} class="btn btn-xs btn-primary btn-soft">
              <.icon name="hero-plus" class="size-3 mr-1" /> New Chat entry
            </.button>
          </div>
        </div>

        <div :if={!@has_orphan_entries} class="text-sm italic text-amber-200/60">
          No detached chat entries found.
        </div>

        <div :if={@has_orphan_entries} class="overflow-x-auto">
          <.table
            id="chat-history-orphans"
            rows={@streams.orphan_entries}
            row_id={fn {_id, chat_entry} -> "chat_history-#{chat_entry.id}" end}
            row_click={fn {_id, chat_entry} -> JS.navigate(~p"/chat_history/#{chat_entry}") end}
          >
            <:col :let={{_id, chat_entry}} label="Turn">
              {chat_entry.turn_index}
            </:col>
            <:col :let={{_id, chat_entry}} label="Actor">
              {chat_entry.actor}
            </:col>
            <:col :let={{_id, chat_entry}} label="Thread">
              {chat_entry.thread_label || chat_entry.thread_id || "—"}
            </:col>
            <:col :let={{_id, chat_entry}} label="Captured">
              {format_datetime(chat_entry.inserted_at)}
            </:col>
            <:col :let={{_id, chat_entry}} label="Payload">
              <.json_viewer data={chat_entry.combined_chat || %{}} summary="Combined chat" />
            </:col>
            <:action :let={{_stream_id, chat_entry}}>
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
              <.link navigate={~p"/chat_history/#{chat_entry}/edit"} class="link text-xs">
                Edit
              </.link>
              <.link
                phx-click={JS.push("delete", value: %{id: chat_entry.id})}
                data-confirm="Are you sure?"
                class="link link-error text-xs"
              >
                Delete
              </.link>
            </:action>
          </.table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    chat_entry = Conversations.get_chat_entry!(id)
    {:ok, _} = Conversations.delete_chat_entry(chat_entry)

    {:noreply,
     socket
     |> put_flash(:info, "Detached chat entry removed")
     |> refresh_chat_history()}
  end

  def handle_event("attach", %{"_id" => _id, "session_id" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Select a session before attaching")}
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
     |> refresh_chat_history()}
  end

  defp refresh_chat_history(socket) do
    orphan_entries = Conversations.list_orphan_chat_entries()

    socket
    |> assign(:chat_summaries, Conversations.list_chat_history_summary())
    |> assign(:session_options, session_options())
    |> assign(:has_orphan_entries, orphan_entries != [])
    |> stream(:orphan_entries, orphan_entries, reset: true)
  end

  defp session_options do
    Conversations.list_sessions_brief()
  end

  defp display_session_name(session) do
    session.name ||
      (session.saved_authentication && session.saved_authentication.name) ||
      "sess-" <> String.slice(session.id, 0, 8)
  end

  defp format_session_timestamp(nil, session), do: format_datetime(session.inserted_at)
  defp format_session_timestamp(%{inserted_at: dt}, _session), do: format_datetime(dt)

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M") <> " UTC"
  end
end

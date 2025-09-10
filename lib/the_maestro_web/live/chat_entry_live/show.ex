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
        <:item title="Request headers">{"map"}</:item>
        <:item title="Response headers">{"map"}</:item>
        <:item title="Combined chat">{"map"}</:item>
        <:item title="Edit version">{@chat_entry.edit_version}</:item>
        <:item title="Thread">{@chat_entry.thread_id}</:item>
        <:item title="Parent thread">{@chat_entry.parent_thread_id}</:item>
        <:item title="Fork from entry">{@chat_entry.fork_from_entry_id}</:item>
        <:item title="Thread label">{@chat_entry.thread_label}</:item>
        <:item title="Session">{@chat_entry.session_id}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Chat entry")
     |> assign(:chat_entry, Conversations.get_chat_entry!(id))}
  end
end

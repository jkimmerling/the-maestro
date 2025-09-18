defmodule TheMaestroWeb.SuppliedContextItemLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.SuppliedContext

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Supplied context item {@supplied_context_item.id}
        <:subtitle>This is a supplied_context_item record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/supplied_context"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/supplied_context/#{@supplied_context_item}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit supplied_context_item
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Type">{@supplied_context_item.type}</:item>
        <:item title="Name">{@supplied_context_item.name}</:item>
        <:item title="Text">{@supplied_context_item.text}</:item>
        <:item title="Version">{@supplied_context_item.version}</:item>
        <:item title="Provider">{@supplied_context_item.provider}</:item>
        <:item title="Render Format">{@supplied_context_item.render_format}</:item>
        <:item title="Position">{@supplied_context_item.position}</:item>
        <:item title="Default?">{inspect(@supplied_context_item.is_default)}</:item>
        <:item title="Immutable?">{inspect(@supplied_context_item.immutable)}</:item>
        <:item title="Source Ref">{@supplied_context_item.source_ref || "—"}</:item>
        <:item title="Family ID">{@supplied_context_item.family_id}</:item>
        <:item title="Editor">{@supplied_context_item.editor || "—"}</:item>
        <:item title="Change Note">{@supplied_context_item.change_note || "—"}</:item>
        <:item title="Labels">{inspect(@supplied_context_item.labels)}</:item>
        <:item title="Metadata">{inspect(@supplied_context_item.metadata)}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Supplied context item")
     |> assign(:supplied_context_item, SuppliedContext.get_supplied_context_item!(id))}
  end
end

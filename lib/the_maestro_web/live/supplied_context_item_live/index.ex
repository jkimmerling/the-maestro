defmodule TheMaestroWeb.SuppliedContextItemLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.SuppliedContext

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Supplied context items
        <:actions>
          <.button variant="primary" navigate={~p"/supplied_context/new"}>
            <.icon name="hero-plus" /> New Supplied context item
          </.button>
        </:actions>
      </.header>

      <.table
        id="supplied-context-items"
        rows={@streams.supplied_context_items}
        row_click={fn {_id, supplied_context_item} -> JS.navigate(~p"/supplied_context/#{supplied_context_item}") end}
      >
        <:col :let={{_id, supplied_context_item}} label="Type">{supplied_context_item.type}</:col>
        <:col :let={{_id, supplied_context_item}} label="Name">{supplied_context_item.name}</:col>
        <:col :let={{_id, supplied_context_item}} label="Text">{supplied_context_item.text}</:col>
        <:col :let={{_id, supplied_context_item}} label="Version">{supplied_context_item.version}</:col>
        <:col :let={{_id, supplied_context_item}} label="Tags">{inspect(supplied_context_item.tags)}</:col>
        <:col :let={{_id, supplied_context_item}} label="Metadata">{inspect(supplied_context_item.metadata)}</:col>
        <:action :let={{_id, supplied_context_item}}>
          <div class="sr-only">
            <.link navigate={~p"/supplied_context/#{supplied_context_item}"}>Show</.link>
          </div>
          <.link navigate={~p"/supplied_context/#{supplied_context_item}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, supplied_context_item}}>
          <.link
            phx-click={JS.push("delete", value: %{id: supplied_context_item.id}) |> hide("##{id}")}
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
     |> assign(:page_title, "Listing Supplied context items")
     |> stream(:supplied_context_items, SuppliedContext.list_supplied_context_items())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    supplied_context_item = SuppliedContext.get_supplied_context_item!(id)
    {:ok, _} = SuppliedContext.delete_supplied_context_item(supplied_context_item)

    {:noreply, stream_delete(socket, :supplied_context_items, supplied_context_item)}
  end
end

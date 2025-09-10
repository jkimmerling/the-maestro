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
          <.link phx-click="new" class="btn btn-primary">
            <.icon name="hero-plus" /> New Supplied context item
          </.link>
        </:actions>
      </.header>

      <div class="flex items-center gap-4 mb-4">
        <.link patch={~p"/supplied_context?type=persona"} class={tab_class(@filter_type == :persona)}>
          Personas
        </.link>
        <.link
          patch={~p"/supplied_context?type=system_prompt"}
          class={tab_class(@filter_type == :system_prompt)}
        >
          System Prompts
        </.link>
      </div>

      <.table
        id="supplied-context-items"
        rows={@streams.supplied_context_items}
        row_click={
          fn {_id, supplied_context_item} ->
            JS.navigate(~p"/supplied_context/#{supplied_context_item}")
          end
        }
      >
        <:col :let={{_id, supplied_context_item}} label="Type">{supplied_context_item.type}</:col>
        <:col :let={{_id, supplied_context_item}} label="Name">{supplied_context_item.name}</:col>
        <:col :let={{_id, supplied_context_item}} label="Text">{supplied_context_item.text}</:col>
        <:col :let={{_id, supplied_context_item}} label="Version">
          {supplied_context_item.version}
        </:col>
        <:col :let={{_id, supplied_context_item}} label="Tags">
          {inspect(supplied_context_item.tags)}
        </:col>
        <:col :let={{_id, supplied_context_item}} label="Metadata">
          {inspect(supplied_context_item.metadata)}
        </:col>
        <:action :let={{_id, supplied_context_item}}>
          <div class="sr-only">
            <.link navigate={~p"/supplied_context/#{supplied_context_item}"}>Show</.link>
          </div>
          <.link phx-click="edit" phx-value-id={supplied_context_item.id}>Edit</.link>
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
     |> assign(:filter_type, :persona)
     |> stream(:supplied_context_items, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    type = parse_type(params["type"])
    items = SuppliedContext.list_items(type)

    {:noreply,
     socket
     |> assign(:filter_type, type)
     |> stream(:supplied_context_items, items, reset: true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    supplied_context_item = SuppliedContext.get_supplied_context_item!(id)
    {:ok, _} = SuppliedContext.delete_supplied_context_item(supplied_context_item)

    {:noreply, stream_delete(socket, :supplied_context_items, supplied_context_item)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/supplied_context/new")}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/supplied_context/#{id}/edit")}
  end

  defp parse_type("persona"), do: :persona
  defp parse_type("system_prompt"), do: :system_prompt
  defp parse_type(_), do: :persona

  defp tab_class(true), do: "px-3 py-2 rounded border border-blue-500 text-blue-600"

  defp tab_class(false),
    do: "px-3 py-2 rounded border border-transparent text-slate-600 hover:text-slate-900"
end

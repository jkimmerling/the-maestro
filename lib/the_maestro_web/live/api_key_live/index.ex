defmodule TheMaestroWeb.ApiKeyLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.ApiKeys

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        API Keys
        <:actions>
          <.button variant="primary" navigate={~p"/api_keys/new"}>
            <.icon name="hero-plus" /> New API Key
          </.button>
        </:actions>
      </.header>

      <.table
        id="api_keys"
        rows={@streams.api_keys}
        row_click={fn {_id, api_key} -> JS.navigate(~p"/api_keys/#{api_key}") end}
      >
        <:col :let={{_id, api_key}} label="Label">{api_key.label}</:col>
        <:col :let={{_id, api_key}} label="Last used">{api_key.last_used_at}</:col>
        <:col :let={{_id, api_key}} label="Revoked?">{not is_nil(api_key.revoked_at)}</:col>
        <:action :let={{_id, api_key}}>
          <div class="sr-only">
            <.link navigate={~p"/api_keys/#{api_key}"}>Show</.link>
          </div>
          <.link navigate={~p"/api_keys/#{api_key}/edit"}>Rotate</.link>
        </:action>
        <:action :let={{id, api_key}}>
          <.link phx-click={JS.push("revoke", value: %{id: api_key.id}) |> hide("##{id}")}>
            Revoke
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
     |> assign(:page_title, "API Keys")
     |> stream(:api_keys, ApiKeys.list_keys())}
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    api_key = ApiKeys.get_key!(id)
    updated = ApiKeys.revoke!(api_key)
    {:noreply, stream_insert(socket, :api_keys, updated)}
  end
end

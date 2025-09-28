defmodule TheMaestroWeb.ApiKeyLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.ApiKeys

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        API Key {@api_key.label}
        <:subtitle>Rotate or revoke from here.</:subtitle>
        <:actions>
          <.button navigate={~p"/api_keys"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/api_keys/#{@api_key}/edit?return_to=show"}>
            <.icon name="hero-key" /> Rotate
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Label">{@api_key.label}</:item>
        <:item title="Last used">{@api_key.last_used_at}</:item>
        <:item title="Revoked?">{not is_nil(@api_key.revoked_at)}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API Key")
     |> assign(:api_key, ApiKeys.get_key!(id))}
  end
end

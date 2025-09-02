defmodule TheMaestroWeb.AgentLive.Show do
  use TheMaestroWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Agent {@agent.id}
        <:subtitle>This is a agent record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/agents"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/agents/#{@agent}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit agent
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@agent.name}</:item>
        <:item title="Auth">
          <%= if @agent.saved_authentication do %>
            <%= @agent.saved_authentication.name %> (<%= @agent.saved_authentication.provider %>/<%= @agent.saved_authentication.auth_type %>)
          <% else %>
            —
          <% end %>
        </:item>
        <:item title="Tools"><pre class="text-xs">{inspect(@agent.tools || %{}, pretty: true, limit: :infinity)}</pre></:item>
        <:item title="MCPs"><pre class="text-xs">{inspect(@agent.mcps || %{}, pretty: true, limit: :infinity)}</pre></:item>
        <:item title="Memory"><pre class="text-xs">{inspect(@agent.memory || %{}, pretty: true, limit: :infinity)}</pre></:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Agent")
     |> assign(:agent, TheMaestro.Repo.get!(TheMaestro.Agents.Agent, id) |> TheMaestro.Repo.preload([:saved_authentication, :base_system_prompt, :persona]))}
  end
end

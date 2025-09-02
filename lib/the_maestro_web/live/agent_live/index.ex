defmodule TheMaestroWeb.AgentLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Agents
        <:actions>
          <.button variant="primary" navigate={~p"/agents/new"}>
            <.icon name="hero-plus" /> New Agent
          </.button>
        </:actions>
      </.header>

      <.table
        id="agents"
        rows={@streams.agents}
        row_click={fn {_id, agent} -> JS.navigate(~p"/agents/#{agent}") end}
      >
        <:col :let={{_id, agent}} label="Name">{agent.name}</:col>
        <:col :let={{_id, agent}} label="Tools">{agent.tools}</:col>
        <:col :let={{_id, agent}} label="Mcps">{agent.mcps}</:col>
        <:col :let={{_id, agent}} label="Memory">{agent.memory}</:col>
        <:action :let={{_id, agent}}>
          <div class="sr-only">
            <.link navigate={~p"/agents/#{agent}"}>Show</.link>
          </div>
          <.link navigate={~p"/agents/#{agent}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, agent}}>
          <.link
            phx-click={JS.push("delete", value: %{id: agent.id}) |> hide("##{id}")}
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
     |> assign(:page_title, "Listing Agents")
     |> stream(:agents, Agents.list_agents())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    agent = Agents.get_agent!(id)
    {:ok, _} = Agents.delete_agent(agent)

    {:noreply, stream_delete(socket, :agents, agent)}
  end
end

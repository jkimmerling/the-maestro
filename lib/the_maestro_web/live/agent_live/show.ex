defmodule TheMaestroWeb.AgentLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents

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
        <:item title="Tools">{@agent.tools}</:item>
        <:item title="Mcps">{@agent.mcps}</:item>
        <:item title="Memory">{@agent.memory}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Agent")
     |> assign(:agent, Agents.get_agent!(id))}
  end
end

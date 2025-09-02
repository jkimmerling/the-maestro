defmodule TheMaestroWeb.PersonaLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Personas

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Persona {@persona.id}
        <:subtitle>This is a persona record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/personas"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/personas/#{@persona}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit persona
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@persona.name}</:item>
        <:item title="Prompt text">{@persona.prompt_text}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Persona")
     |> assign(:persona, Personas.get_persona!(id))}
  end
end

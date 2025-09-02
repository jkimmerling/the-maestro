defmodule TheMaestroWeb.PersonaLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Personas

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Personas
        <:actions>
          <.button variant="primary" navigate={~p"/personas/new"}>
            <.icon name="hero-plus" /> New Persona
          </.button>
        </:actions>
      </.header>

      <.table
        id="personas"
        rows={@streams.personas}
        row_click={fn {_id, persona} -> JS.navigate(~p"/personas/#{persona}") end}
      >
        <:col :let={{_id, persona}} label="Name">{persona.name}</:col>
        <:col :let={{_id, persona}} label="Prompt text">{persona.prompt_text}</:col>
        <:action :let={{_id, persona}}>
          <div class="sr-only">
            <.link navigate={~p"/personas/#{persona}"}>Show</.link>
          </div>
          <.link navigate={~p"/personas/#{persona}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, persona}}>
          <.link
            phx-click={JS.push("delete", value: %{id: persona.id}) |> hide("##{id}")}
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
     |> assign(:page_title, "Listing Personas")
     |> stream(:personas, Personas.list_personas())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    persona = Personas.get_persona!(id)
    {:ok, _} = Personas.delete_persona(persona)

    {:noreply, stream_delete(socket, :personas, persona)}
  end
end

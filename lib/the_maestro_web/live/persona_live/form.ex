defmodule TheMaestroWeb.PersonaLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Personas
  alias TheMaestro.Personas.Persona

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage persona records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="persona-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:prompt_text]} type="textarea" label="Prompt text" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Persona</.button>
          <.button navigate={return_path(@return_to, @persona)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    persona = Personas.get_persona!(id)

    socket
    |> assign(:page_title, "Edit Persona")
    |> assign(:persona, persona)
    |> assign(:form, to_form(Personas.change_persona(persona)))
  end

  defp apply_action(socket, :new, _params) do
    persona = %Persona{}

    socket
    |> assign(:page_title, "New Persona")
    |> assign(:persona, persona)
    |> assign(:form, to_form(Personas.change_persona(persona)))
  end

  @impl true
  def handle_event("validate", %{"persona" => persona_params}, socket) do
    changeset = Personas.change_persona(socket.assigns.persona, persona_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"persona" => persona_params}, socket) do
    save_persona(socket, socket.assigns.live_action, persona_params)
  end

  defp save_persona(socket, :edit, persona_params) do
    case Personas.update_persona(socket.assigns.persona, persona_params) do
      {:ok, persona} ->
        {:noreply,
         socket
         |> put_flash(:info, "Persona updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, persona))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_persona(socket, :new, persona_params) do
    case Personas.create_persona(persona_params) do
      {:ok, persona} ->
        {:noreply,
         socket
         |> put_flash(:info, "Persona created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, persona))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _persona), do: ~p"/personas"
  defp return_path("show", persona), do: ~p"/personas/#{persona}"
end

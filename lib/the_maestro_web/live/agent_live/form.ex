defmodule TheMaestroWeb.AgentLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents
  alias TheMaestro.Agents.Agent
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.{Personas, Prompts}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage agent records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="agent-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input
          field={@form[:auth_id]}
          type="select"
          label="Saved Auth"
          options={@auth_options}
          prompt="Select an auth"
        />
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@form[:base_system_prompt_id]}
            type="select"
            label="Base System Prompt (optional)"
            options={@prompt_options}
            prompt="None"
          />
          <.input
            field={@form[:persona_id]}
            type="select"
            label="Persona (optional)"
            options={@persona_options}
            prompt="None"
          />
        </div>
        <.input field={@form[:tools_json]} type="textarea" rows="5" label="Tools (JSON object)" />
        <.input field={@form[:mcps_json]} type="textarea" rows="5" label="MCPs (JSON object)" />
        <.input field={@form[:memory_json]} type="textarea" rows="5" label="Memory (JSON object)" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Agent</.button>
          <.button navigate={return_path(@return_to, @agent)}>Cancel</.button>
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
     |> load_form_options()
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    agent = Agents.get_agent!(id)

    socket
    |> assign(:page_title, "Edit Agent")
    |> assign(:agent, agent)
    |> assign(:form, to_form(Agents.change_agent(agent)))
  end

  defp apply_action(socket, :new, _params) do
    agent = %Agent{}

    socket
    |> assign(:page_title, "New Agent")
    |> assign(:agent, agent)
    |> assign(:form, to_form(Agents.change_agent(agent)))
  end

  defp load_form_options(socket) do
    auths =
      SavedAuthentication.list_all()
      |> Enum.map(fn sa ->
        label = "#{sa.name} — #{sa.provider}/#{sa.auth_type}"
        {label, sa.id}
      end)

    prompts =
      try do
        Prompts.list_base_system_prompts() |> Enum.map(&{&1.name, &1.id})
      rescue
        _ -> []
      end

    personas =
      try do
        Personas.list_personas() |> Enum.map(&{&1.name, &1.id})
      rescue
        _ -> []
      end

    socket
    |> assign(:auth_options, auths)
    |> assign(:prompt_options, prompts)
    |> assign(:persona_options, personas)
  end

  @impl true
  def handle_event("validate", %{"agent" => agent_params}, socket) do
    changeset = Agents.change_agent(socket.assigns.agent, agent_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"agent" => agent_params}, socket) do
    save_agent(socket, socket.assigns.live_action, agent_params)
  end

  defp save_agent(socket, :edit, agent_params) do
    case Agents.update_agent(socket.assigns.agent, agent_params) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, agent))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_agent(socket, :new, agent_params) do
    case Agents.create_agent(agent_params) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, agent))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _agent), do: ~p"/agents"
  defp return_path("show", agent), do: ~p"/agents/#{agent}"
end

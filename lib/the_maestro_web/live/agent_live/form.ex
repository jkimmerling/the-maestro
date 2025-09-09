defmodule TheMaestroWeb.AgentLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents
  alias TheMaestro.Agents.Agent
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.{Personas, Prompts, Provider}
  alias TheMaestro.SavedAuthentication

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; {@page_title} &lt;&lt;&lt;
            </h1>
            <div class="space-x-2">
              <%= if @live_action == :edit do %>
                <button
                  phx-click="delete"
                  data-confirm="Delete this agent?"
                  class="px-3 py-1 rounded btn-red"
                >
                  DELETE
                </button>
              <% end %>
              <.link
                navigate={return_path(@return_to, @agent)}
                class="px-3 py-1 rounded btn-amber"
                data-hotkey-seq="g i"
                data-hotkey-label="Back"
              >
                BACK
              </.link>
            </div>
          </div>

          <.form for={@form} id="agent-form" phx-change="validate" phx-submit="save">
            <div class="terminal-card terminal-border-amber p-6 space-y-4">
              <.input field={@form[:name]} type="text" label="Name" />
              <.input
                field={@form[:auth_id]}
                type="select"
                label="Saved Auth"
                options={@auth_options}
                prompt="Select an auth"
              />
              <.input
                field={@form[:model_id]}
                type="select"
                label="Model"
                options={@model_options}
                prompt="Auto-select from provider"
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
              <.input
                field={@form[:memory_json]}
                type="textarea"
                rows="5"
                label="Memory (JSON object)"
              />
              <footer class="space-x-2">
                <button type="submit" class="px-4 py-2 rounded btn-green" phx-disable-with="Saving...">
                  Save Agent
                </button>
                <.link navigate={return_path(@return_to, @agent)} class="px-4 py-2 rounded btn-amber">
                  Cancel
                </.link>
              </footer>
            </div>
          </.form>
          <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
        </div>
      </div>
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

    # Preload model options based on current agent auth_id (if any)
    model_opts = model_options_for_agent(socket.assigns[:agent])

    socket
    |> assign(:auth_options, auths)
    |> assign(:prompt_options, prompts)
    |> assign(:persona_options, personas)
    |> assign(:model_options, model_opts)
  end

  @impl true
  def handle_event("validate", %{"agent" => agent_params}, socket) do
    changeset = Agents.change_agent(socket.assigns.agent, agent_params)

    # If auth_id changed in the form input, refresh model options
    model_opts =
      case Map.get(agent_params, "auth_id") do
        nil -> socket.assigns.model_options || []
        "" -> []
        id when is_binary(id) -> model_options_for_auth_id(id)
      end

    {:noreply,
     socket
     |> assign(:model_options, model_opts)
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"agent" => agent_params}, socket) do
    save_agent(socket, socket.assigns.live_action, agent_params)
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Agents.delete_agent(socket.assigns.agent)

    {:noreply,
     socket
     |> put_flash(:info, "Agent deleted")
     |> push_navigate(to: return_path("index", nil))}
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

  defp model_options_for_agent(nil), do: []
  defp model_options_for_agent(%Agent{auth_id: nil}), do: []

  defp model_options_for_agent(%Agent{auth_id: auth_id}) when is_integer(auth_id),
    do: model_options_for_auth_id(Integer.to_string(auth_id))

  defp model_options_for_auth_id(auth_id_str) when is_binary(auth_id_str) do
    with {auth_id, _} <- Integer.parse(auth_id_str),
         %SavedAuthentication{} = sa <- SavedAuthentication.get!(auth_id),
         {:ok, models} <- Provider.list_models(sa.provider, sa.auth_type, sa.name) do
      Enum.map(models, fn m -> {m.name || m.id, m.id} end)
    else
      _ -> []
    end
  end
end

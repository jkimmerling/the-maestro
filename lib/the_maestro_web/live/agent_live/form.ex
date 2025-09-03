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
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage agent records in your database.</:subtitle>
        <:actions :if={@live_action == :edit}>
          <.button phx-click="delete" data-confirm="Delete this agent?" variant="danger">
            Delete
          </.button>
        </:actions>
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

        <div class="divider my-4">Tools</div>

        <div class="mb-3 text-sm opacity-80">
          Select which tools this agent can use during a session. Use the Advanced toggle to edit JSON directly if needed.
        </div>

        <div class="grid md:grid-cols-2 gap-3">
          <div>
            <div class="font-semibold mb-2">Available Tools</div>
            <div class="space-y-1 max-h-60 overflow-auto pr-1">
              <%= for tool <- @available_tools do %>
                <label class="flex items-start gap-2">
                  <input
                    type="checkbox"
                    name="agent[tools][enabled_tools][]"
                    value={tool.name}
                    class="checkbox checkbox-sm mt-0.5"
                    checked={tool.name in (@enabled_tools || [])}
                  />
                  <span>
                    <div class="font-medium">{tool.name}</div>
                    <div class="text-xs opacity-70">{tool.description}</div>
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <div>
            <div class="font-semibold mb-2">Tool & Safety Settings</div>
            <.input
              name="agent[tools][trust]"
              type="checkbox"
              label="Allow tool writes without extra confirmation (trust)"
              checked={@tools_map["trust"] || false}
            />
            <.input
              name="agent[tools][allow_chaining]"
              type="checkbox"
              label="Allow shell command chaining (&&, ||, ;)"
              checked={@tools_map["allow_chaining"] || false}
            />
            <.input
              name="agent[tools][sudo_allowed]"
              type="checkbox"
              label="Allow sudo in shell (dangerous)"
              checked={@tools_map["sudo_allowed"] || false}
            />
            <.input
              name="agent[tools][token_cap]"
              type="number"
              label="Token cap for tool outputs"
              value={@tools_map["token_cap"] || 100_000}
              min="1000"
              step="1000"
            />
            <.input
              name="agent[tools][denylist]"
              type="textarea"
              label="Additional denylist patterns (one per line)"
              rows="3"
              value={Enum.join(List.wrap(@tools_map["denylist"] || []), "\n")}
            />
            <div class="mt-2">
              <label class="label mb-1">Preferred Search Backend</label>
              <select name="agent[tools][search_backends][]" class="select w-full">
                <%= for opt <- ["tavily", "duckduckgo"] do %>
                  <option value={opt} selected={List.first(@search_backends) == opt}>{opt}</option>
                <% end %>
              </select>
              <input
                type="hidden"
                name="agent[tools][search_backends][]"
                value={
                  (@search_backends -- [List.first(@search_backends || [])]) |> List.first() ||
                    "duckduckgo"
                }
              />
              <div class="text-xs opacity-70 mt-1">
                Order is respected; remaining backends fill after the preferred one.
              </div>
            </div>
          </div>
        </div>

        <div class="mt-4">
          <label class="label cursor-pointer">
            <span class="label-text">Advanced: Edit raw JSON maps</span>
            <input
              type="checkbox"
              class="toggle"
              phx-click="toggle_advanced"
              checked={@advanced_json?}
            />
          </label>
        </div>

        <div :if={@advanced_json?} class="mt-2">
          <.input field={@form[:tools_json]} type="textarea" rows="5" label="Tools (JSON object)" />
          <.input field={@form[:mcps_json]} type="textarea" rows="5" label="MCPs (JSON object)" />
          <.input field={@form[:memory_json]} type="textarea" rows="5" label="Memory (JSON object)" />
        </div>
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
     |> assign(:advanced_json?, false)
     |> load_form_options()
     |> apply_action(socket.assigns.live_action, params)
     |> load_tools_ui_state()}
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
     |> assign(:form, to_form(changeset, action: :validate))
     |> load_tools_ui_state()}
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

  @impl true
  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, :advanced_json?, !socket.assigns.advanced_json?)}
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

  # ===== Tools UI helpers =====
  defp load_tools_ui_state(socket) do
    changeset = socket.assigns.form.source

    tools_map =
      (changeset.changes[:tools] || changeset.data.tools || %{})
      |> normalize_tools_map()

    enabled_tools = Map.get(tools_map, "enabled_tools", [])
    backends = Map.get(tools_map, "search_backends", ["tavily", "duckduckgo"])

    assign(socket,
      available_tools: TheMaestro.Tools.Registry.list_tools(%{}),
      tools_map: tools_map,
      enabled_tools: enabled_tools,
      search_backends: backends
    )
  end

  defp normalize_tools_map(%{} = m) do
    # Convert textarea denylist (string) into list when validating
    case m do
      %{"denylist" => s} when is_binary(s) ->
        Map.put(m, "denylist", split_lines(s))

      _ ->
        m
    end
  end

  defp normalize_tools_map(_), do: %{}

  defp split_lines(str) when is_binary(str) do
    str
    |> String.split(["\r\n", "\n", "\r"], trim: true)
    |> Enum.reject(&(&1 == ""))
  end
end

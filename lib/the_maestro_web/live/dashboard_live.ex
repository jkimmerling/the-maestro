defmodule TheMaestroWeb.DashboardLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents
  alias TheMaestro.Agents.Agent
  alias TheMaestro.Conversations
  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    {:ok,
     socket
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:agents, Agents.list_agents_with_auth())
     |> assign(:sessions, Conversations.list_sessions_with_agents())
     |> assign(:show_agent_modal, false)
     |> assign(:show_session_modal, false)
     |> assign(:agent_changeset, Agents.change_agent(%Agent{}))
     |> assign(:agent_form, to_form(Agents.change_agent(%Agent{})))
     |> assign(:auth_options, build_auth_options())
     |> assign(:prompt_options, build_prompt_options())
     |> assign(:persona_options, build_persona_options())
     |> assign(:agent_options, build_agent_options())
     |> assign(:session_form, to_form(Conversations.change_session(%Conversations.Session{})))
     |> assign(:show_session_dir_picker, false)
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:agents, Agents.list_agents_with_auth())
     |> assign(:sessions, Conversations.list_sessions_with_agents())
     |> assign(:auth_options, build_auth_options())
     |> assign(:agent_options, build_agent_options())
     |> assign(:prompt_options, build_prompt_options())
     |> assign(:persona_options, build_persona_options())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {int, _} ->
        sa = SavedAuthentication.get!(int)
        # Allow deletion; DB FK now nilifies agent.auth_id
        _ = Provider.delete_session(sa.provider, sa.auth_type, sa.name)

        {:noreply,
         socket
         |> put_flash(:info, "Auth deleted; linked agents detached.")
         |> assign(:auths, SavedAuthentication.list_all())
         |> assign(:auth_options, build_auth_options())
         |> assign(:agents, Agents.list_agents_with_auth())}

      :error ->
        {:noreply, socket}
    end
  end

  # Delete a chat session from the dashboard Sessions grid
  def handle_event("delete_session", %{"id" => id}, socket) do
    # Session IDs are UUID strings; fetch and delete
    session = Conversations.get_session!(id)
    {:ok, _} = Conversations.delete_session(session)

    {:noreply,
     socket
     |> put_flash(:info, "Session deleted")
     |> assign(:sessions, Conversations.list_sessions_with_agents())}
  end

  def handle_event("open_agent_modal", _params, socket) do
    cs = Agents.change_agent(%Agent{})

    {:noreply,
     socket
     |> assign(:agent_changeset, cs)
     |> assign(:agent_form, to_form(cs))
     |> assign(:model_options, [])
     |> assign(:auth_options, build_auth_options())
     |> assign(:show_agent_modal, true)}
  end

  def handle_event("agent_validate", %{"agent" => params}, socket) do
    cs = Agents.change_agent(%Agent{}, params) |> Map.put(:action, :validate)
    model_opts = build_model_options(params)

    {:noreply,
     socket
     |> assign(:model_options, model_opts)
     |> assign(agent_changeset: cs, agent_form: to_form(cs, action: :validate))}
  end

  def handle_event("agent_save", %{"agent" => params}, socket) do
    case Agents.create_agent(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent created")
         |> assign(:show_agent_modal, false)
         |> assign(:agents, Agents.list_agents_with_auth())
         |> assign(:model_options, [])
         |> assign(:agent_options, build_agent_options())}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, agent_changeset: cs, agent_form: to_form(cs))}
    end
  end

  def handle_event("open_session_modal", _params, socket) do
    cs = Conversations.change_session(%Conversations.Session{})

    {:noreply,
     socket
     |> assign(:agent_options, build_agent_options())
     |> assign(:session_form, to_form(cs))
     |> assign(:show_session_modal, true)}
  end

  def handle_event("session_validate", %{"session" => params}, socket) do
    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, session_form: to_form(cs, action: :validate))}
  end

  def handle_event("open_session_dir_picker", _params, socket) do
    {:noreply, assign(socket, :show_session_dir_picker, true)}
  end

  def handle_event("session_use_root_dir", _params, socket) do
    wd = File.cwd!() |> Path.expand()

    cs =
      Conversations.change_session(%Conversations.Session{}, %{"working_dir" => wd})
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, session_form: to_form(cs, action: :validate))}
  end

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  def handle_event("session_save", %{"session" => params}, socket) do
    case Conversations.create_session(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session created")
         |> assign(:show_session_modal, false)
         |> assign(:show_session_dir_picker, false)
         |> assign(:sessions, Conversations.list_sessions_with_agents())}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, session_form: to_form(cs))}
    end
  end

  # moved earlier to keep handle_event clauses grouped

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  # moved earlier to keep handle_event clauses grouped

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :selected, path, :new_session}, socket) do
    cs =
      Conversations.change_session(%Conversations.Session{}, %{"working_dir" => path})
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:session_form, to_form(cs, action: :validate))
     |> assign(:show_session_dir_picker, false)}
  end

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :cancel, :new_session}, socket) do
    {:noreply, assign(socket, :show_session_dir_picker, false)}
  end

  @impl true
  def handle_info(%{topic: "oauth:events", event: "completed", payload: payload}, socket) do
    # Refresh list when a new auth is persisted by the callback server
    {:noreply,
     socket
     |> put_flash(:info, "OAuth completed for #{payload["provider"]}: #{payload["session_name"]}")
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:auth_options, build_auth_options())
     |> assign(:agents, Agents.list_agents_with_auth())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # duplicate clauses removed; see earlier grouped handle_event/3 definitions

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")

  defp format_dt(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S") <> " UTC"

  defp provider_label(p) when is_atom(p), do: Atom.to_string(p)
  defp provider_label(p) when is_binary(p), do: p

  defp map_count(nil), do: 0
  defp map_count(%{} = m), do: map_size(m)
  defp map_count(_), do: 0

  defp build_auth_options do
    SavedAuthentication.list_all()
    |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
  end

  defp build_prompt_options do
    if Code.ensure_loaded?(TheMaestro.Prompts) do
      TheMaestro.Prompts.list_base_system_prompts() |> Enum.map(&{&1.name, &1.id})
    else
      []
    end
  end

  defp build_persona_options do
    if Code.ensure_loaded?(TheMaestro.Personas) do
      TheMaestro.Personas.list_personas() |> Enum.map(&{&1.name, &1.id})
    else
      []
    end
  end

  defp build_agent_options do
    Agents.list_agents_with_auth() |> Enum.map(&{&1.name, &1.id})
  end

  defp build_model_options(%{"auth_id" => auth_id}) when is_binary(auth_id) and auth_id != "" do
    with {id, _} <- Integer.parse(auth_id),
         %SavedAuthentication{} = sa <- SavedAuthentication.get!(id),
         {:ok, models} <- Provider.list_models(sa.provider, sa.auth_type, sa.name) do
      Enum.map(models, fn m -> {m.name || m.id, m.id} end)
    else
      _ -> []
    end
  end

  defp build_model_options(_), do: []

  defp session_label(s) do
    cond do
      is_binary(s.name) and String.trim(s.name) != "" -> s.name
      s.agent && s.agent.name -> s.agent.name <> " · sess-" <> String.slice(s.id, 0, 8)
      true -> "sess-" <> String.slice(s.id, 0, 8)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-xl font-semibold">Dashboard</h1>
        <.link navigate={~p"/auths/new"} class="btn btn-primary">New Auth</.link>
      </div>

      <.auths_table auths={@auths} />

      <.agents_grid agents={@agents} />

      <.sessions_grid sessions={@sessions} />

      <.modal :if={@show_session_modal} id="session-modal">
        <h3 class="text-lg font-semibold mb-2">Create Session</h3>
        <.form
          for={@session_form}
          id="session-modal-form"
          phx-submit="session_save"
          phx-change="session_validate"
        >
          <.input field={@session_form[:name]} type="text" label="Name (optional)" />
          <.input
            field={@session_form[:agent_id]}
            type="select"
            label="Agent"
            options={@agent_options}
            prompt="Select an agent"
          />
          <div class="mt-2 grid gap-2">
            <.input
              field={@session_form[:working_dir]}
              type="text"
              label="Working directory"
              placeholder={Path.expand(".")}
            />
            <div>
              <button type="button" class="btn btn-xs" phx-click="session_use_root_dir">
                Use project root
              </button>
              <button type="button" class="btn btn-xs ml-2" phx-click="open_session_dir_picker">
                Browse…
              </button>
            </div>
          </div>
          <div class="mt-3 space-x-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" class="btn" phx-click={JS.dispatch("phx:close-modal")}>
              Cancel
            </button>
          </div>
        </.form>
        <.modal :if={@show_session_dir_picker} id="dir-picker-session-new">
          <.live_component
            module={TheMaestroWeb.DirectoryPicker}
            id="dirpick-session-new"
            start_path={@session_form[:working_dir].value || Path.expand(".")}
            context={:new_session}
          />
        </.modal>
      </.modal>

      <.modal :if={@show_agent_modal} id="agent-modal">
        <h3 class="text-lg font-semibold mb-2">Create Agent</h3>
        <.form
          for={@agent_form}
          id="agent-modal-form"
          phx-change="agent_validate"
          phx-submit="agent_save"
        >
          <.input field={@agent_form[:name]} type="text" label="Name" />
          <.input
            field={@agent_form[:auth_id]}
            type="select"
            label="Saved Auth"
            options={@auth_options}
            prompt="Select an auth"
          />
          <.input
            field={@agent_form[:model_id]}
            type="select"
            label="Model"
            options={@model_options}
            prompt="Auto-select from provider"
          />
          <.input
            field={@agent_form[:base_system_prompt_id]}
            type="select"
            label="Base System Prompt"
            options={@prompt_options}
            prompt="(optional)"
          />
          <.input
            field={@agent_form[:persona_id]}
            type="select"
            label="Persona"
            options={@persona_options}
            prompt="(optional)"
          />
          <div class="mt-3 space-x-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" class="btn" phx-click={JS.dispatch("phx:close-modal")}>
              Cancel
            </button>
          </div>
        </.form>
        <.modal :if={@show_session_dir_picker} id="dir-picker-session-new">
          <.live_component
            module={TheMaestroWeb.DirectoryPicker}
            id="dirpick-session-new"
            start_path={@session_form[:working_dir].value || Path.expand(".")}
            context={:new_session}
          />
        </.modal>
      </.modal>
    </Layouts.app>
    """
  end

  # ===== Extracted components to reduce nesting =====
  attr :auths, :list, required: true

  defp auths_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th>Name</th>
            <th>Provider</th>
            <th>Auth Type</th>
            <th>Expiration</th>
            <th>Created</th>
            <th class="w-40">Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for sa <- @auths do %>
            <tr id={"auth-#{sa.id}"}>
              <td>{sa.name}</td>
              <td>{provider_label(sa.provider)}</td>
              <td class="uppercase">{sa.auth_type}</td>
              <td>{format_dt(sa.expires_at)}</td>
              <td>{format_dt(sa.inserted_at)}</td>
              <td class="space-x-2">
                <.link navigate={~p"/auths/#{sa.id}"} class="btn btn-xs">View</.link>
                <.link navigate={~p"/auths/#{sa.id}/edit"} class="btn btn-xs">Edit</.link>
                <button
                  phx-click="delete"
                  phx-value-id={sa.id}
                  data-confirm="Delete this auth?"
                  class="btn btn-xs btn-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :agents, :list, required: true

  defp agents_grid(assigns) do
    ~H"""
    <div class="mt-10">
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-lg font-semibold">Agents</h2>
        <button class="btn" phx-click="open_agent_modal">New Agent</button>
      </div>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <%= for a <- @agents do %>
          <div class="card bg-base-200 p-4" id={"agent-" <> to_string(a.id)}>
            <div class="font-semibold text-base">{a.name}</div>
            <div class="text-sm opacity-80">
              Auth: {a.saved_authentication && a.saved_authentication.name} ({a.saved_authentication &&
                a.saved_authentication.provider}/{a.saved_authentication &&
                a.saved_authentication.auth_type})
            </div>
            <div class="text-xs opacity-70">
              Tools: {map_count(a.tools)} • MCPs: {map_count(a.mcps)}
            </div>
            <div class="mt-2 space-x-2">
              <.link class="btn btn-xs" navigate={"/agents/" <> to_string(a.id)}>View</.link>
              <.link class="btn btn-xs" navigate={"/agents/" <> to_string(a.id) <> "/edit"}>
                Edit
              </.link>
              <button
                class="btn btn-xs btn-error"
                phx-click="delete_agent"
                phx-value-id={a.id}
                data-confirm="Delete this agent?"
              >
                Delete
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :sessions, :list, required: true

  defp sessions_grid(assigns) do
    ~H"""
    <div class="mt-10">
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-lg font-semibold">Sessions</h2>
        <button class="btn" phx-click="open_session_modal">New Session</button>
      </div>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <%= for s <- @sessions do %>
          <div class="card bg-base-200 p-4" id={"session-" <> to_string(s.id)}>
            <div class="font-semibold text-base">{session_label(s)}</div>
            <div class="text-sm opacity-80">Agent: {s.agent && s.agent.name}</div>
            <div class="text-xs opacity-70">Last used: {format_dt(s.last_used_at)}</div>
            <div class="mt-2 space-x-2">
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/chat"}>Go into chat</.link>
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/edit"}>
                Edit
              </.link>
              <button class="btn btn-xs btn-error" phx-click="delete_session" phx-value-id={s.id}>
                Delete
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end

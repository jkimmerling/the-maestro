defmodule TheMaestroWeb.DashboardLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents
  alias TheMaestro.Agents.Agent
  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    {:ok,
     socket
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:agents, Agents.list_agents_with_auth())
     |> assign(:show_agent_modal, false)
     |> assign(:agent_changeset, Agents.change_agent(%Agent{}))
     |> assign(:agent_form, to_form(Agents.change_agent(%Agent{})))
     |> assign(:auth_options, build_auth_options())
     |> assign(:prompt_options, build_prompt_options())
     |> assign(:persona_options, build_persona_options())
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:agents, Agents.list_agents_with_auth())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {int, _} ->
        sa = SavedAuthentication.get!(int)
        # Block deletion if agents reference this auth
        count = TheMaestro.Repo.aggregate(from(a in Agent, where: a.auth_id == ^sa.id), :count)
        if count > 0 do
          {:noreply, put_flash(socket, :error, "Cannot delete auth: #{count} agent(s) reference it")}
        else
          _ = Provider.delete_session(sa.provider, sa.auth_type, sa.name)
          {:noreply, assign(socket, :auths, SavedAuthentication.list_all())}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("open_agent_modal", _params, socket) do
    cs = Agents.change_agent(%Agent{})
    {:noreply,
     socket
     |> assign(:agent_changeset, cs)
     |> assign(:agent_form, to_form(cs))
     |> assign(:show_agent_modal, true)}
  end

  def handle_event("agent_validate", %{"agent" => params}, socket) do
    cs = Agents.change_agent(%Agent{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, agent_changeset: cs, agent_form: to_form(cs, action: :validate))}
  end

  def handle_event("agent_save", %{"agent" => params}, socket) do
    case Agents.create_agent(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent created")
         |> assign(:show_agent_modal, false)
         |> assign(:agents, Agents.list_agents_with_auth())}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, agent_changeset: cs, agent_form: to_form(cs))}
    end
  end

  @impl true
  def handle_info(%{topic: "oauth:events", event: "completed", payload: payload}, socket) do
    # Refresh list when a new auth is persisted by the callback server
    {:noreply,
     socket
     |> put_flash(:info, "OAuth completed for #{payload["provider"]}: #{payload["session_name"]}")
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:agents, Agents.list_agents_with_auth())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")
  defp format_dt(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S") <> " UTC"

  defp provider_label(p) when is_atom(p), do: Atom.to_string(p)
  defp provider_label(p) when is_binary(p), do: p

  defp map_count(nil), do: 0
  defp map_count(%{} = m), do: map_size(m)
  defp map_count(_), do: 0

  defp build_auth_options do
    SavedAuthentication.list_all() |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-xl font-semibold">Dashboard</h1>
        <.link navigate={~p"/auths/new"} class="btn btn-primary">New Auth</.link>
      </div>

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
                <td><%= sa.name %></td>
                <td><%= provider_label(sa.provider) %></td>
                <td class="uppercase"><%= sa.auth_type %></td>
                <td><%= format_dt(sa.expires_at) %></td>
                <td><%= format_dt(sa.inserted_at) %></td>
                <td class="space-x-2">
                  <.link navigate={~p"/auths/#{sa.id}"} class="btn btn-xs">View</.link>
                  <.link navigate={~p"/auths/#{sa.id}/edit"} class="btn btn-xs">Edit</.link>
                  <button phx-click="delete" phx-value-id={sa.id} data-confirm="Delete this auth?" class="btn btn-xs btn-error">Delete</button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <div class="mt-10">
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-lg font-semibold">Agents</h2>
          <button class="btn" phx-click="open_agent_modal">New Agent</button>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <%= for a <- @agents do %>
            <div class="card bg-base-200 p-4" id={"agent-" <> to_string(a.id)}>
              <div class="font-semibold text-base"> <%= a.name %> </div>
              <div class="text-sm opacity-80">Auth: <%= a.saved_authentication && a.saved_authentication.name %> (<%= a.saved_authentication && a.saved_authentication.provider %>/<%= a.saved_authentication && a.saved_authentication.auth_type %>)</div>
              <div class="text-xs opacity-70">Tools: <%= map_count(a.tools) %> • MCPs: <%= map_count(a.mcps) %></div>
              <div class="mt-2 space-x-2">
                <.link class="btn btn-xs" navigate={"/agents/" <> to_string(a.id)}>View</.link>
                <.link class="btn btn-xs" navigate={"/agents/" <> to_string(a.id) <> "/edit"}>Edit</.link>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <.modal :if={@show_agent_modal} id="agent-modal">
        <h3 class="text-lg font-semibold mb-2">Create Agent</h3>
        <.form for={@agent_form} id="agent-modal-form" phx-change="agent_validate" phx-submit="agent_save">
          <.input field={@agent_form[:name]} type="text" label="Name" />
          <.input field={@agent_form[:auth_id]} type="select" label="Saved Auth" options={@auth_options} prompt="Select an auth" />
          <.input field={@agent_form[:base_system_prompt_id]} type="select" label="Base System Prompt" options={@prompt_options} prompt="(optional)" />
          <.input field={@agent_form[:persona_id]} type="select" label="Persona" options={@persona_options} prompt="(optional)" />
          <div class="mt-3 space-x-2">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" class="btn" phx-click={JS.dispatch("phx:close-modal")}>Cancel</button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end
end

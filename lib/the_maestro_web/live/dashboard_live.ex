defmodule TheMaestroWeb.DashboardLive do
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Provider

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    {:ok,
     socket
     |> assign(:auths, Auth.list_saved_authentications())
     |> assign(:sessions, Conversations.list_sessions_with_auth())
     |> assign(:show_session_modal, false)
     |> assign(:auth_options, build_auth_options())
     |> assign(:prompt_options, build_prompt_options())
     |> assign(:persona_options, build_persona_options())
     |> assign(:session_form, to_form(Conversations.change_session(%Conversations.Session{})))
     |> assign(:session_provider, "openai")
     |> assign(:session_auth_options, build_auth_options_for(:openai))
     |> assign(:session_model_options, [])
     |> assign(:show_session_dir_picker, false)
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:auths, Auth.list_saved_authentications())
     |> assign(:sessions, Conversations.list_sessions_with_auth())
     |> assign(:auth_options, build_auth_options())
     |> assign(:prompt_options, build_prompt_options())
     |> assign(:persona_options, build_persona_options())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case id do
      id when is_binary(id) ->
        sa = Auth.get_saved_authentication!(id)
        # Allow deletion; DB FK now nilifies agent.auth_id
        _ = Provider.delete_session(sa.provider, sa.auth_type, sa.name)

        {:noreply,
         socket
         |> put_flash(:info, "Auth deleted; linked agents detached.")
         |> assign(:auths, Auth.list_saved_authentications())
         |> assign(:auth_options, build_auth_options())}

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
     |> assign(:sessions, Conversations.list_sessions_with_auth())}
  end

  def handle_event("open_session_modal", _params, socket) do
    cs = Conversations.change_session(%Conversations.Session{})

    {:noreply,
     socket
     |> assign(:session_provider, "openai")
     |> assign(:session_auth_options, build_auth_options_for(:openai))
     |> assign(:session_model_options, [])
     |> assign(:auth_options, build_auth_options())
     |> assign(:session_form, to_form(cs))
     |> assign(:show_session_modal, true)}
  end

  def handle_event("cancel_session_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_session_modal, false)
     |> assign(:show_session_dir_picker, false)}
  end

  # Target-aware validate to avoid clobbering model list when provider also present
  def handle_event(
        "session_validate",
        %{"_target" => ["session", target], "session" => params},
        socket
      ) do
    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    socket = assign(socket, session_form: to_form(cs, action: :validate))

    case target do
      "provider" ->
        provider = String.to_existing_atom(params["provider"])

        {:noreply,
         socket
         |> assign(:session_provider, params["provider"])
         |> assign(:session_auth_options, build_auth_options_for(provider))
         |> assign(:session_model_options, [])}

      "auth_id" ->
        models = build_model_options(%{"auth_id" => params["auth_id"]})
        {:noreply, assign(socket, :session_model_options, models)}

      _ ->
        {:noreply, socket}
    end
  end

  # Fallback validate (no _target); preserve previous behavior
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

    params = merge_session_params(socket, %{"working_dir" => wd})

    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, session_form: to_form(cs, action: :validate))}
  end

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  def handle_event("session_save", %{"session" => params}, socket) do
    # Mirror persona from persona_id if provided
    params =
      case Map.get(params, "persona_id") do
        nil ->
          params

        "" ->
          params

        id ->
          p = TheMaestro.SuppliedContext.get_item!(id)

          Map.put(params, "persona", %{
            "name" => p.name,
            "version" => p.version || 1,
            "persona_text" => p.text
          })
      end

    # Merge memory from memory_json if present
    params =
      case Map.get(params, "memory_json") do
        nil ->
          params

        "" ->
          params

        txt ->
          case Jason.decode(txt) do
            {:ok, %{} = m} -> Map.put(params, "memory", m)
            _ -> params
          end
      end

    case Conversations.create_session(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session created")
         |> assign(:show_session_modal, false)
         |> assign(:show_session_dir_picker, false)
         |> assign(:sessions, Conversations.list_sessions_with_auth())}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, session_form: to_form(cs))}
    end
  end

  # moved earlier to keep handle_event clauses grouped

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_session_modal, false)
     |> assign(:show_session_dir_picker, false)
     |> assign(:show_agent_modal, false)}
  end

  # moved earlier to keep handle_event clauses grouped

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :selected, path, :new_session}, socket) do
    params = merge_session_params(socket, %{"working_dir" => path})

    cs =
      Conversations.change_session(%Conversations.Session{}, params)
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
     |> assign(:auths, Auth.list_saved_authentications())
     |> assign(:auth_options, build_auth_options())}
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
    Auth.list_saved_authentications()
    |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
  end

  defp build_prompt_options do
    TheMaestro.SuppliedContext.list_items(:system_prompt) |> Enum.map(&{&1.name, &1.id})
  end

  defp build_persona_options do
    TheMaestro.SuppliedContext.list_items(:persona) |> Enum.map(&{&1.name, &1.id})
  end

  # agent options removed

  defp build_model_options(%{"auth_id" => auth_id}) when is_binary(auth_id) and auth_id != "" do
    with %{} = sa <- Auth.get_saved_authentication!(auth_id),
         {:ok, models} <- Provider.list_models(sa.provider, sa.auth_type, sa.name),
         list when is_list(list) and list != [] <-
           Enum.map(models, fn m -> {m.name || m.id, m.id} end) do
      list
    else
      _ ->
        # Fallback defaults per provider to ensure model select is populated
        case Auth.get_saved_authentication!(auth_id) do
          %{provider: provider} ->
            case provider do
              :openai ->
                [{"gpt-5", "gpt-5"}, {"gpt-4o", "gpt-4o"}]

              :anthropic ->
                [{"claude-3-5-sonnet", "claude-3-5-sonnet"}, {"claude-3-opus", "claude-3-opus"}]

              :gemini ->
                [
                  {"gemini-2.5-pro", "gemini-2.5-pro"},
                  {"gemini-1.5-pro-latest", "gemini-1.5-pro-latest"}
                ]

              _ ->
                []
            end

          _ ->
            []
        end
    end
  end

  defp build_auth_options_for(provider) when is_atom(provider) do
    Auth.list_saved_authentications_by_provider(provider)
    |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
  end

  defp build_model_options(_), do: []

  # Merge new form values into the current session form params, preserving prior selections
  defp merge_session_params(socket, extra) when is_map(extra) do
    (socket.assigns[:session_form] && socket.assigns.session_form.params) |> Map.merge(extra)
  end

  defp session_label(s) do
    cond do
      is_binary(s.name) and String.trim(s.name) != "" ->
        s.name

      s.saved_authentication && s.saved_authentication.name ->
        s.saved_authentication.name <> " · sess-" <> String.slice(s.id, 0, 8)

      true ->
        "sess-" <> String.slice(s.id, 0, 8)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div
        id="dashboard-root"
        class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden"
        phx-hook="DashboardHotkeys"
      >
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-8 border-b border-amber-600 pb-4">
            <h1 class="text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; DASHBOARD TERMINAL V2.1.4 &lt;&lt;&lt;
            </h1>
            <div class="flex gap-2">
              <.link
                navigate={~p"/supplied_context"}
                class="px-6 py-2 rounded transition-all duration-200 btn-green hover:glow-strong"
                data-hotkey="alt+c"
                data-hotkey-seq="g c"
                data-hotkey-label="Context Library"
              >
                <.icon name="hero-archive-box" class="inline mr-2 w-4 h-4" /> CONTEXT LIBRARY
              </.link>
              <.link
                navigate={~p"/auths/new"}
                class="px-6 py-2 rounded transition-all duration-200 btn-amber hover:glow-strong"
                data-hotkey="alt+h"
                data-hotkey-seq="g h"
                data-hotkey-label="New Auth"
              >
                <.icon name="hero-plus" class="inline mr-2 w-4 h-4" /> NEW AUTH
              </.link>
            </div>
          </div>

          <section class="mb-12">
            <h2 class="text-2xl font-bold text-green-400 mb-6 glow">
              &gt; SAVED_AUTHENTICATIONS.DAT
            </h2>
            <div class="terminal-card terminal-border-amber rounded-lg overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full">
                  <thead class="bg-amber-600/20">
                    <tr>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">NAME</th>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">PROVIDER</th>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">AUTH_TYPE</th>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">EXPIRATION</th>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">CREATED</th>
                      <th class="px-4 py-3 text-left font-bold text-amber-300">ACTIONS</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for sa <- @auths do %>
                      <tr id={"auth-#{sa.id}"} class="border-t border-amber-800 hover:bg-amber-600/10">
                        <td class="px-4 py-3 text-amber-200">{sa.name}</td>
                        <td class="px-4 py-3 text-amber-200">{provider_label(sa.provider)}</td>
                        <td class="px-4 py-3 text-amber-200 uppercase">{sa.auth_type}</td>
                        <td class="px-4 py-3 text-amber-200">{format_dt(sa.expires_at)}</td>
                        <td class="px-4 py-3 text-amber-200">{format_dt(sa.inserted_at)}</td>
                        <td class="px-4 py-3">
                          <div class="flex space-x-2">
                            <.link
                              navigate={~p"/auths/#{sa.id}"}
                              class="text-green-400 hover:text-green-300"
                            >
                              <.icon name="hero-eye" class="h-4 w-4" />
                            </.link>
                            <.link
                              navigate={~p"/auths/#{sa.id}/edit"}
                              class="text-blue-400 hover:text-blue-300"
                            >
                              <.icon name="hero-pencil-square" class="h-4 w-4" />
                            </.link>
                            <button
                              phx-click="delete"
                              phx-value-id={sa.id}
                              data-confirm="Delete this auth?"
                              class="text-red-400 hover:text-red-300"
                            >
                              <.icon name="hero-trash" class="h-4 w-4" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </section>

          <section>
            <div class="flex justify-between items-center mb-6">
              <h2 class="text-2xl font-bold text-green-400 glow">&gt; SESSION_MANAGER.DAT</h2>
              <button
                class="px-4 py-2 rounded transition-all duration-200 btn-blue"
                phx-click="open_session_modal"
                data-hotkey="alt+n"
                data-hotkey-seq="g n"
                data-hotkey-label="New Session"
              >
                <.icon name="hero-plus" class="inline mr-2 h-4 w-4" /> NEW SESSION
              </button>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for s <- @sessions do %>
                <div
                  class="terminal-card terminal-border-blue rounded-lg p-6 transition-colors"
                  id={"session-" <> to_string(s.id)}
                >
                  <h3 class="text-xl font-bold text-blue-300 mb-3 glow">{session_label(s)}</h3>
                  <div class="space-y-2 text-sm">
                    <p class="text-amber-300">
                      Auth: {s.saved_authentication && s.saved_authentication.name} ({s.saved_authentication &&
                        s.saved_authentication.provider}/ {s.saved_authentication &&
                        s.saved_authentication.auth_type})
                    </p>
                    <p class="text-amber-200">Model: {s.model_id || "(auto)"}</p>
                    <p class="text-amber-200">Last used: {format_dt(s.last_used_at)}</p>
                  </div>
                  <div class="flex justify-between mt-4 pt-3 border-t border-blue-800">
                    <div class="flex space-x-2">
                      <.link
                        class="px-3 py-1 rounded text-xs btn-green"
                        navigate={~p"/sessions/#{s.id}/chat"}
                      >
                        CHAT
                      </.link>
                      <.link
                        class="text-blue-400 hover:text-blue-300"
                        navigate={~p"/sessions/#{s.id}/edit"}
                      >
                        <.icon name="hero-pencil-square" class="h-4 w-4" />
                      </.link>
                    </div>
                    <button
                      class="text-red-400 hover:text-red-300"
                      phx-click="delete_session"
                      phx-value-id={s.id}
                    >
                      <.icon name="hero-trash" class="h-4 w-4" />
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </section>
        </div>

        <.modal :if={@show_session_modal} id="session-modal">
          <h3 class="text-2xl font-bold text-blue-400 mb-6 glow">CREATE NEW SESSION</h3>
          <.form
            for={@session_form}
            id="session-modal-form"
            phx-submit="session_save"
            phx-change="session_validate"
          >
            <.input field={@session_form[:name]} type="text" label="Session Name" />
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label class="text-xs">Provider (filter)</label>
                <select name="session[provider]" class="input">
                  <%= for p <- ["openai", "anthropic", "gemini"] do %>
                    <option value={p} selected={@session_provider == p}>{p}</option>
                  <% end %>
                </select>
              </div>
              <.input
                field={@session_form[:auth_id]}
                type="select"
                label="Saved Auth"
                options={@session_auth_options}
                prompt="Select auth"
              />
              <.input
                field={@session_form[:model_id]}
                type="select"
                label="Model"
                options={@session_model_options}
                prompt="(auto)"
              />
              <div>
                <.input field={@session_form[:working_dir]} type="text" label="Working Directory" />
                <div class="mt-1 flex gap-2">
                  <button type="button" class="btn btn-xs btn-amber" phx-click="session_use_root_dir">
                    ROOT
                  </button>
                  <button
                    type="button"
                    class="btn btn-xs btn-amber"
                    phx-click="open_session_dir_picker"
                  >
                    <.icon name="hero-folder" class="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="mt-2">
              <label class="text-xs">Chat History</label>
              <div class="text-sm opacity-80">Start New Chat</div>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input
                field={@session_form[:persona_id]}
                type="select"
                label="Persona"
                options={@persona_options}
                prompt="(optional)"
              />
              <div>
                <label class="text-xs">Memory (JSON)</label>
                <textarea name="session[memory_json]" rows="4" class="textarea-terminal"></textarea>
              </div>
            </div>
            <div class="mt-2"></div>
            <div class="mt-3 space-x-2">
              <button type="submit" class="btn btn-blue">Save</button>
              <button type="button" class="btn" phx-click="cancel_session_modal">Cancel</button>
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

        <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
      </div>
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

  # Agents grid removed in session-centric cleanup

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
            <div class="text-sm opacity-80">
              Auth: {s.saved_authentication && s.saved_authentication.name} ({s.saved_authentication &&
                s.saved_authentication.provider}/ {s.saved_authentication &&
                s.saved_authentication.auth_type})
            </div>
            <div class="text-xs opacity-70">Model: {s.model_id || "(auto)"}</div>
            <div class="text-xs opacity-70">Last used: {format_dt(s.last_used_at)}</div>
            <div class="mt-2 space-x-2">
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/chat"}>Go into chat</.link>
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/chat"}>
                Open
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

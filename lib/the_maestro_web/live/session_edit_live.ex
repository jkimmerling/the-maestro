defmodule TheMaestroWeb.SessionEditLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestroWeb.MCPServersLive.FormComponent

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session =
      id
      |> Conversations.get_session!()
      |> Conversations.preload_session_mcp()

    selected = Enum.map(session.mcp_servers || [], & &1.id)

    {:ok,
     socket
     |> assign(:page_title, "Edit Session")
     |> assign(:session, session)
     |> assign(:form, to_form(Conversations.change_session(session)))
     |> assign(:auth_options, auth_options())
     |> assign(:show_dir_picker, false)
     |> assign(:mcp_server_options, MCP.server_options(include_disabled?: true))
     |> assign(:selected_mcp_server_ids, selected)
     |> assign(:show_mcp_modal, false)
     |> assign(:form_params, %{})}
  end

  @impl true
  def handle_event("validate", %{"session" => params}, socket) do
    changeset =
      Conversations.change_session(socket.assigns.session, params) |> Map.put(:action, :validate)

    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:form_params, params)
     |> assign(:selected_mcp_server_ids, selected)}
  end

  @impl true
  def handle_event("save", %{"session" => params}, socket) do
    case Conversations.update_session(socket.assigns.session, params) do
      {:ok, session} ->
        session = Conversations.preload_session_mcp(session)
        selected = Enum.map(session.mcp_servers || [], & &1.id)

        {:noreply,
         socket
         |> put_flash(:info, "Session updated")
         |> assign(:session, session)
         |> assign(:form, to_form(Conversations.change_session(session)))
         |> assign(:selected_mcp_server_ids, selected)
         |> assign(:form_params, %{})
         |> assign(:show_mcp_modal, false)
         |> push_navigate(to: ~p"/sessions/#{session.id}/chat")}

      {:error, changeset} ->
        selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:form_params, params)
         |> assign(:selected_mcp_server_ids, selected)}
    end
  end

  @impl true
  def handle_event("use_root_dir", _params, socket) do
    wd = File.cwd!() |> Path.expand()

    params = Map.put(socket.assigns[:form_params] || %{}, "working_dir", wd)
    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    changeset =
      socket.assigns.session
      |> Conversations.change_session(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:form_params, params)
     |> assign(:selected_mcp_server_ids, selected)}
  end

  @impl true
  def handle_event("open_dir_picker", _params, socket) do
    {:noreply, assign(socket, :show_dir_picker, true)}
  end

  def handle_event("open_mcp_modal", _params, socket) do
    {:noreply, assign(socket, :show_mcp_modal, true)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, socket |> assign(:show_dir_picker, false) |> assign(:show_mcp_modal, false)}
  end

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :selected, path, _ctx}, socket) do
    params = Map.put(socket.assigns[:form_params] || %{}, "working_dir", path)
    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    cs =
      socket.assigns.session
      |> Conversations.change_session(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(cs))
     |> assign(:form_params, params)
     |> assign(:selected_mcp_server_ids, selected)
     |> assign(:show_dir_picker, false)}
  end

  def handle_info({TheMaestroWeb.DirectoryPicker, :cancel, _ctx}, socket) do
    {:noreply, assign(socket, :show_dir_picker, false)}
  end

  def handle_info({FormComponent, {:saved, server}}, socket) do
    selected = Enum.uniq([server.id | socket.assigns.selected_mcp_server_ids || []])

    params =
      socket.assigns[:form_params]
      |> Kernel.||(%{})
      |> Map.put("mcp_server_ids", selected)

    changeset =
      socket.assigns.session
      |> Conversations.change_session(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:mcp_server_options, MCP.server_options(include_disabled?: true))
     |> assign(:selected_mcp_server_ids, selected)
     |> assign(:form_params, params)
     |> assign(:form, to_form(changeset))
     |> assign(:show_mcp_modal, false)}
  end

  def handle_info({FormComponent, {:canceled, _}}, socket) do
    {:noreply, assign(socket, :show_mcp_modal, false)}
  end

  defp auth_options do
    TheMaestro.Auth.list_saved_authentications()
    |> Enum.map(&{"#{&1.name} (#{&1.provider}/#{&1.auth_type})", &1.id})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Edit Session {@session.id}
        <:actions>
          <.button navigate={~p"/sessions/#{@session.id}/chat"}>Back to Chat</.button>
        </:actions>
      </.header>

      <.form for={@form} id="session-edit-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input
          field={@form[:auth_id]}
          type="select"
          label="Saved Auth"
          options={@auth_options}
          prompt="Select an auth"
        />
        <.input field={@form[:last_used_at]} type="datetime-local" label="Last used at" />
        <div class="grid grid-cols-1 gap-2">
          <.input
            field={@form[:working_dir]}
            type="text"
            label="Working directory"
            placeholder={Path.expand(".")}
            help="Absolute path used as CWD for tools and shell. Paste a path or click Use project root."
          />
          <div>
            <button type="button" class="btn btn-xs" phx-click="use_root_dir">
              Use project root
            </button>
            <button type="button" class="btn btn-xs ml-2" phx-click="open_dir_picker">
              Browse…
            </button>
          </div>
        </div>
        <div class="mt-4 space-y-2">
          <label class="text-sm font-semibold">MCP Servers</label>
          <p class="text-xs text-slate-500">
            Attach connectors that should be available when this session boots.
          </p>
          <.input
            type="select"
            name="session[mcp_server_ids][]"
            multiple
            options={@mcp_server_options}
            value={@selected_mcp_server_ids}
            class="min-h-[6rem]"
          />
          <button type="button" class="btn btn-xs" phx-click="open_mcp_modal">
            <.icon name="hero-plus" class="h-4 w-4" />
            <span class="ml-1">New MCP Server</span>
          </button>
        </div>
        <footer class="mt-2 space-x-2">
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          <.button navigate={~p"/dashboard"}>Cancel</.button>
        </footer>
      </.form>

      <.modal :if={@show_mcp_modal} id="session-edit-mcp">
        <.live_component
          module={FormComponent}
          id="edit-session-mcp-form"
          title="New MCP Server"
          server={%MCP.Servers{}}
          action={:new}
        />
      </.modal>

      <.modal :if={@show_dir_picker} id="dir-picker-edit">
        <.live_component
          module={TheMaestroWeb.DirectoryPicker}
          id="dirpick-edit"
          start_path={@form[:working_dir].value || Path.expand(".")}
          context={:edit}
        />
      </.modal>
      <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
    </Layouts.app>
    """
  end

  defp normalize_mcp_ids(nil), do: []

  defp normalize_mcp_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_mcp_ids(id), do: normalize_mcp_ids([id])
end

defmodule TheMaestroWeb.SessionEditLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Conversations.get_session!(id)

    {:ok,
     socket
     |> assign(:page_title, "Edit Session")
     |> assign(:session, session)
     |> assign(:form, to_form(Conversations.change_session(session)))
     |> assign(:auth_options, auth_options())
     |> assign(:show_dir_picker, false)}
  end

  @impl true
  def handle_event("validate", %{"session" => params}, socket) do
    changeset =
      Conversations.change_session(socket.assigns.session, params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"session" => params}, socket) do
    case Conversations.update_session(socket.assigns.session, params) do
      {:ok, session} ->
        {:noreply,
         socket
         |> put_flash(:info, "Session updated")
         |> push_navigate(to: ~p"/sessions/#{session.id}/chat")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("use_root_dir", _params, socket) do
    wd = File.cwd!() |> Path.expand()

    changeset =
      socket.assigns.session
      |> Conversations.change_session(%{"working_dir" => wd})
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("open_dir_picker", _params, socket) do
    {:noreply, assign(socket, :show_dir_picker, true)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_dir_picker, false)}
  end

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :selected, path, _ctx}, socket) do
    cs =
      socket.assigns.session
      |> Conversations.change_session(%{"working_dir" => path})
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(cs)) |> assign(:show_dir_picker, false)}
  end

  def handle_info({TheMaestroWeb.DirectoryPicker, :cancel, _ctx}, socket) do
    {:noreply, assign(socket, :show_dir_picker, false)}
  end

  defp auth_options do
    TheMaestro.SavedAuthentication.list_all()
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
        <footer class="mt-2 space-x-2">
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          <.button navigate={~p"/dashboard"}>Cancel</.button>
        </footer>
      </.form>

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
end

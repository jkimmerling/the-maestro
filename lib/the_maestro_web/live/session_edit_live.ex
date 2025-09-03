defmodule TheMaestroWeb.SessionEditLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents
  alias TheMaestro.Conversations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Conversations.get_session!(id)

    {:ok,
     socket
     |> assign(:page_title, "Edit Session")
     |> assign(:session, session)
     |> assign(:form, to_form(Conversations.change_session(session)))
     |> assign(:agent_options, agent_options())}
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

  defp agent_options do
    Agents.list_agents_with_auth()
    |> Enum.map(&{&1.name, &1.id})
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
          field={@form[:agent_id]}
          type="select"
          label="Agent"
          options={@agent_options}
          prompt="Select an agent"
        />
        <.input field={@form[:last_used_at]} type="datetime-local" label="Last used at" />
        <footer class="mt-2 space-x-2">
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          <.button navigate={~p"/dashboard"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end
end

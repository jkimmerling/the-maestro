defmodule TheMaestroWeb.ChatEntryLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Conversations
  alias TheMaestro.Conversations.ChatEntry

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage chat_entry records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="chat_entry-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:turn_index]} type="number" label="Turn index" />
        <.input field={@form[:actor]} type="text" label="Actor" />
        <.input field={@form[:provider]} type="text" label="Provider" />
        <textarea name="chat_entry[combined_chat]" class="textarea-terminal" rows="2"></textarea>
        <textarea name="chat_entry[request_headers]" class="textarea-terminal" rows="2"></textarea>
        <textarea name="chat_entry[response_headers]" class="textarea-terminal" rows="2"></textarea>
        <.input field={@form[:edit_version]} type="number" label="Edit version" />
        <.input field={@form[:thread_id]} type="text" label="Thread" />
        <.input field={@form[:parent_thread_id]} type="text" label="Parent thread" />
        <.input field={@form[:fork_from_entry_id]} type="text" label="Fork from entry" />
        <.input field={@form[:thread_label]} type="text" label="Thread label" />
        <.input field={@form[:session_id]} type="text" label="Session" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Chat entry</.button>
          <.button navigate={return_path(@return_to, @chat_entry)}>Cancel</.button>
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
    chat_entry = Conversations.get_chat_entry!(id)

    socket
    |> assign(:page_title, "Edit Chat entry")
    |> assign(:chat_entry, chat_entry)
    |> assign(:form, to_form(Conversations.change_chat_entry(chat_entry)))
  end

  defp apply_action(socket, :new, _params) do
    chat_entry = %ChatEntry{}

    socket
    |> assign(:page_title, "New Chat entry")
    |> assign(:chat_entry, chat_entry)
    |> assign(:form, to_form(Conversations.change_chat_entry(chat_entry)))
  end

  @impl true
  def handle_event("validate", %{"chat_entry" => chat_entry_params}, socket) do
    changeset = Conversations.change_chat_entry(socket.assigns.chat_entry, chat_entry_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"chat_entry" => chat_entry_params}, socket) do
    save_chat_entry(socket, socket.assigns.live_action, chat_entry_params)
  end

  defp save_chat_entry(socket, :edit, chat_entry_params) do
    case Conversations.update_chat_entry(socket.assigns.chat_entry, chat_entry_params) do
      {:ok, chat_entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Chat entry updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, chat_entry))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_chat_entry(socket, :new, chat_entry_params) do
    case Conversations.create_chat_entry(chat_entry_params) do
      {:ok, chat_entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Chat entry created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, chat_entry))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _chat_entry), do: ~p"/chat_history"
  defp return_path("show", chat_entry), do: ~p"/chat_history/#{chat_entry}"
end

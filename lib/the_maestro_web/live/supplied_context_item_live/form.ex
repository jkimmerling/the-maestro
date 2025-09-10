defmodule TheMaestroWeb.SuppliedContextItemLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.SuppliedContext
  alias TheMaestro.SuppliedContext.SuppliedContextItem

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage supplied_context_item records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="supplied-context-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          prompt="Choose a value"
          options={Ecto.Enum.values(TheMaestro.SuppliedContext.SuppliedContextItem, :type)}
        />
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:text]} type="textarea" label="Text" />
        <.input field={@form[:version]} type="number" label="Version" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Supplied context item</.button>
          <.button navigate={return_path(@return_to, @supplied_context_item)}>Cancel</.button>
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
    supplied_context_item = SuppliedContext.get_supplied_context_item!(id)

    socket
    |> assign(:page_title, "Edit Supplied context item")
    |> assign(:supplied_context_item, supplied_context_item)
    |> assign(:form, to_form(SuppliedContext.change_supplied_context_item(supplied_context_item)))
  end

  defp apply_action(socket, :new, _params) do
    supplied_context_item = %SuppliedContextItem{}

    socket
    |> assign(:page_title, "New Supplied context item")
    |> assign(:supplied_context_item, supplied_context_item)
    |> assign(:form, to_form(SuppliedContext.change_supplied_context_item(supplied_context_item)))
  end

  @impl true
  def handle_event("validate", %{"supplied_context_item" => supplied_context_item_params}, socket) do
    changeset =
      SuppliedContext.change_supplied_context_item(
        socket.assigns.supplied_context_item,
        supplied_context_item_params
      )
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"supplied_context_item" => supplied_context_item_params}, socket) do
    save_supplied_context_item(socket, socket.assigns.live_action, supplied_context_item_params)
  end

  defp save_supplied_context_item(socket, :edit, supplied_context_item_params) do
    case SuppliedContext.update_supplied_context_item(
           socket.assigns.supplied_context_item,
           supplied_context_item_params
         ) do
      {:ok, supplied_context_item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplied context item updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, supplied_context_item))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_supplied_context_item(socket, :new, supplied_context_item_params) do
    case SuppliedContext.create_supplied_context_item(supplied_context_item_params) do
      {:ok, supplied_context_item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplied context item created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, supplied_context_item))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _supplied_context_item), do: ~p"/supplied_context"
  defp return_path("show", supplied_context_item), do: ~p"/supplied_context/#{supplied_context_item}"
end

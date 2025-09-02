defmodule TheMaestroWeb.BaseSystemPromptLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Prompts
  alias TheMaestro.Prompts.BaseSystemPrompt

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage base_system_prompt records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="base_system_prompt-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:prompt_text]} type="textarea" label="Prompt text" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Base system prompt</.button>
          <.button navigate={return_path(@return_to, @base_system_prompt)}>Cancel</.button>
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
    base_system_prompt = Prompts.get_base_system_prompt!(id)

    socket
    |> assign(:page_title, "Edit Base system prompt")
    |> assign(:base_system_prompt, base_system_prompt)
    |> assign(:form, to_form(Prompts.change_base_system_prompt(base_system_prompt)))
  end

  defp apply_action(socket, :new, _params) do
    base_system_prompt = %BaseSystemPrompt{}

    socket
    |> assign(:page_title, "New Base system prompt")
    |> assign(:base_system_prompt, base_system_prompt)
    |> assign(:form, to_form(Prompts.change_base_system_prompt(base_system_prompt)))
  end

  @impl true
  def handle_event("validate", %{"base_system_prompt" => base_system_prompt_params}, socket) do
    changeset =
      Prompts.change_base_system_prompt(
        socket.assigns.base_system_prompt,
        base_system_prompt_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"base_system_prompt" => base_system_prompt_params}, socket) do
    save_base_system_prompt(socket, socket.assigns.live_action, base_system_prompt_params)
  end

  defp save_base_system_prompt(socket, :edit, base_system_prompt_params) do
    case Prompts.update_base_system_prompt(
           socket.assigns.base_system_prompt,
           base_system_prompt_params
         ) do
      {:ok, base_system_prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Base system prompt updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, base_system_prompt))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_base_system_prompt(socket, :new, base_system_prompt_params) do
    case Prompts.create_base_system_prompt(base_system_prompt_params) do
      {:ok, base_system_prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, "Base system prompt created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, base_system_prompt))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _base_system_prompt), do: ~p"/base_system_prompts"
  defp return_path("show", base_system_prompt), do: ~p"/base_system_prompts/#{base_system_prompt}"
end

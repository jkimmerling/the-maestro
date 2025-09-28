defmodule TheMaestroWeb.ApiKeyLive.Form do
  use TheMaestroWeb, :live_view

  alias TheMaestro.ApiKeys
  alias TheMaestro.ApiKeys.ApiKey

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage api_key records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="api_key-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:label]} type="text" label="Label" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save</.button>
          <.button navigate={return_path(@return_to, @api_key)}>Cancel</.button>
        </footer>
      </.form>

      <%= if @plaintext_token do %>
        <.modal id="reveal-token">
          <p class="mb-2">Copy this API token now. You will not be able to see it again.</p>
          <pre class="p-2 bg-zinc-900 text-zinc-100 rounded">{@plaintext_token}</pre>
          <div class="mt-4">
            <.button phx-click={JS.hide(to: "#reveal-token")} variant="primary">Done</.button>
          </div>
        </.modal>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:plaintext_token, nil)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    api_key = ApiKeys.get_key!(id)

    socket
    |> assign(:page_title, "Edit Api key")
    |> assign(:api_key, api_key)
    |> assign(:form, to_form(Ecto.Changeset.change(api_key, %{})))
  end

  defp apply_action(socket, :new, _params) do
    api_key = %ApiKey{}

    socket
    |> assign(:page_title, "New Api key")
    |> assign(:api_key, api_key)
    |> assign(:form, to_form(Ecto.Changeset.change(api_key, %{})))
  end

  @impl true
  def handle_event("validate", %{"api_key" => api_key_params}, socket) do
    changeset =
      %ApiKey{}
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.cast(api_key_params, [:label])
      |> Ecto.Changeset.validate_required([:label])
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"api_key" => api_key_params}, socket) do
    save_api_key(socket, socket.assigns.live_action, api_key_params)
  end

  defp save_api_key(socket, :edit, _params) do
    {key, token} = ApiKeys.rotate!(socket.assigns.api_key)
    {:noreply,
     socket
     |> assign(:api_key, key)
     |> assign(:plaintext_token, token)
     |> put_flash(:info, "API key rotated")
     |> push_patch(to: ~p"/api_keys/#{key}/edit?return_to=#{socket.assigns.return_to}")}
  end

  defp save_api_key(socket, :new, api_key_params) do
    label = api_key_params["label"]
    {api_key, token} = ApiKeys.create_key!(label)
    {:noreply,
     socket
     |> assign(:api_key, api_key)
     |> assign(:plaintext_token, token)
     |> put_flash(:info, "API key created")}
  end

  defp return_path("index", _api_key), do: ~p"/api_keys"
  defp return_path("show", api_key), do: ~p"/api_keys/#{api_key}"
end

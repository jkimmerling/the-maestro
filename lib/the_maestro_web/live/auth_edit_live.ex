defmodule TheMaestroWeb.AuthEditLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sa = SavedAuthentication.get!(String.to_integer(id))
    api_key = Map.get(sa.credentials, "api_key", "")

    {:ok,
     socket
     |> assign(:sa, sa)
     |> assign(:name, sa.name)
     |> assign(:api_key, api_key)
     |> assign(:page_title, "Edit Auth")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("change", %{"auth" => params}, socket) do
    {:noreply,
     socket
     |> assign(:name, Map.get(params, "name", socket.assigns.name))
     |> assign(:api_key, Map.get(params, "api_key", socket.assigns.api_key))
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    sa = socket.assigns.sa
    with :ok <- Provider.validate_session_name(socket.assigns.name),
         {:ok, sa} <- maybe_update(sa, socket.assigns) do
      {:noreply, push_navigate(socket, to: ~p"/auths/#{sa.id}")}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  defp maybe_update(sa, assigns) do
    attrs = %{name: assigns.name}
    attrs =
      if sa.auth_type == :api_key do
        cred = Map.put(sa.credentials || %{}, "api_key", assigns.api_key)
        Map.put(attrs, :credentials, cred)
      else
        attrs
      end

    SavedAuthentication.update(sa, attrs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link navigate={~p"/auths/#{@sa.id}"} class="btn btn-ghost mb-4">← Back</.link>
      <h1 class="text-xl font-semibold mb-2">Edit Auth</h1>

      <%= if @error do %>
        <div class="alert alert-error mb-4">
          <span><%= @error %></span>
        </div>
      <% end %>

      <.form for={%{}} as={:auth} phx-change="change" class="space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="label">Name</label>
            <input name="auth[name]" type="text" value={@name} class="input input-bordered w-full" />
          </div>
          <div>
            <label class="label">Provider</label>
            <input value={@sa.provider} class="input input-bordered w-full" disabled />
          </div>
          <div>
            <label class="label">Auth Type</label>
            <input value={@sa.auth_type} class="input input-bordered w-full" disabled />
          </div>
        </div>

        <%= if @sa.auth_type == :api_key do %>
          <div>
            <label class="label">API Key</label>
            <input name="auth[api_key]" type="password" value={@api_key} class="input input-bordered w-full" />
          </div>
        <% end %>

        <div class="mt-4">
          <button type="button" phx-click="save" class="btn btn-primary">Save</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end

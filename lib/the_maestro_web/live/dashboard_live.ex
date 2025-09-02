defmodule TheMaestroWeb.DashboardLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    {:ok,
     socket
     |> assign(:auths, SavedAuthentication.list_all())
     |> assign(:page_title, "Dashboard")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :auths, SavedAuthentication.list_all())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {int, _} ->
        sa = SavedAuthentication.get!(int)
        # Normalize provider to atom safely
        # Use Provider wrapper for idempotent deletion
        _ = Provider.delete_session(sa.provider, sa.auth_type, sa.name)
        {:noreply, assign(socket, :auths, SavedAuthentication.list_all())}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{topic: "oauth:events", event: "completed", payload: payload}, socket) do
    # Refresh list when a new auth is persisted by the callback server
    {:noreply,
     socket
     |> put_flash(:info, "OAuth completed for #{payload["provider"]}: #{payload["session_name"]}")
     |> assign(:auths, SavedAuthentication.list_all())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")
  defp format_dt(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S") <> " UTC"

  defp provider_label(p) when is_atom(p), do: Atom.to_string(p)
  defp provider_label(p) when is_binary(p), do: p

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
    </Layouts.app>
    """
  end
end

defmodule TheMaestroWeb.AuthShowLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sa = SavedAuthentication.get!(String.to_integer(id))
    {:ok, assign(socket, :sa, sa) |> assign(:page_title, "Auth Details")}
  end

  @impl true
  def handle_event("refresh_tokens", _params, socket) do
    sa = socket.assigns.sa

    case Provider.refresh_tokens(String.to_atom(sa.provider), sa.name) do
      {:ok, _} -> {:noreply, assign(socket, :sa, SavedAuthentication.get!(sa.id))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")

  defp format_dt(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S") <> " UTC"

  defp redact_credentials(%{"api_key" => _} = cred), do: Map.put(cred, "api_key", "••••••••••")

  defp redact_credentials(%{"access_token" => _} = cred),
    do: Map.put(cred, "access_token", "••••••••••")

  defp redact_credentials(cred) when is_map(cred), do: cred
  defp redact_credentials(_), do: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link navigate={~p"/dashboard"} class="btn btn-ghost mb-4">← Back</.link>
      <h1 class="text-xl font-semibold mb-2">Auth Details</h1>

      <div class="card bg-base-200 p-4 space-y-2">
        <div><b>Name:</b> {@sa.name}</div>
        <div><b>Provider:</b> {@sa.provider}</div>
        <div><b>Auth Type:</b> {@sa.auth_type}</div>
        <div><b>Expires:</b> {format_dt(@sa.expires_at)}</div>
        <div><b>Created:</b> {format_dt(@sa.inserted_at)}</div>
        <div><b>Updated:</b> {format_dt(@sa.updated_at)}</div>
        <div class="mt-2">
          <details>
            <summary class="cursor-pointer">Credentials (redacted)</summary>
            <pre class="mt-2 text-xs">{inspect(redact_credentials(@sa.credentials), pretty: true)}</pre>
          </details>
        </div>
        <div class="mt-3 space-x-2">
          <%= if @sa.auth_type == :oauth do %>
            <button phx-click="refresh_tokens" class="btn btn-xs">Refresh Tokens</button>
          <% end %>
          <.link navigate={~p"/auths/#{@sa.id}/edit"} class="btn btn-xs">Edit</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

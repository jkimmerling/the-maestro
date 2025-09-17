defmodule TheMaestroWeb.AuthShowLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Provider

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sa = Auth.get_saved_authentication!(id)
    {:ok, assign(socket, :sa, sa) |> assign(:page_title, "AUTH: #{sa.name}")}
  end

  @impl true
  def handle_event("refresh_tokens", _params, socket) do
    sa = socket.assigns.sa

    case Provider.refresh_tokens(String.to_atom(sa.provider), sa.name) do
      {:ok, _} -> {:noreply, assign(socket, :sa, Auth.get_saved_authentication!(sa.id))}
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
    <Layouts.app
      flash={@flash}
      page_title={@page_title}
      main_class="px-6 py-8"
      container_class="mx-auto max-w-4xl"
    >
      <div class="flex justify-end mb-6">
        <.link
          navigate={~p"/dashboard"}
          class="px-4 py-2 rounded transition-all duration-200 btn-amber"
          data-hotkey="alt+b"
          data-hotkey-seq="g d"
          data-hotkey-label="Go to Dashboard"
        >
          <.icon name="hero-arrow-left" class="inline mr-2 w-4 h-4" /> BACK
        </.link>
      </div>

      <div class="terminal-card terminal-border-amber p-6 space-y-2">
        <div><b class="text-amber-300">Name:</b> {@sa.name}</div>
        <div><b class="text-amber-300">Provider:</b> {@sa.provider}</div>
        <div><b class="text-amber-300">Auth Type:</b> {@sa.auth_type}</div>
        <div><b class="text-amber-300">Expires:</b> {format_dt(@sa.expires_at)}</div>
        <div><b class="text-amber-300">Created:</b> {format_dt(@sa.inserted_at)}</div>
        <div><b class="text-amber-300">Updated:</b> {format_dt(@sa.updated_at)}</div>
        <div class="mt-2">
          <details>
            <summary class="cursor-pointer glow">Credentials (redacted)</summary>
            <pre class="mt-2 text-xs text-amber-200">{inspect(redact_credentials(@sa.credentials), pretty: true)}</pre>
          </details>
        </div>
        <div class="mt-3 space-x-2">
          <%= if @sa.auth_type == :oauth do %>
            <button
              phx-click="refresh_tokens"
              class="px-3 py-1 rounded text-xs btn-green"
              data-hotkey="alt+r"
              data-hotkey-label="Refresh Tokens"
            >
              Refresh Tokens
            </button>
          <% end %>
          <.link
            navigate={~p"/auths/#{@sa.id}/edit"}
            class="px-3 py-1 rounded text-xs btn-blue"
            data-hotkey-seq="g e"
            data-hotkey-label="Edit Auth"
          >
            Edit
          </.link>
        </div>
      </div>
      <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
    </Layouts.app>
    """
  end
end

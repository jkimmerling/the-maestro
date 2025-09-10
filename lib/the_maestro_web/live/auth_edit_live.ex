defmodule TheMaestroWeb.AuthEditLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Provider

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sa = Auth.get_saved_authentication!(id)
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

    Auth.update_saved_authentication(sa, attrs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; EDIT AUTH &lt;&lt;&lt;
            </h1>
            <.link
              navigate={~p"/auths/#{@sa.id}"}
              class="px-4 py-2 rounded transition-all duration-200 btn-amber"
              data-hotkey-seq="g v"
              data-hotkey-label="View Auth"
              data-hotkey="alt+b"
            >
              <.icon name="hero-arrow-left" class="inline mr-2 w-4 h-4" /> BACK
            </.link>
          </div>

          <%= if @error do %>
            <div class="terminal-card terminal-border-red p-3 mb-4 text-red-300 glow">{@error}</div>
          <% end %>

          <.form for={%{}} as={:auth} phx-change="change">
            <div class="terminal-card terminal-border-amber p-6 space-y-4">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-amber-400 mb-1">Name</label>
                  <input name="auth[name]" type="text" value={@name} class="input-terminal" />
                </div>
                <div>
                  <label class="block text-amber-400 mb-1">Provider</label>
                  <input value={@sa.provider} class="input-terminal opacity-70" disabled />
                </div>
                <div>
                  <label class="block text-amber-400 mb-1">Auth Type</label>
                  <input value={@sa.auth_type} class="input-terminal opacity-70" disabled />
                </div>
              </div>

              <%= if @sa.auth_type == :api_key do %>
                <div>
                  <label class="block text-amber-400 mb-1">API Key</label>
                  <input name="auth[api_key]" type="password" value={@api_key} class="input-terminal" />
                </div>
              <% end %>

              <div class="mt-4">
                <button type="button" phx-click="save" class="px-4 py-2 rounded btn-blue">
                  Save
                </button>
              </div>
            </div>
          </.form>
        </div>
        <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
      </div>
    </Layouts.app>
    """
  end
end

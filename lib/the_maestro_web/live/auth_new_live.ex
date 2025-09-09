defmodule TheMaestroWeb.AuthNewLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Provider

  @providers [:openai, :anthropic, :gemini]
  @auth_types [:oauth, :api_key]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    {:ok,
     socket
     |> assign(:page_title, "Create New Auth")
     |> assign(:providers, @providers)
     |> assign(:auth_types, @auth_types)
     |> assign(:name, "")
     |> assign(:provider, hd(@providers))
     |> assign(:auth_type, hd(@auth_types))
     |> assign(:api_key, "")
     |> assign(:user_project, "")
     |> assign(:oauth_url, nil)
     |> assign(:pkce_params, nil)
     |> assign(:auth_code, "")
     |> assign(:error, nil)
     |> assign(:callback_listening, false)
     |> assign(:callback_port, 1455)
     |> assign(:callback_deadline, nil)
     |> assign(:subscribed_to_oauth, connected?(socket))}
  end

  @impl true
  def handle_event("change", %{"auth" => params}, socket) do
    {:noreply,
     socket
     |> assign(:name, Map.get(params, "name", socket.assigns.name))
     |> assign(:provider, parse_atom(Map.get(params, "provider")) || socket.assigns.provider)
     |> assign(:auth_type, parse_atom(Map.get(params, "auth_type")) || socket.assigns.auth_type)
     |> assign(:api_key, Map.get(params, "api_key", socket.assigns.api_key))
     |> assign(:user_project, Map.get(params, "user_project", socket.assigns.user_project))
     |> assign(:auth_code, Map.get(params, "auth_code", socket.assigns.auth_code))
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("generate_oauth_url", _params, socket) do
    # Ensure we are subscribed before launching external flow to avoid missing the event
    socket =
      if !socket.assigns.subscribed_to_oauth and connected?(socket) do
        TheMaestroWeb.Endpoint.subscribe("oauth:events")
        assign(socket, :subscribed_to_oauth, true)
      else
        socket
      end

    with :ok <- Provider.validate_session_name(socket.assigns.name),
         {:ok, {url, pkce}} <- oauth_url_for(socket.assigns.provider) do
      url_state = extract_state(url)

      socket =
        if socket.assigns.provider in [:openai, :gemini] and is_binary(url_state) do
          # Save mapping so callback server can complete flow
          TheMaestro.OAuthState.put(url_state, %{
            provider: socket.assigns.provider,
            session_name: socket.assigns.name,
            pkce_params: Map.new(pkce_to_kw(pkce))
          })

          # Ensure callback runtime is running with 180s timeout
          {:ok, %{port: port}} =
            TheMaestro.OAuthCallbackRuntime.ensure_started(timeout_ms: 180_000)

          Process.send_after(self(), :tick, 1000)

          socket
          |> assign(:callback_port, port)
          |> assign(:callback_listening, true)
          |> assign(
            :callback_deadline,
            System.monotonic_time(:millisecond) + 180_000
          )
        else
          socket
        end

      {:noreply,
       socket
       |> assign(:oauth_url, url)
       |> assign(:pkce_params, pkce)
       |> assign(:error, nil)}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def handle_event("create_api_key", _params, socket) do
    opts =
      case socket.assigns.provider do
        :gemini ->
          [
            name: socket.assigns.name,
            credentials: %{
              api_key: socket.assigns.api_key,
              user_project: blank_to_nil(socket.assigns.user_project)
            }
          ]

        _ ->
          [name: socket.assigns.name, credentials: %{api_key: socket.assigns.api_key}]
      end

    case Provider.create_session(socket.assigns.provider, :api_key, opts) do
      {:ok, _session} -> {:noreply, push_navigate(socket, to: ~p"/dashboard")}
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def handle_event("complete_oauth", _params, socket) do
    with :ok <- Provider.validate_session_name(socket.assigns.name),
         pkce when not is_nil(pkce) <-
           socket.assigns.pkce_params || {:error, "Generate the OAuth URL first"},
         code when is_binary(code) and code != "" <-
           socket.assigns.auth_code || {:error, "Enter the authorization code"},
         {:ok, _} <-
           Provider.create_session(socket.assigns.provider, :oauth,
             name: socket.assigns.name,
             pkce_params: Map.new(pkce_to_kw(pkce)),
             auth_code: code
           ) do
      {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
      msg when is_binary(msg) -> {:noreply, assign(socket, :error, msg)}
    end
  end

  @impl true
  def handle_event("restart_listener", _params, socket) do
    {:ok, %{port: port}} = TheMaestro.OAuthCallbackRuntime.ensure_started(timeout_ms: 180_000)
    Process.send_after(self(), :tick, 1000)

    {:noreply,
     socket
     |> assign(:callback_port, port)
     |> assign(:callback_listening, true)
     |> assign(:callback_deadline, System.monotonic_time(:millisecond) + 180_000)}
  end

  @impl true
  def handle_info(:tick, socket) do
    case socket.assigns.callback_deadline do
      nil ->
        {:noreply, socket}

      deadline ->
        now = System.monotonic_time(:millisecond)

        if now < deadline and socket.assigns.callback_listening do
          Process.send_after(self(), :tick, 1000)
          {:noreply, socket}
        else
          {:noreply, assign(socket, :callback_listening, false)}
        end
    end
  end

  @impl true
  def handle_info(%{topic: "oauth:events", event: "completed", payload: payload}, socket) do
    # Redirect on completion regardless of provider/name to avoid race/delivery timing issues
    {:noreply,
     socket
     |> put_flash(:info, "OAuth completed: #{payload["provider"]}/#{payload["session_name"]}")
     |> push_navigate(to: ~p"/dashboard")}
  end

  defp oauth_url_for(:openai), do: Auth.generate_openai_oauth_url()
  defp oauth_url_for(:anthropic), do: Auth.generate_oauth_url()
  defp oauth_url_for(:gemini), do: Auth.generate_gemini_oauth_url()

  defp pkce_to_kw(%Auth.PKCEParams{} = pkce),
    do: [
      code_verifier: pkce.code_verifier,
      code_challenge: pkce.code_challenge,
      code_challenge_method: pkce.code_challenge_method
    ]

  defp pkce_to_kw(%{code_verifier: v} = pkce),
    do: [
      code_verifier: v,
      code_challenge: Map.get(pkce, :code_challenge) || Map.get(pkce, "code_challenge"),
      code_challenge_method:
        Map.get(pkce, :code_challenge_method) || Map.get(pkce, "code_challenge_method")
    ]

  defp parse_atom(nil), do: nil
  defp parse_atom(val) when is_binary(val), do: String.to_existing_atom(val)
  defp parse_atom(val) when is_atom(val), do: val

  defp extract_state(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:query)
    |> Kernel.||("")
    |> URI.decode_query()
    |> Map.get("state")
  rescue
    _ -> nil
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; CREATE NEW AUTH &lt;&lt;&lt;
            </h1>
            <.link
              navigate={~p"/dashboard"}
              class="px-4 py-2 rounded transition-all duration-200 btn-amber"
              data-hotkey-seq="g d"
              data-hotkey-label="Go to Dashboard"
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
                  <input
                    name="auth[name]"
                    type="text"
                    value={@name}
                    placeholder="e.g. work_openai"
                    class="input-terminal"
                  />
                </div>
                <div>
                  <label class="block text-amber-400 mb-1">Provider</label>
                  <select name="auth[provider]" class="select-terminal" value={@provider}>
                    <%= for p <- @providers do %>
                      <option value={p} selected={@provider == p}>{p}</option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="block text-amber-400 mb-1">Auth Type</label>
                  <select name="auth[auth_type]" class="select-terminal" value={@auth_type}>
                    <%= for t <- @auth_types do %>
                      <option value={t} selected={@auth_type == t}>{t}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <%= if @auth_type == :api_key do %>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div class="sm:col-span-2">
                    <label class="block text-amber-400 mb-1">API Key</label>
                    <input
                      name="auth[api_key]"
                      type="password"
                      value={@api_key}
                      class="input-terminal"
                    />
                  </div>
                  <%= if @provider == :gemini do %>
                    <div class="sm:col-span-2">
                      <label class="block text-amber-400 mb-1">X-Goog-User-Project (optional)</label>
                      <input
                        name="auth[user_project]"
                        type="text"
                        value={@user_project}
                        class="input-terminal"
                        placeholder="billing-project-id"
                      />
                    </div>
                  <% end %>
                </div>
                <div class="mt-4">
                  <button type="button" phx-click="create_api_key" class="px-4 py-2 rounded btn-green">
                    Create
                  </button>
                </div>
              <% else %>
                <div class="space-y-3">
                  <div class="flex gap-2 items-end">
                    <button
                      type="button"
                      phx-click="generate_oauth_url"
                      class="px-3 py-2 rounded btn-amber"
                    >
                      Generate OAuth URL
                    </button>
                    <%= if @oauth_url do %>
                      <a href={@oauth_url} target="_blank" class="px-3 py-2 rounded btn-blue">
                        Open OAuth Page
                      </a>
                    <% end %>
                  </div>
                  <%= if @oauth_url && @provider == :openai do %>
                    <p class="text-sm opacity-80 text-amber-300">
                      <%= if @callback_listening do %>
                        Listening on <code>http://localhost:<%= @callback_port || 1455 %>/auth/callback</code>.
                        <%= if @callback_deadline do %>
                          Time remaining: {max(
                            div(@callback_deadline - System.monotonic_time(:millisecond), 1000),
                            0
                          )}s
                        <% end %>
                      <% else %>
                        Listener stopped.
                        <button
                          type="button"
                          class="btn btn-xs btn-amber"
                          phx-click="restart_listener"
                        >
                          Restart (180s)
                        </button>
                      <% end %>
                      <br />
                      After authorization, we will auto-complete and return you to the dashboard.
                    </p>
                  <% end %>
                  <%= if @oauth_url && @provider != :openai do %>
                    <div>
                      <label class="block text-amber-400 mb-1">Authorization Code</label>
                      <input
                        name="auth[auth_code]"
                        type="text"
                        value={@auth_code}
                        class="input-terminal"
                        placeholder="Paste code from provider callback"
                      />
                    </div>
                    <div class="mt-2">
                      <button
                        type="button"
                        phx-click="complete_oauth"
                        class="px-3 py-1 rounded btn-green"
                      >
                        Complete OAuth
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </.form>
        </div>
        <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
      </div>
    </Layouts.app>
    """
  end

  # assigns are set in mount
end

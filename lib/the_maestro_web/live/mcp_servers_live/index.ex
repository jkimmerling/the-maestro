defmodule TheMaestroWeb.MCPServersLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.MCP
  alias TheMaestro.MCP.Client, as: MCPClient
  alias TheMaestro.MCP.Servers
  alias TheMaestroWeb.MCPServersLive.FormComponent

  @impl true
  def mount(_params, _session, socket) do
    servers = MCP.list_servers_with_stats()

    {:ok,
     socket
     |> assign(:page_title, "MCP Hub")
     |> assign(:server, %Servers{})
     |> assign(:form_mode, :manual)
     |> assign(:stats, compute_stats(servers))
     |> stream(:servers, servers)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :new ->
        mode = params |> Map.get("mode", "manual") |> parse_mode()

        {:noreply,
         socket
         |> assign(:page_title, "New MCP Server")
         |> assign(:server, %Servers{})
         |> assign(:form_mode, mode)}

      :edit ->
        server = MCP.get_server!(params["id"], preload: [:session_servers])
        mode = server |> Map.get(:definition_source) |> parse_mode()

        {:noreply,
         socket
         |> assign(:page_title, "Edit MCP Server")
         |> assign(:server, server)
         |> assign(:form_mode, mode)}

      _ ->
        {:noreply,
         socket
         |> assign(:page_title, "MCP Hub")
         |> assign(:server, %Servers{})
         |> assign(:form_mode, :manual)}
    end
  end

  @impl true
  def handle_info({FormComponent, {:saved, server}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Saved #{server.display_name}.")
     |> close_modal()
     |> reload_servers()}
  end

  @impl true
  def handle_info({FormComponent, {:imported, message}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> close_modal()
     |> reload_servers()}
  end

  @impl true
  def handle_info({FormComponent, {:canceled, _server}}, socket) do
    {:noreply, close_modal(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    server = MCP.get_server!(id)
    {:ok, _} = MCP.delete_server(server)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted #{server.display_name}.")
     |> reload_servers()}
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    server = MCP.get_server!(id)
    {:ok, updated} = MCP.update_server(server, %{is_enabled: !server.is_enabled})

    if updated.is_enabled do
      # Warm tools cache when enabling a server
      Task.start(fn ->
        case MCP.Client.discover_server(updated) do
          {:ok, %{tools: tools}} ->
            ttl_ms =
              case updated.metadata do
                %{} = md -> (md["tool_cache_ttl_minutes"] || 60) * 60_000
                _ -> 60 * 60_000
              end

            _ = TheMaestro.MCP.ToolsCache.put(updated.id, tools, ttl_ms)
            :ok

          _ ->
            :ok
        end
      end)
    end

    {:noreply, reload_servers(socket)}
  end

  def handle_event("test", %{"id" => id}, socket) do
    server = MCP.get_server!(id)

    case MCPClient.discover_server(server) do
      {:ok, %{tools: tools}} ->
        ttl_ms =
          case server.metadata do
            %{} = md -> ((md["tool_cache_ttl_minutes"] || 60) |> to_int()) * 60_000
            _ -> 60 * 60_000
          end

        _ = TheMaestro.MCP.ToolsCache.put(server.id, tools, ttl_ms)
        {:noreply, socket |> put_flash(:info, format_test_success(server, tools))}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, format_test_error(server, reason))}
    end
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60

  defp close_modal(socket) do
    socket
    |> assign(:form_mode, :manual)
    |> push_patch(to: ~p"/mcp/servers")
  end

  defp reload_servers(socket) do
    servers = MCP.list_servers_with_stats()

    socket
    |> stream(:servers, servers, reset: true)
    |> assign(:stats, compute_stats(servers))
  end

  defp compute_stats(servers) do
    total = length(servers)
    enabled = Enum.count(servers, & &1.is_enabled)
    disabled = total - enabled
    attached = Enum.reduce(servers, 0, fn s, acc -> acc + (s.session_count || 0) end)

    %{total: total, enabled: enabled, disabled: disabled, attached: attached}
  end

  defp definition_source_label("cli"), do: "COMMAND / CLI"
  defp definition_source_label("json"), do: "JSON"
  defp definition_source_label("toml"), do: "TOML"
  defp definition_source_label(_), do: "MANUAL"

  defp parse_mode("cli"), do: :cli
  defp parse_mode("command"), do: :cli
  defp parse_mode("json"), do: :json
  defp parse_mode("toml"), do: :toml
  defp parse_mode(_), do: :manual

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page_title={@page_title}>
      <.header>
        MCP Hub
        <:actions>
          <.link patch={~p"/mcp/servers/new?mode=cli"} class="btn btn-soft btn-xs md:btn-sm">
            <.icon name="hero-arrow-down-tray" class="size-4" /> Import
          </.link>
          <.link patch={~p"/mcp/servers/new"} class="btn btn-primary btn-xs md:btn-sm">
            <.icon name="hero-plus" class="size-4" /> New Server
          </.link>
        </:actions>
      </.header>

      <section aria-labelledby="mcp-stats" class="mb-6">
        <h2 id="mcp-stats" class="sr-only">Hub statistics</h2>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card label="Total Servers" value={@stats.total} icon="hero-database" />
          <.stat_card label="Enabled" value={@stats.enabled} icon="hero-power" />
          <.stat_card label="Disabled" value={@stats.disabled} icon="hero-no-symbol" />
          <.stat_card label="Attached Sessions" value={@stats.attached} icon="hero-user-group" />
        </div>
      </section>

      <section aria-labelledby="servers-heading">
        <div class="flex items-center justify-between mb-2">
          <h2 id="servers-heading" class="text-base font-semibold">Persisted MCP Servers</h2>
          <span class="text-xs text-slate-500">Showing {@stats.total}</span>
        </div>

        <div
          id="mcp-server-list"
          class="space-y-3"
          phx-update="stream"
          role="list"
          aria-label="MCP servers"
        >
          <article
            :for={{id, server} <- @streams.servers}
            id={id}
            class="rounded-lg border border-slate-800 bg-slate-950/70 p-4 shadow-sm"
            role="listitem"
          >
            <div class="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <h3 class="text-lg font-semibold text-amber-200">{server.display_name}</h3>
                  <span
                    class={[
                      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
                      server.is_enabled && "bg-emerald-500/20 text-emerald-200",
                      !server.is_enabled && "bg-slate-700 text-slate-300"
                    ]}
                    aria-label={if(server.is_enabled, do: "Server enabled", else: "Server disabled")}
                  >
                    {if(server.is_enabled, do: "enabled", else: "disabled")}
                  </span>
                </div>
                <p :if={server.description} class="mt-1 text-sm text-slate-400">
                  {server.description}
                </p>
                <p class="text-[11px] uppercase tracking-[0.3em] text-slate-500">
                  Definition: {definition_source_label(server.definition_source)}
                </p>
                <dl class="mt-3 grid gap-2 text-xs text-slate-400 sm:grid-cols-2 lg:grid-cols-3">
                  <div>
                    <dt class="font-semibold text-slate-300">Transport</dt>
                    <dd class="mt-0.5 uppercase tracking-wide">{server.transport}</dd>
                  </div>
                  <div :if={server.url}>
                    <dt class="font-semibold text-slate-300">URL</dt>
                    <dd class="mt-0.5 break-all text-amber-200">{server.url}</dd>
                  </div>
                  <div :if={server.command}>
                    <dt class="font-semibold text-slate-300">Command</dt>
                    <dd class="mt-0.5 font-mono text-amber-200">{server.command}</dd>
                  </div>
                  <div>
                    <dt class="font-semibold text-slate-300">Arguments</dt>
                    <dd class="mt-0.5 font-mono">
                      {server
                      |> Map.get(:args, [])
                      |> Enum.join(" ")
                      |> blank_to_dash()}
                    </dd>
                  </div>
                  <div>
                    <dt class="font-semibold text-slate-300">Headers</dt>
                    <dd class="mt-0.5 font-mono">
                      {if map_size(server.headers || %{}) == 0 do
                        "—"
                      else
                        Enum.map_join(server.headers, ", ", fn {k, v} -> "#{k}=#{v}" end)
                      end}
                    </dd>
                  </div>
                  <div>
                    <dt class="font-semibold text-slate-300">Sessions</dt>
                    <dd class="mt-0.5 text-amber-200">{server.session_count || 0}</dd>
                  </div>
                </dl>
                <div :if={(server.tags || []) != []} class="mt-3 flex flex-wrap gap-1">
                  <span
                    :for={tag <- server.tags}
                    class="rounded-full border border-amber-500/40 px-2 py-0.5 text-[11px] uppercase tracking-wide text-amber-200"
                  >
                    {tag}
                  </span>
                </div>
              </div>
              <div class="flex flex-col items-stretch gap-2 md:w-40">
                <.link navigate={~p"/mcp/servers/#{server.id}"} class="btn btn-xs btn-soft w-full">
                  View
                </.link>
                <button
                  type="button"
                  class="btn btn-xs btn-soft w-full"
                  phx-click="test"
                  phx-value-id={server.id}
                >
                  Test
                </button>
                <button
                  type="button"
                  class="btn btn-xs w-full"
                  aria-pressed={server.is_enabled}
                  phx-click="toggle_enabled"
                  phx-value-id={server.id}
                >
                  {if(server.is_enabled, do: "Disable", else: "Enable")}
                </button>
                <.link patch={~p"/mcp/servers/#{server.id}/edit"} class="btn btn-xs btn-soft w-full">
                  Edit
                </.link>
                <button
                  type="button"
                  class="btn btn-xs btn-danger w-full"
                  data-confirm="Delete #{server.display_name}? This cannot be undone."
                  phx-click="delete"
                  phx-value-id={server.id}
                >
                  Delete
                </button>
              </div>
            </div>
          </article>
          <div
            :if={@stats.total == 0}
            id="mcp-server-empty"
            class="rounded border border-dashed border-slate-700 p-6 text-center text-sm text-slate-400"
          >
            No MCP servers yet. Import from CLI/JSON/TOML or create a new server to get started.
          </div>
        </div>
      </section>

      <.modal :if={@live_action in [:new, :edit]} id="mcp-server-modal">
        <.live_component
          module={FormComponent}
          id={@server.id || :new}
          title={@page_title}
          server={@server}
          action={@live_action}
          patch={~p"/mcp/servers"}
          mode={@form_mode}
          allow_import_tabs={true}
        />
      </.modal>
    </Layouts.app>
    """
  end

  defp format_test_success(server, tools) do
    names =
      tools
      |> Enum.map(&(&1["name"] || &1[:name]))
      |> Enum.reject(&(&1 in [nil, ""]))

    summary =
      case names do
        [] ->
          "No tools returned."

        [_] = list ->
          "Tools: " <> Enum.join(list, ", ")

        list when length(list) <= 3 ->
          "Tools: " <> Enum.join(list, ", ")

        list ->
          shown = Enum.take(list, 3)
          remaining = length(list) - 3
          "Tools: " <> Enum.join(shown, ", ") <> " (+" <> Integer.to_string(remaining) <> " more)"
      end

    "#{server.display_name}: #{summary}"
  end

  defp format_test_error(server, {:unsupported_transport, transport}) do
    "#{server.display_name}: Test failed – unsupported transport #{transport}."
  end

  defp format_test_error(server, :missing_base_url) do
    "#{server.display_name}: Test failed – missing base URL."
  end

  defp format_test_error(server, :missing_command) do
    "#{server.display_name}: Test failed – missing command for stdio transport."
  end

  defp format_test_error(server, reason) when is_binary(reason) do
    "#{server.display_name}: Test failed – #{reason}."
  end

  defp format_test_error(server, reason) do
    "#{server.display_name}: Test failed – #{inspect(reason)}."
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-slate-800 bg-slate-900/80 p-4">
      <div class="flex items-center gap-3">
        <.icon name={@icon} class="size-6 text-amber-300" />
        <div>
          <p class="text-xs uppercase tracking-wide text-slate-400">{@label}</p>
          <p class="text-xl font-semibold text-amber-100">{@value}</p>
        </div>
      </div>
    </div>
    """
  end

  defp blank_to_dash(value) when value in [nil, ""], do: "—"
  defp blank_to_dash(value), do: value
end

defmodule TheMaestroWeb.MCPServersLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.MCP

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    server = MCP.get_server!(id)
    sessions = MCP.list_server_sessions(id)

    {:ok,
     socket
     |> assign(:server, server)
     |> assign(:sessions, sessions)
     |> assign(:page_title, "MCP Hub")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    server = MCP.get_server!(id)
    sessions = MCP.list_server_sessions(id)

    {:noreply,
     socket
     |> assign(:server, server)
     |> assign(:sessions, sessions)}
  end

  @impl true
  def handle_event("toggle_enabled", _params, socket) do
    server = socket.assigns.server
    {:ok, updated} = MCP.update_server(server, %{is_enabled: !server.is_enabled})
    {:noreply, assign(socket, :server, updated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page_title={@page_title}>
      <.header>
        {@server.display_name}
        <:subtitle>
          <p class="text-xs uppercase tracking-[0.3em] text-slate-400">
            Canonical: {@server.name}
          </p>
        </:subtitle>
        <:actions>
          <.link navigate={~p"/mcp/servers/#{@server.id}/edit"} class="btn btn-soft btn-xs">
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.link>
          <button
            type="button"
            class="btn btn-soft btn-xs"
            phx-click="toggle_enabled"
          >
            {if @server.is_enabled, do: "Disable", else: "Enable"}
          </button>
        </:actions>
      </.header>

      <section class="mb-8 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          label="Transport"
          value={String.upcase(@server.transport)}
          icon="hero-arrows-right-left"
        />
        <.stat_card
          label="Status"
          value={if(@server.is_enabled, do: "ENABLED", else: "DISABLED")}
          icon="hero-bolt"
        />
        <.stat_card
          label="Definition"
          value={definition_source_label(@server.definition_source)}
          icon="hero-document-text"
        />
        <.stat_card label="Sessions Attached" value={length(@sessions)} icon="hero-user-group" />
      </section>

      <section class="mb-8 space-y-3">
        <h2 class="text-base font-semibold text-amber-200 uppercase tracking-[0.3em]">
          Connection Details
        </h2>
        <dl class="grid gap-4 rounded-lg border border-amber-500/30 bg-black/40 p-4 text-sm">
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">URL</dt>
            <dd class="font-mono text-amber-200 break-all">{@server.url || "—"}</dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Command</dt>
            <dd class="font-mono text-amber-200 break-all">{@server.command || "—"}</dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Arguments</dt>
            <dd>
              <pre phx-no-curly-interpolation class="whitespace-pre-wrap font-mono text-amber-200"><%= format_args(@server) %></pre>
            </dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Headers</dt>
            <dd>
              <pre phx-no-curly-interpolation class="whitespace-pre-wrap font-mono text-amber-200"><%= format_map_lines(@server.headers) %></pre>
            </dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Environment</dt>
            <dd>
              <pre phx-no-curly-interpolation class="whitespace-pre-wrap font-mono text-amber-200"><%= format_map_lines(@server.env) %></pre>
            </dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Metadata</dt>
            <dd>
              <pre phx-no-curly-interpolation class="whitespace-pre-wrap font-mono text-amber-200"><%= format_metadata(@server.metadata) %></pre>
            </dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Tags</dt>
            <dd class="font-mono text-amber-200">
              {if Enum.empty?(@server.tags || []), do: "—", else: Enum.join(@server.tags, ", ")}
            </dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Inserted</dt>
            <dd class="text-amber-200">{format_dt(@server.inserted_at)}</dd>
          </div>
          <div>
            <dt class="text-amber-400 uppercase text-xs tracking-[0.3em]">Updated</dt>
            <dd class="text-amber-200">{format_dt(@server.updated_at)}</dd>
          </div>
        </dl>
      </section>

      <section>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-base font-semibold text-amber-200 uppercase tracking-[0.3em]">
            Attached Sessions
          </h2>
          <span class="text-xs text-amber-300">{length(@sessions)} total</span>
        </div>
        <div
          :if={@sessions == []}
          class="rounded border border-amber-500/20 bg-black/40 p-6 text-sm text-amber-200"
        >
          No sessions currently use this MCP server.
        </div>
        <div :if={@sessions != []} class="space-y-3">
          <article
            :for={binding <- @sessions}
            class="rounded border border-amber-500/30 bg-black/50 p-4"
          >
            <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <div>
                <p class="text-amber-200 font-semibold">
                  Session {binding.session.name || binding.session.id}
                </p>
                <p class="text-xs text-amber-300 uppercase tracking-[0.3em]">
                  Auth: {(binding.session.saved_authentication &&
                            binding.session.saved_authentication.name) || "None"}
                </p>
              </div>
              <.link navigate={~p"/dashboard"} class="btn btn-xs btn-soft">
                Manage Session
              </.link>
            </div>
            <p class="mt-2 text-xs text-amber-300">
              Attached {format_dt(binding.attached_at)}
            </p>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")

  defp format_args(%{args: args}) when is_list(args) and args != [] do
    Enum.join(args, "\n")
  end

  defp format_args(_), do: "—"

  defp format_map_lines(map) when map in [%{}, nil], do: "—"

  defp format_map_lines(map) do
    map
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("\n")
  end

  defp format_metadata(map) when map in [%{}, nil], do: "—"

  defp format_metadata(map) do
    Jason.encode!(map, pretty: true)
  end

  defp definition_source_label("cli"), do: "COMMAND / CLI"
  defp definition_source_label("json"), do: "JSON"
  defp definition_source_label("toml"), do: "TOML"
  defp definition_source_label(_), do: "MANUAL"

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-amber-500/30 bg-black/40 p-4">
      <div class="flex items-center gap-3">
        <.icon name={@icon} class="size-6 text-amber-300" />
        <div>
          <p class="text-xs uppercase tracking-[0.3em] text-amber-300">{@label}</p>
          <p class="text-lg font-semibold text-amber-100">{@value}</p>
        </div>
      </div>
    </div>
    """
  end
end

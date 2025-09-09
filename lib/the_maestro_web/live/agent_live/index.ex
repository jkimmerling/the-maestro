defmodule TheMaestroWeb.AgentLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Agents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">&gt;&gt;&gt; AGENTS INDEX &lt;&lt;&lt;</h1>
            <.link navigate={~p"/agents/new"} class="px-4 py-2 rounded transition-all duration-200 btn-green" data-hotkey-seq="g a" data-hotkey-label="New Agent" data-hotkey="alt+a">
              <.icon name="hero-plus" class="inline mr-2 w-4 h-4" /> NEW AGENT
            </.link>
          </div>

          <div id="agents" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for {dom_id, agent} <- @streams.agents do %>
              <div id={dom_id} class="terminal-card terminal-border-green p-4">
                <div class="flex items-center justify-between">
                  <div class="text-lg font-bold text-green-300 glow">{agent.name}</div>
                  <div class="space-x-2">
                    <.link navigate={~p"/agents/#{agent}"} class="text-green-400 hover:text-green-300">
                      <.icon name="hero-eye" class="h-4 w-4" />
                    </.link>
                    <.link navigate={~p"/agents/#{agent}/edit"} class="text-blue-400 hover:text-blue-300">
                      <.icon name="hero-pencil-square" class="h-4 w-4" />
                    </.link>
                    <button phx-click={JS.push("delete", value: %{id: agent.id}) |> hide("##{dom_id}")} data-confirm="Are you sure?" class="text-red-400 hover:text-red-300">
                      <.icon name="hero-trash" class="h-4 w-4" />
                    </button>
                  </div>
                </div>
                <div class="mt-2 text-sm text-amber-200 space-y-1">
                  <div><span class="text-amber-300">Tools:</span> {inspect(map_size(agent.tools || %{}))}</div>
                  <div><span class="text-amber-300">MCPs:</span> {inspect(map_size(agent.mcps || %{}))}</div>
                </div>
                <div class="mt-3">
                  <.link navigate={~p"/agents/#{agent}"} class="px-3 py-1 rounded text-xs btn-amber">OPEN</.link>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Agents")
     |> stream(:agents, Agents.list_agents())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    agent = Agents.get_agent!(id)
    {:ok, _} = Agents.delete_agent(agent)

    {:noreply, stream_delete(socket, :agents, agent)}
  end
end

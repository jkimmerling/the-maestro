defmodule TheMaestroWeb.AgentLive.Show do
  use TheMaestroWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">&gt;&gt;&gt; AGENT {@agent.id} &lt;&lt;&lt;</h1>
            <div class="space-x-2">
              <.link navigate={~p"/agents"} class="px-3 py-1 rounded btn-amber" data-hotkey-seq="g i" data-hotkey-label="Agents Index">
                <.icon name="hero-arrow-left" class="inline mr-1 w-4 h-4" /> BACK
              </.link>
              <.link navigate={~p"/agents/#{@agent}/edit?return_to=show"} class="px-3 py-1 rounded btn-blue" data-hotkey-seq="g e" data-hotkey-label="Edit Agent">
                <.icon name="hero-pencil-square" class="inline mr-1 w-4 h-4" /> EDIT
              </.link>
            </div>
          </div>

          <div class="terminal-card terminal-border-green p-6 space-y-3">
            <div><b class="text-amber-300">Name:</b> {@agent.name}</div>
            <div>
              <b class="text-amber-300">Auth:</b>
              <%= if @agent.saved_authentication do %>
                {@agent.saved_authentication.name} ({@agent.saved_authentication.provider}/{@agent.saved_authentication.auth_type})
              <% else %>
                —
              <% end %>
            </div>
            <div>
              <b class="text-amber-300">Tools:</b>
              <pre class="text-xs text-amber-200">{inspect(@agent.tools || %{}, pretty: true, limit: :infinity)}</pre>
            </div>
            <div>
              <b class="text-amber-300">MCPs:</b>
              <pre class="text-xs text-amber-200">{inspect(@agent.mcps || %{}, pretty: true, limit: :infinity)}</pre>
            </div>
            <div>
              <b class="text-amber-300">Memory:</b>
              <pre class="text-xs text-amber-200">{inspect(@agent.memory || %{}, pretty: true, limit: :infinity)}</pre>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Agent")
     |> assign(
       :agent,
       TheMaestro.Repo.get!(TheMaestro.Agents.Agent, id)
       |> TheMaestro.Repo.preload([:saved_authentication, :base_system_prompt, :persona])
     )}
  end
end

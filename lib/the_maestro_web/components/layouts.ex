defmodule TheMaestroWeb.Layouts do
  use TheMaestroWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :page_title, :string, default: nil
  attr :main_class, :string, default: "px-4 py-20 sm:px-6 lg:px-8"
  attr :container_class, :string, default: "mx-auto max-w-2xl space-y-4"
  attr :show_header, :boolean, default: true

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="app-root" phx-hook="GlobalHotkeys" class="min-h-screen bg-black text-amber-400 font-mono">
      <div class="crt-overlay"></div>
      <header
        :if={@show_header}
        class="px-6 py-8"
      >
        <div class="flex justify-between items-center mb-8 border-b border-amber-600 pb-4 relative">
          <h1 class="text-4xl font-bold text-amber-400 glow tracking-wider">
            {page_title_banner(@page_title)}
          </h1>
          <div class="relative">
            <button
              id="global-nav-toggle"
              type="button"
              class="bg-amber-600/20 hover:bg-amber-600/40 border border-amber-500 text-amber-400 px-4 py-2 rounded transition-all duration-200 hover:glow-strong"
              data-target="global-nav-dropdown"
              phx-hook="HamburgerToggle"
            >
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </button>

            <%!-- Hamburger Menu Dropdown --%>
            <div
              id="global-nav-dropdown"
              class="hidden absolute right-0 top-full mt-2 w-48 bg-black border border-amber-500 rounded-lg shadow-lg z-50"
            >
              <div class="py-2">
                <.terminal_nav_item navigate={~p"/dashboard"} icon="hero-home">
                  Dashboard
                </.terminal_nav_item>
                <.terminal_nav_item navigate={~p"/mcp/servers"} icon="hero-cpu-chip">
                  MCP Hub
                </.terminal_nav_item>
                <.terminal_nav_item navigate={~p"/supplied_context"} icon="hero-archive-box">
                  Context Library
                </.terminal_nav_item>
                <.terminal_nav_item navigate={~p"/chat_history"} icon="hero-clock">
                  Chat Histories
                </.terminal_nav_item>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main class={@main_class}>
        <div class={@container_class}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
      <button
        id="shortcuts-hint"
        phx-hook="ShortcutsHint"
        aria-label="Show shortcuts"
        class="fixed bottom-3 right-3 z-50 px-2 py-1 rounded text-xs btn-amber opacity-60 hover:opacity-100"
      >
        ?
      </button>
    </div>
    """
  end

  defp page_title_banner(nil), do: ">>> THE MAESTRO <<<"

  defp page_title_banner(title) do
    formatted =
      title
      |> to_string()
      |> String.trim()
      |> String.upcase()

    ">>> #{formatted} <<<"
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-amber-400/30 bg-black/60 rounded-full px-1 py-1">
      <button
        class="flex items-center justify-center rounded-full px-2 py-1 text-[10px] uppercase tracking-[0.4em] text-amber-300 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        SYS
      </button>
      <button
        class="flex items-center justify-center rounded-full px-2 py-1 text-[10px] uppercase tracking-[0.4em] text-amber-300 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        ☀︎
      </button>
      <button
        class="flex items-center justify-center rounded-full px-2 py-1 text-[10px] uppercase tracking-[0.4em] text-amber-300 hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        ☾
      </button>
    </div>
    """
  end

  attr :navigate, :any, required: true
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-2 rounded-md px-3 py-1.5 text-slate-200 transition hover:bg-amber-500/15 hover:text-amber-200"
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      <span>{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  attr :navigate, :any, required: true
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  defp terminal_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-3 px-4 py-2 text-amber-300 hover:bg-amber-500/20 hover:text-amber-100 transition"
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      <span class="uppercase tracking-[0.35em] text-xs">{render_slot(@inner_block)}</span>
    </.link>
    """
  end
end

defmodule TheMaestroWeb.ShortcutsOverlay do
  use TheMaestroWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, visible: false, items: [])}
  end

  @impl true
  def update(assigns, socket) do
    # Preserve :id and any other structural assigns; apply provided visibility/items
    {:ok,
     assign(socket, assigns)
     |> assign_new(:visible, fn -> false end)
     |> assign_new(:items, fn -> [] end)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, update(socket, :visible, &(!&1))}
  end

  def handle_event("set", %{"items" => items}, socket) when is_list(items) do
    norm =
      Enum.map(items, fn item ->
        %{
          combo: (item["combo"] || item[:combo] || "") |> to_string(),
          label: (item["label"] || item[:label] || "") |> to_string()
        }
      end)
      |> Enum.uniq()

    {:noreply, assign(socket, :items, norm)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id <> "-root"} style="display: contents">
      <.modal :if={@visible} id="hotkeys-modal">
        <div class="terminal-card terminal-border-amber p-4">
          <h3 class="text-xl font-bold text-amber-400 mb-3 glow">KEYBOARD SHORTCUTS</h3>
          <div class="text-amber-300 text-sm mb-2">Press Esc or click outside to close</div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <%= for item <- @items do %>
              <div class="flex items-start gap-3">
                <code class="px-2 py-0.5 rounded bg-amber-600/10 border border-amber-600 text-amber-300">
                  {item.combo}
                </code>
                <div class="text-amber-200 text-sm">{item.label}</div>
              </div>
            <% end %>
            <%= if @items == [] do %>
              <div class="text-amber-300">No shortcuts found on this page.</div>
            <% end %>
          </div>
        </div>
      </.modal>
    </div>
    """
  end
end

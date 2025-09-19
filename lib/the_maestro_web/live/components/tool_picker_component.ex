defmodule TheMaestroWeb.ToolPickerComponent do
  use TheMaestroWeb, :live_component

  alias TheMaestro.Tools.Inventory

  @moduledoc """
  Tool Picker UI component.

  Props:
    - provider: :openai | :anthropic | :gemini
    - session_id: session uuid or nil (nil => built-ins only)
    - allowed_by_provider: %{provider_atom => [names]}
    - inventory_by_provider: %{provider_atom => [Inventory.item]}

  Emits events to parent LiveView:
    - "tool_picker:toggle" with provider + name
    - "tool_picker:select_all" with provider
    - "tool_picker:select_none" with provider
  """

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> ensure_inventory()
     |> assign_new(:allowed_by_provider, fn -> %{} end)}
  end

  defp ensure_inventory(%{assigns: assigns} = socket) do
    inv =
      assigns[:inventory_by_provider] ||
        %{
          openai: Inventory.list_for_provider(assigns[:session_id], :openai),
          anthropic: Inventory.list_for_provider(assigns[:session_id], :anthropic),
          gemini: Inventory.list_for_provider(assigns[:session_id], :gemini)
        }

    assign(socket, :inventory_by_provider, inv)
  end

  @impl true
  attr :show_groups, :list, default: [:builtin, :mcp]
  attr :dom_id_suffix, :string, default: nil
  attr :warming, :boolean, default: false
  attr :title, :string, default: "Tools"
  attr :target, :any, default: nil
  # Controls top spacing. Keep true by default for legacy placements.
  attr :top_margin, :boolean, default: true

  def render(assigns) do
    ~H"""
    <div
      id={dom_id("tool-picker-" <> Atom.to_string(@provider), @dom_id_suffix)}
      class={[@top_margin && "mt-6"]}
    >
      <% scope =
        case @show_groups do
          [:mcp] -> "mcp"
          [:builtin] -> "builtin"
          _ -> "all"
        end %>
      <div class="flex items-center justify-between mb-2">
        <div class="text-xs font-semibold uppercase tracking-wide">{@title}</div>
        <div class="space-x-2">
          <button
            type="button"
            class="btn btn-xs"
            phx-click="tool_picker:select_all"
            phx-value-provider={@provider}
            phx-target={@target}
            phx-value-source={scope}
          >
            All
          </button>
          <button
            type="button"
            class="btn btn-xs"
            phx-click="tool_picker:select_none"
            phx-value-provider={@provider}
            phx-target={@target}
            phx-value-source={scope}
          >
            None
          </button>
        </div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
        <% grouped_tools = group_by_source(@inventory_by_provider[@provider] || []) %>
        <%= for source <- @show_groups do %>
          <div
            id={dom_id("tool-group-#{@provider}-#{source}", @dom_id_suffix)}
            class="rounded border border-base-300 p-2"
          >
            <div class="text-[11px] uppercase tracking-wide opacity-70 mb-1">
              {if source == :builtin, do: "Built-in", else: "MCP"}
            </div>

            <%= if source == :mcp do %>
              <% per_server =
                Enum.group_by(
                  Map.get(grouped_tools, :mcp, []),
                  fn item -> Map.get(item, :server_label) || "MCP" end
                ) %>
              <div class="space-y-2">
                <div :if={Map.keys(per_server) == [] and @warming} class="text-xs opacity-70 italic">
                  <span class="animate-pulse">Warming cache…</span>
                </div>
                <div :for={{label, items} <- per_server} class="">
                  <div class="flex items-center justify-between text-xs font-semibold">
                    <span class="opacity-80">{label}</span>
                    <span class="rounded-full bg-slate-700 px-2 py-0.5 text-[10px]">
                      {length(items)}
                    </span>
                  </div>
                  <div class="mt-1 space-y-1">
                    <label
                      :for={item <- items}
                      id={dom_id("tool-#{@provider}-#{item.name}", @dom_id_suffix)}
                      class="flex items-center gap-2 text-sm"
                    >
                      <input
                        type="checkbox"
                        checked={
                          selected?(
                            @allowed_by_provider,
                            @provider,
                            item.name,
                            @inventory_by_provider
                          )
                        }
                        phx-click="tool_picker:toggle"
                        phx-target={@target}
                        phx-value-provider={@provider}
                        phx-value-name={item.name}
                      />
                      <span class="truncate">
                        <span class="font-mono text-xs">{item.name}</span>
                        <%= if item.description do %>
                          <span class="ml-1 text-[11px] opacity-70">— {item.description}</span>
                        <% end %>
                      </span>
                    </label>
                  </div>
                </div>
                <div :if={Map.get(grouped_tools, :mcp, []) == []} class="text-xs opacity-60 italic">
                  No tools
                </div>
              </div>
            <% else %>
              <div class="space-y-1">
                <%= for item <- Map.get(grouped_tools, :builtin, []) do %>
                  <label
                    id={dom_id("tool-#{@provider}-#{item.name}", @dom_id_suffix)}
                    class="flex items-center gap-2 text-sm"
                  >
                    <input
                      type="checkbox"
                      checked={
                        selected?(@allowed_by_provider, @provider, item.name, @inventory_by_provider)
                      }
                      phx-click="tool_picker:toggle"
                      phx-target={@target}
                      phx-value-provider={@provider}
                      phx-value-name={item.name}
                    />
                    <span class="truncate">
                      <span class="font-mono text-xs">{item.name}</span>
                      <%= if item.description do %>
                        <span class="ml-1 text-[11px] opacity-70">— {item.description}</span>
                      <% end %>
                    </span>
                  </label>
                <% end %>
                <div
                  :if={Map.get(grouped_tools, :builtin, []) == []}
                  class="text-xs opacity-60 italic"
                >
                  No tools
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
      <p class="mt-2 text-[11px] opacity-70">
        If no selection is saved for a provider, all tools are exposed by default.
      </p>
    </div>
    """
  end

  defp selected?(allowed_by_provider, provider, name, inv_by_provider) do
    case Map.fetch(allowed_by_provider || %{}, provider) do
      {:ok, list} when is_list(list) ->
        name in list

      _ ->
        # Default to all selected if nothing persisted
        names = Enum.map(inv_by_provider[provider] || [], & &1.name)
        name in names
    end
  end

  defp group_by_source(list) do
    Enum.group_by(list, & &1.source)
  end

  defp dom_id(base, nil), do: base
  defp dom_id(base, suffix) when is_binary(suffix), do: base <> "-" <> suffix
end

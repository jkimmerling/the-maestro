defmodule TheMaestroWeb.SessionFormComponent do
  use TheMaestroWeb, :live_component

  alias TheMaestro.MCP
  alias TheMaestro.MCP.ToolsCache
  alias TheMaestro.Tools.Inventory

  @moduledoc """
  Shared inner sections for the Session form modal used by both Edit (Chat)
  and Create (Dashboard). Keeps layout/UI identical to Edit, with a `:mode`
  flag to toggle optional blocks and field names.

  Props:
    - mode: :edit | :create
    - prompt_picker_provider
    - session_prompt_builder
    - prompt_library
    - prompt_picker_selection
    - ui_sections (%{prompt: boolean, persona: boolean, memory: boolean})
    - For persona (create): persona_options; (edit): config_persona_options
    - For memory/persona values: config_form (edit) or session_form (create)
    - MCP: mcp_server_options, session_mcp_selected_ids, mcp_warming
    - Tools: tool_picker_allowed, tool_inventory_by_provider
  """

  # attrs declared before render/1 only

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> ensure_state()

    {:ok, socket}
  end

  defp ensure_state(%{assigns: assigns} = socket) do
    ui = Map.get(assigns, :ui_sections) || %{prompt: true, persona: true, memory: true}

    inv =
      if map_size(assigns[:tool_inventory_by_provider] || %{}) > 0 do
        assigns.tool_inventory_by_provider
      else
        build_initial_inventory(assigns)
      end

    allowed = assigns[:tool_picker_allowed] || %{}

    socket
    |> assign(:ui_sections, ui)
    |> assign(:tool_inventory_by_provider, inv)
    |> assign(:tool_picker_allowed, allowed)
    |> assign(:session_mcp_selected_ids, assigns[:session_mcp_selected_ids] || [])
    |> assign(:mcp_warming, assigns[:mcp_warming] || false)
  end

  defp build_initial_inventory(%{mode: :edit, config_form: %{"session_id" => sid}})
       when is_binary(sid) do
    %{
      openai: Inventory.list_for_provider(sid, :openai),
      anthropic: Inventory.list_for_provider(sid, :anthropic),
      gemini: Inventory.list_for_provider(sid, :gemini)
    }
  end

  defp build_initial_inventory(%{mode: :create, session_mcp_selected_ids: ids}) do
    ids = Enum.map(List.wrap(ids), &to_string/1)

    %{
      openai: Inventory.list_for_provider_with_servers(ids, :openai),
      anthropic: Inventory.list_for_provider_with_servers(ids, :anthropic),
      gemini: Inventory.list_for_provider_with_servers(ids, :gemini)
    }
  end

  defp build_initial_inventory(_), do: %{}

  # Props for render/1 (function component inside LiveComponent module)
  attr :mode, :atom, required: true
  attr :prompt_picker_provider, :atom, required: true
  attr :session_prompt_builder, :map, default: %{}
  attr :prompt_library, :map, default: %{}
  attr :prompt_picker_selection, :map, default: %{}
  attr :ui_sections, :map, default: %{prompt: true, persona: true, memory: true}
  # Persona/memory sources
  attr :config_persona_options, :list, default: []
  attr :persona_options, :list, default: []
  attr :config_form, :map, default: %{}
  attr :session_form, :any, default: nil
  # MCP + tools
  attr :mcp_server_options, :list, default: []
  attr :session_mcp_selected_ids, :list, default: []
  attr :mcp_warming, :boolean, default: false
  attr :tool_picker_allowed, :map, default: %{}
  attr :tool_inventory_by_provider, :map, default: %{}
  # Provider for child pickers
  attr :provider, :atom, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <!-- System Prompts (collapsible) -->
      <div class="md:col-span-2" id="section-system-prompts">
        <div class="flex items-center justify-between">
          <label class="text-xs font-semibold uppercase tracking-wide">System Prompts</label>
          <button
            type="button"
            class="btn btn-xs relative z-20"
            phx-click={
              JS.push("toggle_section", target: @myself, value: %{name: "prompt"})
              |> JS.toggle(to: "#section-system-prompts-content")
            }
            id="toggle-prompt"
          >
            <.icon
              name={
                (Map.get(@ui_sections, :prompt, true) && "hero-chevron-right") || "hero-chevron-down"
              }
              class="h-3.5 w-3.5"
            />
            <span class="ml-1">
              {(Map.get(@ui_sections, :prompt, true) && "Expand") || "Collapse"}
            </span>
          </button>
        </div>
        <div
          id="section-system-prompts-content"
          class={["mt-2", Map.get(@ui_sections, :prompt, true) && "hidden"]}
        >
          <.live_component
            module={TheMaestroWeb.SystemPromptPickerComponent}
            id={if @mode == :edit, do: "session-config-prompt-picker", else: "session-prompt-picker"}
            providers={[:openai, :anthropic, :gemini]}
            active_provider={@prompt_picker_provider}
            selected_by_provider={@session_prompt_builder}
            library_by_provider={@prompt_library}
            selections={@prompt_picker_selection}
            disabled={false}
          />
        </div>
      </div>
      
    <!-- Persona (collapsible) -->
      <div class="md:col-span-2 mt-4" id="section-persona">
        <div class="flex items-center justify-between">
          <label class="text-xs font-semibold uppercase tracking-wide">Persona</label>
          <button
            type="button"
            class="btn btn-xs relative z-20"
            phx-click={
              JS.push("toggle_section", target: @myself, value: %{name: "persona"})
              |> JS.toggle(to: "#section-persona-content")
            }
            id="toggle-persona"
          >
            <.icon
              name={
                (Map.get(@ui_sections, :persona, true) && "hero-chevron-right") || "hero-chevron-down"
              }
              class="h-3.5 w-3.5"
            />
            <span class="ml-1">
              {(Map.get(@ui_sections, :persona, true) && "Expand") || "Collapse"}
            </span>
          </button>
        </div>
        <div
          id="section-persona-content"
          class={["mt-2 space-y-2", Map.get(@ui_sections, :persona, true) && "hidden"]}
        >
          <%= if @mode == :edit do %>
            <div class="flex gap-2 items-center">
              <select name="persona_id" class="input">
                <option value="">(custom JSON)</option>
                <%= for {label, id} <- (@config_persona_options || []) do %>
                  <option value={id} selected={to_string(id) == to_string(@config_form["persona_id"])}>
                    {label}
                  </option>
                <% end %>
              </select>
              <button type="button" class="btn btn-xs" phx-click="open_persona_modal">
                Add Persona…
              </button>
            </div>
            <div>
              <label class="text-xs">Persona (JSON)</label>
              <textarea name="persona_json" rows="3" class="textarea-terminal"><%= @config_form["persona_json"] || Jason.encode!(@config_form["persona"] || %{}) %></textarea>
            </div>
          <% else %>
            <.input
              field={@session_form[:persona_id]}
              type="select"
              label="Persona"
              options={@persona_options}
              prompt="(optional)"
            />
          <% end %>
        </div>
      </div>
      
    <!-- Memory (collapsible) -->
      <div class="md:col-span-2 mt-4" id="section-memory">
        <div class="flex items-center justify-between">
          <label class="text-xs font-semibold uppercase tracking-wide">Memory</label>
          <button
            type="button"
            class="btn btn-xs relative z-20"
            phx-click={
              JS.push("toggle_section", target: @myself, value: %{name: "memory"})
              |> JS.toggle(to: "#section-memory-content")
            }
            id="toggle-memory"
          >
            <.icon
              name={
                (Map.get(@ui_sections, :memory, true) && "hero-chevron-right") || "hero-chevron-down"
              }
              class="h-3.5 w-3.5"
            />
            <span class="ml-1">
              {(Map.get(@ui_sections, :memory, true) && "Expand") || "Collapse"}
            </span>
          </button>
        </div>
        <div
          id="section-memory-content"
          class={["mt-2", Map.get(@ui_sections, :memory, true) && "hidden"]}
        >
          <%= if @mode == :edit do %>
            <label class="text-xs">Memory (JSON)</label>
            <textarea name="memory_json" rows="3" class="textarea-terminal"><%= @config_form["memory_json"] || Jason.encode!(@config_form["memory"] || %{}) %></textarea>
            <div class="mt-1">
              <button type="button" class="btn btn-xs" phx-click="open_memory_modal">
                Open Advanced Editor…
              </button>
            </div>
          <% else %>
            <label class="text-xs">Memory (JSON)</label>
            <textarea name="session[memory_json]" rows="3" class="textarea-terminal"></textarea>
          <% end %>
        </div>
      </div>
      
    <!-- Built-in Tools -->
      <div class="md:col-span-2 mt-4">
        <.live_component
          module={TheMaestroWeb.ToolPickerComponent}
          id={if @mode == :edit, do: "session-tool-picker", else: "new-session-tool-picker"}
          provider={@provider}
          session_id={if @mode == :edit, do: @config_form["session_id"], else: nil}
          allowed_by_provider={@tool_picker_allowed || %{}}
          inventory_by_provider={@tool_inventory_by_provider || %{}}
          target={@myself}
          show_groups={[:builtin]}
        />
      </div>
      
    <!-- MCPs Container -->
      <div class="md:col-span-2 mt-4">
        <label class="text-xs font-semibold uppercase tracking-wide">MCPs</label>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 items-start mt-2">
          <!-- Left column: Servers (checkboxes) -->
          <div>
            <div class="text-xs font-semibold uppercase tracking-wide">Servers</div>
            <div class="mt-2 space-y-1" id="mcp-server-checkboxes">
              <label
                :for={{label, id} <- @mcp_server_options || []}
                class="flex items-center gap-2 text-sm"
                id={"mcp-server-" <> to_string(id)}
              >
                <input
                  type="checkbox"
                  phx-click="toggle_mcp_server"
                  phx-target={@myself}
                  phx-value-id={id}
                  checked={to_string(id) in Enum.map(@session_mcp_selected_ids || [], &to_string/1)}
                />
                <span class="truncate">{label}</span>
              </label>
            </div>
            <p class="mt-2 text-[11px] text-slate-400">
              Select one or more connectors to use for this session. Disabled entries appear with a badge.
            </p>
            <button type="button" class="btn btn-xs mt-2" phx-click="open_mcp_modal">
              <.icon name="hero-plus" class="h-4 w-4" />
              <span class="ml-1">New</span>
            </button>
          </div>
          <!-- Right column: MCP TOOLS -->
          <div>
            <.live_component
              module={TheMaestroWeb.ToolPickerComponent}
              id={
                if @mode == :edit, do: "session-tool-picker-mcp", else: "new-session-tool-picker-mcp"
              }
              provider={@provider}
              session_id={if @mode == :edit, do: @config_form["session_id"], else: nil}
              allowed_by_provider={@tool_picker_allowed || %{}}
              inventory_by_provider={@tool_inventory_by_provider || %{}}
              show_groups={[:mcp]}
              warming={@mcp_warming}
              dom_id_suffix="mcp"
              title="MCP TOOLS"
              top_margin={false}
              target={@myself}
            />
          </div>
        </div>
      </div>
      
    <!-- Hidden fields kept in-sync for saving on both modals -->
      <input
        type="hidden"
        name={if @mode == :edit, do: "tools_json", else: "session[tools_json]"}
        value={encode_tools_json(@tool_picker_allowed)}
      />

      <%= for id <- @session_mcp_selected_ids || [] do %>
        <input
          type="hidden"
          name={if @mode == :edit, do: "mcp_server_ids[]", else: "session[mcp_server_ids][]"}
          value={id}
        />
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_section", %{"name" => name}, socket) do
    sections = socket.assigns[:ui_sections] || %{}

    updated =
      case name do
        "prompt" -> Map.put(sections, :prompt, !Map.get(sections, :prompt, true))
        "persona" -> Map.put(sections, :persona, !Map.get(sections, :persona, true))
        "memory" -> Map.put(sections, :memory, !Map.get(sections, :memory, true))
        _ -> sections
      end

    {:noreply, assign(socket, :ui_sections, updated)}
  end

  def handle_event("toggle_mcp_server", %{"id" => id}, socket) do
    id = to_string(id)
    selected0 = socket.assigns[:session_mcp_selected_ids] || []
    selected = if id in selected0, do: Enum.reject(selected0, &(&1 == id)), else: [id | selected0]
    selected = Enum.uniq(Enum.map(selected, &to_string/1))

    comp_id = socket.assigns.id

    Task.start(fn ->
      warm_mcp_tools_cache(selected)
      inv = build_tool_inventory_for_servers(selected)

      Phoenix.LiveView.send_update(__MODULE__,
        id: comp_id,
        tool_inventory_by_provider: inv,
        mcp_warming: false
      )
    end)

    inv = build_tool_inventory_for_servers(selected)

    send(self(), {:session_mcp_selected_ids, selected})

    {:noreply,
     assign(socket,
       session_mcp_selected_ids: selected,
       tool_inventory_by_provider: inv,
       mcp_warming: true
     )}
  end

  def handle_event("tool_picker:toggle", %{"provider" => prov_param, "name" => name}, socket) do
    provider = to_provider(prov_param) || socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])
    all_names = Enum.map(inv, & &1.name)

    current =
      case Map.get(allowed0, provider) do
        l when is_list(l) -> l
        _ -> all_names
      end

    desired =
      if name in current,
        do: Enum.reject(current, &(&1 == name)),
        else: Enum.uniq([name | current])

    {:noreply, assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))}
  end

  def handle_event("tool_picker:select_all", %{"provider" => prov_param} = params, socket) do
    provider = to_provider(prov_param) || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])
    target = names_for_source(inv, Map.get(params, "source", "all"))
    current_all_names = Enum.map(inv, & &1.name)

    current =
      case Map.get(allowed0, provider) do
        l when is_list(l) -> l
        _ -> current_all_names
      end

    desired = Enum.uniq(current ++ target)
    {:noreply, assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))}
  end

  def handle_event("tool_picker:select_none", %{"provider" => prov_param} = params, socket) do
    provider = to_provider(prov_param) || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])
    target = names_for_source(inv, Map.get(params, "source", "all"))
    current_all_names = Enum.map(inv, & &1.name)

    current =
      case Map.get(allowed0, provider) do
        l when is_list(l) -> l
        _ -> current_all_names
      end

    desired = Enum.reject(current, &(&1 in target))
    {:noreply, assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))}
  end

  defp to_provider(p) when is_atom(p), do: p

  defp to_provider(p) when is_binary(p) do
    case Enum.find(TheMaestro.Provider.list_providers(), fn pr -> Atom.to_string(pr) == p end) do
      nil -> :openai
      atom -> atom
    end
  end

  defp to_provider(_), do: :openai

  defp names_for_source(inv, "builtin"),
    do: inv |> Enum.filter(&(&1.source == :builtin)) |> Enum.map(& &1.name)

  defp names_for_source(inv, "mcp"),
    do: inv |> Enum.filter(&(&1.source == :mcp)) |> Enum.map(& &1.name)

  defp names_for_source(inv, _), do: Enum.map(inv, & &1.name)

  # Inventory building and warming helpers
  defp build_tool_inventory_for_servers(server_ids) do
    %{
      openai: Inventory.list_for_provider_with_servers(server_ids, :openai),
      anthropic: Inventory.list_for_provider_with_servers(server_ids, :anthropic),
      gemini: Inventory.list_for_provider_with_servers(server_ids, :gemini)
    }
  end

  defp warm_mcp_tools_cache(server_ids) do
    Enum.each(server_ids, &warm_single_cache/1)
  end

  defp warm_single_cache(sid) do
    case ToolsCache.get(sid, 60 * 60_000) do
      {:ok, _} -> :ok
      _ -> discover_and_cache_tools(sid)
    end
  end

  defp discover_and_cache_tools(sid) do
    server = MCP.get_server!(sid)

    case MCP.Client.discover_server(server) do
      {:ok, %{tools: tools}} -> cache_discovered_tools(sid, server, tools)
      _ -> :ok
    end
  end

  defp cache_discovered_tools(sid, server, tools) do
    ttl_ms = calculate_cache_ttl(server.metadata)
    _ = ToolsCache.put(sid, tools, ttl_ms)
    :ok
  end

  defp calculate_cache_ttl(%{} = metadata),
    do: to_int(metadata["tool_cache_ttl_minutes"] || 60) * 60_000

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60

  defp encode_tools_json(%{} = allowed) do
    if map_size(allowed) == 0 do
      ""
    else
      m =
        Enum.into(allowed, %{}, fn {prov, list} ->
          {Atom.to_string(prov), Enum.map(list, &to_string/1)}
        end)

      Jason.encode!(%{"allowed" => m})
    end
  end
end

defmodule TheMaestroWeb.SessionFormComponent do
  require Logger

  use TheMaestroWeb, :live_component

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
    |> assign(:mcp_expanded_servers, assigns[:mcp_expanded_servers] || MapSet.new())
    |> assign(:mcp_server_tools, assigns[:mcp_server_tools] || %{})
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

    # Build inventory from cache (Inventory module now handles stale data automatically)
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
        <label class="text-xs font-semibold uppercase tracking-wide">MCP Servers</label>
        <div class="w-full md:w-[90%] mx-auto mt-2">
          <div class="space-y-2" id="mcp-server-list">
            <%= for {label, id} <- (@mcp_server_options || []) do %>
              <% server_id = to_string(id) %>
              <% is_selected = server_id in Enum.map(@session_mcp_selected_ids || [], &to_string/1) %>
              <% is_expanded = MapSet.member?(@mcp_expanded_servers, server_id) %>
              <% server_tools = get_server_tools(@tool_inventory_by_provider, @provider, label) %>
              <% available_tools =
                get_available_tools_for_server(@tool_inventory_by_provider, @provider, server_id) %>
              <% selected_tools = get_selected_tools(@tool_picker_allowed, @provider, server_tools) %>
              <% some_tools_selected =
                length(selected_tools) > 0 && length(selected_tools) < length(server_tools) %>

              <div class="border border-base-300 rounded-lg p-3" id={"mcp-server-" <> server_id}>
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <!-- Expand/Collapse Arrow -->
                    <button
                      type="button"
                      class="btn btn-xs btn-ghost p-0 w-6 h-6"
                      phx-click="toggle_mcp_expand"
                      phx-target={@myself}
                      phx-value-id={server_id}
                      disabled={length(server_tools) == 0}
                    >
                      <.icon
                        name={if is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
                        class="h-4 w-4"
                      />
                    </button>
                    
    <!-- Server Checkbox -->
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        type="checkbox"
                        phx-click="toggle_mcp_server"
                        phx-target={@myself}
                        phx-value-id={server_id}
                        checked={is_selected}
                        indeterminate={some_tools_selected}
                        class={[
                          some_tools_selected && "indeterminate:bg-blue-500"
                        ]}
                      />
                      <span class="text-sm font-medium">{label}</span>
                    </label>
                  </div>
                  
    <!-- Tool Count Badge -->
                  <div class="flex items-center gap-2">
                    <%= if is_selected do %>
                      <span class="badge badge-sm">
                        {length(selected_tools)}/{length(server_tools)} tools
                      </span>
                    <% else %>
                      <span class="badge badge-sm badge-outline">
                        {length(available_tools)} tools available
                      </span>
                    <% end %>
                  </div>
                </div>
                
    <!-- Expandable Tools Section -->
                <div
                  class={[
                    "mt-3 ml-8 space-y-1 transition-all duration-200",
                    !is_expanded && "hidden"
                  ]}
                  id={"mcp-server-tools-" <> server_id}
                >
                  <%= if length(server_tools) > 0 do %>
                    <div class="flex justify-end mb-2 gap-2">
                      <button
                        type="button"
                        class="btn btn-xs"
                        phx-click="mcp_select_all_tools"
                        phx-target={@myself}
                        phx-value-id={server_id}
                        phx-value-provider={@provider}
                      >
                        Select All
                      </button>
                      <button
                        type="button"
                        class="btn btn-xs"
                        phx-click="mcp_select_no_tools"
                        phx-target={@myself}
                        phx-value-id={server_id}
                        phx-value-provider={@provider}
                      >
                        Select None
                      </button>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-1">
                      <%= for tool <- server_tools do %>
                        <label class="flex items-start gap-2 p-1 hover:bg-base-200 rounded cursor-pointer">
                          <input
                            type="checkbox"
                            phx-click="tool_picker:toggle"
                            phx-target={@myself}
                            phx-value-provider={@provider}
                            phx-value-name={tool.name}
                            checked={tool.name in selected_tools}
                            class="mt-0.5"
                          />
                          <div class="flex-1 min-w-0">
                            <div class="font-mono text-xs truncate">{tool.name}</div>
                            <%= if tool.description do %>
                              <div class="text-[11px] text-slate-400 truncate">
                                {tool.description}
                              </div>
                            <% end %>
                          </div>
                        </label>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-xs text-slate-400 italic">No tools available</div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @mcp_server_options == [] do %>
              <div class="text-sm text-slate-400 italic py-4 text-center">
                No MCP servers configured
              </div>
            <% end %>
          </div>

          <div class="mt-4 flex justify-between items-center">
            <p class="text-[11px] text-slate-400">
              Check the box next to each server to enable its tools. Expand servers to customize tool selection.
            </p>
            <button type="button" class="btn btn-xs" phx-click="open_mcp_modal">
              <.icon name="hero-plus" class="h-4 w-4" />
              <span class="ml-1">Add Server</span>
            </button>
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
    was_selected = id in selected0
    selected = if was_selected, do: Enum.reject(selected0, &(&1 == id)), else: [id | selected0]
    selected = Enum.uniq(Enum.map(selected, &to_string/1))

    # Build inventory immediately from cache (will use stale data if available)
    inv = build_tool_inventory_for_servers(selected)

    send(self(), {:session_mcp_selected_ids, selected})

    # When toggling server, also update tool selection
    socket =
      if was_selected do
        # Deselecting server - remove all its tools from allowed list
        socket
        |> remove_server_tools_from_allowed(id, inv)
      else
        # Selecting server - add all its tools to allowed list
        socket
        |> add_all_server_tools_to_allowed(id, inv)
      end

    # Notify parent about tool selection changes
    send(self(), {:tool_picker_allowed, socket.assigns.tool_picker_allowed})

    {:noreply,
     assign(socket,
       session_mcp_selected_ids: selected,
       tool_inventory_by_provider: inv,
       mcp_warming: false
     )}
  end

  def handle_event("toggle_mcp_expand", %{"id" => id}, socket) do
    id = to_string(id)
    expanded = socket.assigns[:mcp_expanded_servers] || MapSet.new()

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :mcp_expanded_servers, expanded)}
  end

  def handle_event("mcp_select_all_tools", %{"id" => server_id, "provider" => prov_param}, socket) do
    provider = to_provider(prov_param) || socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])

    # Get server info to find tools for this specific server
    server =
      Enum.find(socket.assigns[:mcp_server_options] || [], fn {_label, id} ->
        to_string(id) == server_id
      end)

    if server do
      {label, _id} = server
      # get_server_tools now handles label cleaning internally
      server_tools = get_server_tools(socket.assigns.tool_inventory_by_provider, provider, label)
      tool_names = Enum.map(server_tools, & &1.name)

      current =
        case Map.get(allowed0, provider) do
          l when is_list(l) -> l
          _ -> Enum.map(inv, & &1.name)
        end

      desired = Enum.uniq(current ++ tool_names)
      {:noreply, assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mcp_select_no_tools", %{"id" => server_id, "provider" => prov_param}, socket) do
    provider = to_provider(prov_param) || socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])

    # Get server info to find tools for this specific server
    server =
      Enum.find(socket.assigns[:mcp_server_options] || [], fn {_label, id} ->
        to_string(id) == server_id
      end)

    if server do
      {label, _id} = server
      # get_server_tools now handles label cleaning internally
      server_tools = get_server_tools(socket.assigns.tool_inventory_by_provider, provider, label)
      tool_names = Enum.map(server_tools, & &1.name)

      current =
        case Map.get(allowed0, provider) do
          l when is_list(l) -> l
          _ -> Enum.map(inv, & &1.name)
        end

      desired = Enum.reject(current, &(&1 in tool_names))
      {:noreply, assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("tool_picker:toggle", %{"provider" => prov_param, "name" => name}, socket) do
    provider = to_provider(prov_param) || socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}
    inv = Map.get(socket.assigns[:tool_inventory_by_provider] || %{}, provider, [])

    Logger.info(
      "Provider: #{inspect(provider)} --- Allowed: #{inspect(allowed0)} --- Inv: #{inspect(inv)}"
    )

    # Get the current selection, defaulting to all tools in inventory if not explicitly set
    # This ensures that when MCP servers are selected, their tools appear selected by default
    current =
      case Map.get(allowed0, provider) do
        l when is_list(l) ->
          Logger.info("l when is_list(l), l: #{inspect(l)}")
          # Explicit selection exists, use it
          l

        _ ->
          # No explicit selection, default to all tools currently in inventory
          # This happens when MCP server is first selected
          Logger.info("No explicit selection")
          Enum.map(inv, & &1.name)
      end

    # Toggle the specific tool
    desired =
      if name in current,
        do: Enum.reject(current, &(&1 == name)),
        else: Enum.uniq([name | current])

    Logger.info(
      "name: #{name} -- current: #{inspect(current)} -- name in current: #{inspect(name in current)}"
    )

    # Update the allowed tools
    updated_allowed = Map.put(allowed0, provider, desired)

    # Notify parent to persist the state
    send(self(), {:tool_picker_allowed, updated_allowed})

    {:noreply, assign(socket, :tool_picker_allowed, updated_allowed)}
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
    updated_allowed = Map.put(allowed0, provider, desired)
    send(self(), {:tool_picker_allowed, updated_allowed})
    {:noreply, assign(socket, :tool_picker_allowed, updated_allowed)}
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
    updated_allowed = Map.put(allowed0, provider, desired)
    send(self(), {:tool_picker_allowed, updated_allowed})
    {:noreply, assign(socket, :tool_picker_allowed, updated_allowed)}
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

  # Inventory building helper
  defp build_tool_inventory_for_servers(server_ids) do
    %{
      openai: Inventory.list_for_provider_with_servers(server_ids, :openai),
      anthropic: Inventory.list_for_provider_with_servers(server_ids, :anthropic),
      gemini: Inventory.list_for_provider_with_servers(server_ids, :gemini)
    }
  end

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

  # Helper to get tools for a specific MCP server
  defp get_server_tools(inventory_by_provider, provider, server_label) do
    inv = Map.get(inventory_by_provider || %{}, provider, [])

    # Extract the display_name part from labels like "context7 · stdio"
    # to match against the server_label stored in inventory items
    clean_label =
      case String.split(server_label, " · ") do
        [display_name | _] -> display_name
        _ -> server_label
      end

    Enum.filter(inv, fn item ->
      item.source == :mcp && Map.get(item, :server_label) == clean_label
    end)
  end

  # Helper to get selected tool names
  defp get_selected_tools(allowed_by_provider, provider, server_tools) do
    case Map.get(allowed_by_provider || %{}, provider) do
      list when is_list(list) ->
        tool_names = Enum.map(server_tools, & &1.name)
        Enum.filter(list, &(&1 in tool_names))

      _ ->
        # If no explicit selection, all tools are selected by default
        Enum.map(server_tools, & &1.name)
    end
  end

  # Helper to get available tools for a server directly from cache (even if not selected)
  defp get_available_tools_for_server(_inventory_by_provider, provider, server_id) do
    # Get tools directly from cache for this specific server
    case Inventory.list_for_provider_with_servers([server_id], provider) do
      tools when is_list(tools) ->
        Enum.filter(tools, &(&1.source == :mcp))

      _ ->
        []
    end
  end

  # Helper to add all tools from a server to the allowed list
  defp add_all_server_tools_to_allowed(socket, server_id, inv) do
    provider = socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}

    # Find the server label for this ID
    server =
      Enum.find(socket.assigns[:mcp_server_options] || [], fn {_label, id} ->
        to_string(id) == server_id
      end)

    if server do
      {label, _id} = server
      # get_server_tools now handles label cleaning internally
      server_tools = get_server_tools(inv, provider, label)
      tool_names = Enum.map(server_tools, & &1.name)

      current =
        case Map.get(allowed0, provider) do
          l when is_list(l) -> l
          _ -> Enum.map(inv[provider] || [], & &1.name)
        end

      desired = Enum.uniq(current ++ tool_names)
      assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))
    else
      socket
    end
  end

  # Helper to remove all tools from a server from the allowed list
  defp remove_server_tools_from_allowed(socket, server_id, inv) do
    provider = socket.assigns[:provider] || :openai
    allowed0 = socket.assigns[:tool_picker_allowed] || %{}

    # Find the server label for this ID
    server =
      Enum.find(socket.assigns[:mcp_server_options] || [], fn {_label, id} ->
        to_string(id) == server_id
      end)

    if server do
      {label, _id} = server
      # get_server_tools now handles label cleaning internally
      server_tools = get_server_tools(inv, provider, label)
      tool_names = Enum.map(server_tools, & &1.name)

      current =
        case Map.get(allowed0, provider) do
          l when is_list(l) -> l
          _ -> Enum.map(inv[provider] || [], & &1.name)
        end

      desired = Enum.reject(current, &(&1 in tool_names))
      assign(socket, :tool_picker_allowed, Map.put(allowed0, provider, desired))
    else
      socket
    end
  end
end

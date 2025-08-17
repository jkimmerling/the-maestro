defmodule TheMaestro.MCP.Tools.Registry do
  @moduledoc """
  MCP Tool Registry for managing tool discovery, registration, and namespace handling.

  This GenServer maintains a registry of MCP tools from connected servers, handles
  name conflicts through prefixing, and provides a unified interface for tool
  discovery and execution routing.

  ## Features

  - Tool discovery and registration from MCP servers
  - Automatic namespace conflict resolution through server prefixing
  - Tool metadata management and attribution
  - Dynamic tool registration and deregistration
  - Tool validation and schema processing

  """

  use GenServer
  require Logger

  # Tool metadata structure
  defmodule ToolMetadata do
    @moduledoc """
    Metadata for registered MCP tools including source attribution and namespace info.
    """
    @type t :: %__MODULE__{
            tool_name: String.t(),
            server_id: String.t(),
            original_name: String.t(),
            prefixed_name: String.t() | nil,
            capabilities: [atom()],
            trust_level: :trusted | :untrusted,
            last_used: DateTime.t() | nil,
            registered_at: DateTime.t()
          }

    defstruct [
      :tool_name,
      :server_id,
      :original_name,
      :prefixed_name,
      :capabilities,
      :trust_level,
      :last_used,
      :registered_at
    ]
  end

  # Processed tool structure compatible with existing tool system
  defmodule ProcessedTool do
    @moduledoc """
    MCP tool processed into format compatible with existing agent tooling system.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t(),
            parameters: [map()],
            executor: fun(),
            metadata: ToolMetadata.t()
          }

    defstruct [:name, :description, :parameters, :executor, :metadata]
  end

  # Tool routing information
  defmodule ToolRoute do
    @moduledoc """
    Information needed to route tool execution to the correct MCP server.
    """
    @type t :: %__MODULE__{
            tool: ProcessedTool.t(),
            server_id: String.t(),
            metadata: ToolMetadata.t()
          }

    defstruct [:tool, :server_id, :metadata]
  end

  # GenServer state
  defstruct [
    # %{server_id => [ProcessedTool.t()]}
    :server_tools,
    # %{tool_name => ToolMetadata.t()}
    :tool_metadata,
    # %{tool_name => server_id}
    :tool_routing,
    # Set of tool names that have conflicts
    :conflicted_names
  ]

  @type state :: %__MODULE__{
          server_tools: %{String.t() => [ProcessedTool.t()]},
          tool_metadata: %{String.t() => ToolMetadata.t()},
          tool_routing: %{String.t() => String.t()},
          conflicted_names: MapSet.t(String.t())
        }

  ## Client API

  @doc """
  Start the tool registry GenServer.

  ## Options

  - `:name` - Name to register the GenServer under (default: `__MODULE__`)

  ## Examples

      iex> {:ok, registry} = TheMaestro.MCP.Tools.Registry.start_link()
      iex> is_pid(registry)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register tools from an MCP server.

  Processes raw MCP tool definitions and registers them with conflict resolution.
  Tools that conflict with existing tools from other servers will be prefixed
  with the server ID.

  ## Parameters

  - `registry` - The registry GenServer
  - `server_id` - Unique identifier for the MCP server
  - `raw_tools` - List of raw MCP tool definitions

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  """
  @spec register_tools(GenServer.server(), String.t(), [map()]) :: :ok | {:error, term()}
  def register_tools(registry, server_id, raw_tools) do
    GenServer.call(registry, {:register_tools, server_id, raw_tools})
  end

  @doc """
  Get all tools registered by a specific server.

  ## Parameters

  - `registry` - The registry GenServer
  - `server_id` - Server identifier

  ## Returns

  - `{:ok, [ProcessedTool.t()]}` on success
  - `{:error, :not_found}` if server not found

  """
  @spec get_server_tools(GenServer.server(), String.t()) ::
          {:ok, [ProcessedTool.t()]} | {:error, :not_found}
  def get_server_tools(registry, server_id) do
    GenServer.call(registry, {:get_server_tools, server_id})
  end

  @doc """
  Get all registered tools from all servers with namespace conflict resolution.

  Returns a flat list of all tools, with conflicting tool names automatically
  prefixed with their server IDs to ensure uniqueness.

  ## Parameters

  - `registry` - The registry GenServer

  ## Returns

  List of all processed tools

  """
  @spec get_all_tools(GenServer.server()) :: [ProcessedTool.t()]
  def get_all_tools(registry) do
    GenServer.call(registry, :get_all_tools)
  end

  @doc """
  Find a specific tool by name, supporting both original and prefixed names.

  ## Parameters

  - `registry` - The registry GenServer
  - `tool_name` - Tool name or prefixed tool name (server_id__tool_name)

  ## Returns

  - `{:ok, ToolRoute.t()}` on success
  - `{:error, :not_found}` if tool not found

  """
  @spec find_tool(GenServer.server(), String.t()) :: {:ok, ToolRoute.t()} | {:error, :not_found}
  def find_tool(registry, tool_name) do
    GenServer.call(registry, {:find_tool, tool_name})
  end

  @doc """
  Unregister all tools for a specific server.

  ## Parameters

  - `registry` - The registry GenServer
  - `server_id` - Server identifier

  ## Returns

  `:ok` always
  """
  @spec unregister_server(GenServer.server(), String.t()) :: :ok
  def unregister_server(registry, server_id) do
    GenServer.call(registry, {:unregister_server, server_id})
  end

  @doc """
  Get list of all registered server IDs.

  ## Parameters

  - `registry` - The registry GenServer

  ## Returns

  List of server IDs

  """
  @spec list_servers(GenServer.server()) :: [String.t()]
  def list_servers(registry) do
    GenServer.call(registry, :list_servers)
  end

  @doc """
  Get total count of registered tools across all servers.

  ## Parameters

  - `registry` - The registry GenServer

  ## Returns

  Integer count of tools
  """
  @spec tool_count(GenServer.server()) :: non_neg_integer()
  def tool_count(registry) do
    GenServer.call(registry, :tool_count)
  end

  @doc """
  Get metadata for a specific tool.

  ## Parameters

  - `registry` - The registry GenServer
  - `tool_name` - Tool name (original or prefixed)

  ## Returns

  - `{:ok, ToolMetadata.t()}` on success
  - `{:error, :not_found}` if tool not found
  """
  @spec get_tool_metadata(GenServer.server(), String.t()) ::
          {:ok, ToolMetadata.t()} | {:error, :not_found}
  def get_tool_metadata(registry, tool_name) do
    GenServer.call(registry, {:get_tool_metadata, tool_name})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      server_tools: %{},
      tool_metadata: %{},
      tool_routing: %{},
      conflicted_names: MapSet.new()
    }

    Logger.info("MCP Tool Registry started")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_tools, server_id, raw_tools}, _from, state) do
    case process_and_register_tools(server_id, raw_tools, state) do
      {:ok, new_state} ->
        Logger.info("Registered #{length(raw_tools)} tools for server #{server_id}")
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.warning("Failed to register tools for server #{server_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:get_server_tools, server_id}, _from, state) do
    case Map.get(state.server_tools, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tools ->
        {:reply, {:ok, tools}, state}
    end
  end

  def handle_call(:get_all_tools, _from, state) do
    all_tools = collect_all_tools_with_namespacing(state)
    {:reply, all_tools, state}
  end

  def handle_call({:find_tool, tool_name}, _from, state) do
    case find_tool_in_registry(tool_name, state) do
      {:ok, tool_route} ->
        {:reply, {:ok, tool_route}, state}

      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:unregister_server, server_id}, _from, state) do
    new_state = remove_server_tools(server_id, state)
    Logger.info("Unregistered all tools for server #{server_id}")
    {:reply, :ok, new_state}
  end

  def handle_call(:list_servers, _from, state) do
    servers = Map.keys(state.server_tools)
    {:reply, servers, state}
  end

  def handle_call(:tool_count, _from, state) do
    count =
      state.server_tools
      |> Map.values()
      |> List.flatten()
      |> length()

    {:reply, count, state}
  end

  def handle_call({:get_tool_metadata, tool_name}, _from, state) do
    case Map.get(state.tool_metadata, tool_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      metadata ->
        {:reply, {:ok, metadata}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("MCP Tool Registry received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Helper Functions

  defp process_and_register_tools(server_id, raw_tools, state) do
    with {:ok, validated_tools} <- validate_tool_schemas(raw_tools),
         {:ok, processed_tools} <- process_tools(server_id, validated_tools) do
      new_state = register_processed_tools(server_id, processed_tools, state)
      {:ok, new_state}
    end
  end

  defp validate_tool_schemas(raw_tools) do
    case Enum.find(raw_tools, &(!valid_tool_schema?(&1))) do
      nil ->
        {:ok, raw_tools}

      _invalid_tool ->
        {:error, :invalid_schema}
    end
  end

  defp valid_tool_schema?(tool) do
    is_map(tool) and
      is_binary(Map.get(tool, "name")) and
      is_binary(Map.get(tool, "description")) and
      is_map(Map.get(tool, "inputSchema"))
  end

  defp process_tools(server_id, validated_tools) do
    now = DateTime.utc_now()

    processed_tools =
      Enum.map(validated_tools, fn raw_tool ->
        tool_name = Map.get(raw_tool, "name")

        metadata = %ToolMetadata{
          tool_name: tool_name,
          server_id: server_id,
          original_name: tool_name,
          prefixed_name: nil,
          capabilities: extract_capabilities(raw_tool),
          trust_level: :untrusted,
          last_used: nil,
          registered_at: now
        }

        %ProcessedTool{
          name: tool_name,
          description: Map.get(raw_tool, "description"),
          parameters: process_parameters(Map.get(raw_tool, "inputSchema")),
          executor: &TheMaestro.MCP.Tools.Executor.execute/3,
          metadata: metadata
        }
      end)

    {:ok, processed_tools}
  end

  defp extract_capabilities(_raw_tool) do
    # For now, assume all MCP tools support text output
    # This can be enhanced based on tool analysis
    [:text_output]
  end

  defp process_parameters(input_schema) do
    properties = Map.get(input_schema, "properties", %{})
    required = Map.get(input_schema, "required", [])

    Enum.map(properties, fn {name, prop_def} ->
      %{
        name: name,
        type: string_to_atom_type(Map.get(prop_def, "type", "string")),
        required: name in required,
        description: Map.get(prop_def, "description", "")
      }
    end)
  end

  defp string_to_atom_type("string"), do: :string
  defp string_to_atom_type("number"), do: :number
  defp string_to_atom_type("integer"), do: :integer
  defp string_to_atom_type("boolean"), do: :boolean
  defp string_to_atom_type("array"), do: :array
  defp string_to_atom_type("object"), do: :object
  defp string_to_atom_type(_), do: :string

  defp register_processed_tools(server_id, processed_tools, state) do
    # Remove existing tools for this server first
    state_without_server = remove_server_tools(server_id, state)

    # Add new tools temporarily to determine conflicts
    temp_server_tools = Map.put(state_without_server.server_tools, server_id, processed_tools)

    # Find all conflicts across all servers
    all_tool_names = collect_all_tool_names(temp_server_tools)
    conflicted_names = find_conflicting_names(all_tool_names)

    # Apply prefixing to ALL tools (both new and existing) that have conflicts
    {updated_server_tools, all_tool_metadata, all_tool_routing} =
      apply_conflict_resolution(temp_server_tools, conflicted_names, state_without_server)

    %{
      state_without_server
      | server_tools: updated_server_tools,
        tool_metadata: all_tool_metadata,
        tool_routing: all_tool_routing,
        conflicted_names: MapSet.new(conflicted_names)
    }
  end

  defp remove_server_tools(server_id, state) do
    # Get tools to remove
    tools_to_remove = Map.get(state.server_tools, server_id, [])

    # Remove from metadata and routing
    new_tool_metadata =
      Enum.reduce(tools_to_remove, state.tool_metadata, fn tool, acc ->
        Map.delete(acc, tool.name)
      end)

    new_tool_routing =
      Enum.reduce(tools_to_remove, state.tool_routing, fn tool, acc ->
        Map.delete(acc, tool.name)
      end)

    # Remove from server tools
    new_server_tools = Map.delete(state.server_tools, server_id)

    # Recalculate conflicts since removing tools might resolve some conflicts
    remaining_tool_names = collect_all_tool_names(new_server_tools)
    new_conflicted_names = MapSet.new(find_conflicting_names(remaining_tool_names))

    %{
      state
      | server_tools: new_server_tools,
        tool_metadata: new_tool_metadata,
        tool_routing: new_tool_routing,
        conflicted_names: new_conflicted_names
    }
  end

  defp apply_conflict_resolution(server_tools_map, conflicted_names, _state) do
    # Apply prefixing to all tools that have conflicts
    updated_server_tools =
      Map.new(server_tools_map, fn {server_id, tools} ->
        updated_tools =
          Enum.map(tools, fn tool ->
            if tool.name in conflicted_names do
              prefixed_name = "#{server_id}__#{tool.name}"

              updated_metadata = %{
                tool.metadata
                | tool_name: prefixed_name,
                  prefixed_name: prefixed_name
              }

              %{tool | name: prefixed_name, metadata: updated_metadata}
            else
              tool
            end
          end)

        {server_id, updated_tools}
      end)

    # Build metadata and routing maps
    all_tool_metadata =
      Enum.reduce(updated_server_tools, %{}, fn {_server_id, tools}, acc ->
        Enum.reduce(tools, acc, fn tool, metadata_acc ->
          Map.put(metadata_acc, tool.name, tool.metadata)
        end)
      end)

    all_tool_routing =
      Enum.reduce(updated_server_tools, %{}, fn {server_id, tools}, acc ->
        Enum.reduce(tools, acc, fn tool, routing_acc ->
          Map.put(routing_acc, tool.name, server_id)
        end)
      end)

    {updated_server_tools, all_tool_metadata, all_tool_routing}
  end

  defp collect_all_tool_names(server_tools_map) do
    server_tools_map
    |> Map.values()
    |> List.flatten()
    |> Enum.map(& &1.name)
  end

  defp find_conflicting_names(tool_names) do
    tool_names
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
  end

  defp collect_all_tools_with_namespacing(state) do
    state.server_tools
    |> Map.values()
    |> List.flatten()
  end

  defp find_tool_in_registry(tool_name, state) do
    case Map.get(state.tool_routing, tool_name) do
      nil ->
        :not_found

      server_id ->
        server_tools = Map.get(state.server_tools, server_id, [])

        case Enum.find(server_tools, &(&1.name == tool_name)) do
          nil ->
            :not_found

          tool ->
            metadata = Map.get(state.tool_metadata, tool_name)

            {:ok,
             %ToolRoute{
               tool: tool,
               server_id: server_id,
               metadata: metadata
             }}
        end
    end
  end
end
defmodule TheMaestro.MCP.Registry do
  @moduledoc """
  MCP Server Registry with Tool Namespace Management

  Central registry for tracking all MCP servers, their connections,
  tools, and providing namespace management for tool conflicts.

  Features:
  - Server registration and lifecycle tracking
  - Tool namespace conflict resolution with automatic prefixing
  - Load balancing and failover support
  - Metrics collection and performance tracking
  - Event broadcasting for status changes
  - Priority-based tool resolution
  """

  use GenServer
  require Logger


  # Server information structure
  defmodule ServerInfo do
    @type t :: %__MODULE__{
            server_id: String.t(),
            config: map(),
            connection: pid() | nil,
            status: :connecting | :connected | :disconnected | :error,
            tools: [map()],
            capabilities: map(),
            last_heartbeat: integer(),
            registered_at: DateTime.t(),
            metrics: map()
          }

    defstruct [
      :server_id,
      :config,
      :connection,
      :status,
      :tools,
      :capabilities,
      :last_heartbeat,
      :registered_at,
      :metrics
    ]
  end

  # Tool with server attribution
  defmodule AttributedTool do
    @type t :: %__MODULE__{
            name: String.t(),
            server_id: String.t(),
            description: String.t() | nil,
            original_tool: map()
          }

    defstruct [:name, :server_id, :description, :original_tool]
  end

  # Server metrics
  defmodule Metrics do
    @type t :: %__MODULE__{
            uptime: integer(),
            last_heartbeat: integer(),
            status: atom(),
            total_operations: integer(),
            error_count: integer(),
            error_rate: float(),
            avg_latency: float()
          }

    defstruct [
      uptime: 0,
      last_heartbeat: 0,
      status: :disconnected,
      total_operations: 0,
      error_count: 0,
      error_rate: 0.0,
      avg_latency: 0.0
    ]
  end

  # GenServer state
  defstruct [
    :servers,           # %{server_id => ServerInfo.t()}
    :tool_conflicts,    # MapSet of conflicting tool names
    :subscribers        # List of PIDs subscribed to events
  ]

  @type state :: %__MODULE__{
          servers: %{String.t() => ServerInfo.t()},
          tool_conflicts: MapSet.t(),
          subscribers: [pid()]
        }

  ## Client API

  @doc """
  Start the MCP Registry GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a server in the registry.
  """
  @spec register_server(GenServer.server(), map()) :: :ok
  def register_server(registry, server_info) do
    GenServer.call(registry, {:register_server, server_info})
  end

  @doc """
  Deregister a server from the registry.
  """
  @spec deregister_server(GenServer.server(), String.t()) :: :ok
  def deregister_server(registry, server_id) do
    GenServer.call(registry, {:deregister_server, server_id})
  end

  @doc """
  Update a server's status.
  """
  @spec update_server_status(GenServer.server(), String.t(), atom()) :: :ok
  def update_server_status(registry, server_id, status) do
    GenServer.call(registry, {:update_server_status, server_id, status})
  end

  @doc """
  Update a server's heartbeat timestamp.
  """
  @spec update_heartbeat(GenServer.server(), String.t(), integer()) :: :ok
  def update_heartbeat(registry, server_id, timestamp) do
    GenServer.call(registry, {:update_heartbeat, server_id, timestamp})
  end

  @doc """
  Get server information by ID.
  """
  @spec get_server(GenServer.server(), String.t()) :: {:ok, ServerInfo.t()} | {:error, :not_found}
  def get_server(registry, server_id) do
    GenServer.call(registry, {:get_server, server_id})
  end

  @doc """
  Get all tools with namespace handling for conflicts.
  """
  @spec get_all_tools(GenServer.server()) :: [AttributedTool.t()]
  def get_all_tools(registry) do
    GenServer.call(registry, :get_all_tools)
  end

  @doc """
  Resolve a tool by name, handling conflicts and priorities.
  """
  @spec resolve_tool(GenServer.server(), String.t()) :: {:ok, AttributedTool.t()} | {:error, :not_found}
  def resolve_tool(registry, tool_name) do
    GenServer.call(registry, {:resolve_tool, tool_name})
  end

  @doc """
  Get all servers that provide a specific tool.
  """
  @spec get_servers_for_tool(GenServer.server(), String.t()) :: [ServerInfo.t()]
  def get_servers_for_tool(registry, tool_name) do
    GenServer.call(registry, {:get_servers_for_tool, tool_name})
  end

  @doc """
  Get available (connected) servers that provide a specific tool.
  """
  @spec get_available_servers_for_tool(GenServer.server(), String.t()) :: [ServerInfo.t()]
  def get_available_servers_for_tool(registry, tool_name) do
    GenServer.call(registry, {:get_available_servers_for_tool, tool_name})
  end

  @doc """
  Subscribe to registry events.
  """
  @spec subscribe_to_events(GenServer.server()) :: :ok
  def subscribe_to_events(registry) do
    GenServer.call(registry, {:subscribe_to_events, self()})
  end

  @doc """
  Get server metrics.
  """
  @spec get_server_metrics(GenServer.server(), String.t()) :: Metrics.t() | nil
  def get_server_metrics(registry, server_id) do
    GenServer.call(registry, {:get_server_metrics, server_id})
  end

  @doc """
  Record an operation for metrics collection.
  """
  @spec record_operation(GenServer.server(), String.t(), :success | :error, integer()) :: :ok
  def record_operation(registry, server_id, result, latency_ms) do
    GenServer.call(registry, {:record_operation, server_id, result, latency_ms})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      servers: %{},
      tool_conflicts: MapSet.new(),
      subscribers: []
    }

    Logger.info("MCP Registry started")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_server, server_info}, _from, state) do
    server_id = server_info.server_id

    # Create ServerInfo struct with defaults
    full_server_info = %ServerInfo{
      server_id: server_id,
      config: server_info.config,
      connection: server_info.connection,
      status: server_info.status,
      tools: server_info.tools || [],
      capabilities: server_info.capabilities || %{},
      last_heartbeat: server_info.last_heartbeat,
      registered_at: DateTime.utc_now(),
      metrics: %{
        total_operations: 0,
        error_count: 0,
        latencies: []
      }
    }

    # Update tool conflicts
    new_conflicts = update_tool_conflicts(state.tool_conflicts, state.servers, server_info.tools || [])

    new_state = %{
      state |
      servers: Map.put(state.servers, server_id, full_server_info),
      tool_conflicts: new_conflicts
    }

    # Broadcast event
    broadcast_event(new_state, {:server_registered, server_id})
    broadcast_event(new_state, {:tools_updated, server_id, server_info.tools || []})

    Logger.info("Registered MCP server: #{server_id}")
    {:reply, :ok, new_state}
  end

  def handle_call({:deregister_server, server_id}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, :ok, state}

      _server_info ->
        new_servers = Map.delete(state.servers, server_id)

        # Recalculate tool conflicts without this server
        new_conflicts = recalculate_tool_conflicts(new_servers)

        new_state = %{
          state |
          servers: new_servers,
          tool_conflicts: new_conflicts
        }

        # Broadcast event
        broadcast_event(new_state, {:server_deregistered, server_id})

        Logger.info("Deregistered MCP server: #{server_id}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_server_status, server_id, status}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, :ok, state}

      server_info ->
        updated_server = %{server_info | status: status}
        new_servers = Map.put(state.servers, server_id, updated_server)
        new_state = %{state | servers: new_servers}

        # Broadcast event
        broadcast_event(new_state, {:server_status_changed, server_id, status})

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_heartbeat, server_id, timestamp}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, :ok, state}

      server_info ->
        updated_server = %{server_info | last_heartbeat: timestamp}
        new_servers = Map.put(state.servers, server_id, updated_server)
        new_state = %{state | servers: new_servers}

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_server, server_id}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      server_info ->
        {:reply, {:ok, server_info}, state}
    end
  end

  def handle_call(:get_all_tools, _from, state) do
    tools = collect_all_tools_with_attribution(state.servers, state.tool_conflicts)
    {:reply, tools, state}
  end

  def handle_call({:resolve_tool, tool_name}, _from, state) do
    case find_best_tool_match(state.servers, tool_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {server_info, tool} ->
        attributed_tool = %AttributedTool{
          name: tool_name,
          server_id: server_info.server_id,
          description: Map.get(tool, :description) || Map.get(tool, "description"),
          original_tool: tool
        }
        {:reply, {:ok, attributed_tool}, state}
    end
  end

  def handle_call({:get_servers_for_tool, tool_name}, _from, state) do
    servers = find_servers_with_tool(state.servers, tool_name)
    {:reply, servers, state}
  end

  def handle_call({:get_available_servers_for_tool, tool_name}, _from, state) do
    servers = 
      find_servers_with_tool(state.servers, tool_name)
      |> Enum.filter(&(&1.status == :connected))

    {:reply, servers, state}
  end

  def handle_call({:subscribe_to_events, pid}, _from, state) do
    new_subscribers = [pid | state.subscribers]
    new_state = %{state | subscribers: new_subscribers}

    # Monitor the subscriber
    Process.monitor(pid)

    {:reply, :ok, new_state}
  end

  def handle_call({:get_server_metrics, server_id}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, nil, state}

      server_info ->
        metrics = calculate_server_metrics(server_info)
        {:reply, metrics, state}
    end
  end

  def handle_call({:record_operation, server_id, result, latency_ms}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, :ok, state}

      server_info ->
        updated_metrics = update_operation_metrics(server_info.metrics, result, latency_ms)
        updated_server = %{server_info | metrics: updated_metrics}
        new_servers = Map.put(state.servers, server_id, updated_server)
        new_state = %{state | servers: new_servers}

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber
    new_subscribers = Enum.reject(state.subscribers, &(&1 == pid))
    new_state = %{state | subscribers: new_subscribers}
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("MCP Registry terminated")
    :ok
  end

  ## Private Helper Functions

  defp update_tool_conflicts(current_conflicts, existing_servers, new_tools) do
    # Get all existing tool names
    existing_tool_names = 
      existing_servers
      |> Map.values()
      |> Enum.flat_map(& &1.tools)
      |> Enum.map(fn tool -> Map.get(tool, :name) || Map.get(tool, "name") end)

    # Find conflicts with new tools
    new_tool_names = Enum.map(new_tools, fn tool -> Map.get(tool, :name) || Map.get(tool, "name") end)

    new_conflicts = 
      new_tool_names
      |> Enum.filter(&(&1 in existing_tool_names))
      |> MapSet.new()

    MapSet.union(current_conflicts, new_conflicts)
  end

  defp recalculate_tool_conflicts(servers) do
    # Collect all tool names with their counts
    tool_counts = 
      servers
      |> Map.values()
      |> Enum.flat_map(& &1.tools)
      |> Enum.map(fn tool -> Map.get(tool, :name) || Map.get(tool, "name") end)
      |> Enum.frequencies()

    # Find tools that appear more than once
    tool_counts
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> MapSet.new()
  end

  defp collect_all_tools_with_attribution(servers, conflicts) do
    servers
    |> Map.values()
    |> Enum.flat_map(fn server_info ->
      Enum.map(server_info.tools, fn tool ->
        tool_name = Map.get(tool, :name) || Map.get(tool, "name")
        
        final_name = if MapSet.member?(conflicts, tool_name) do
          "#{server_info.server_id}__#{tool_name}"
        else
          tool_name
        end

        %AttributedTool{
          name: final_name,
          server_id: server_info.server_id,
          description: Map.get(tool, :description) || Map.get(tool, "description"),
          original_tool: tool
        }
      end)
    end)
  end

  defp find_best_tool_match(servers, tool_name) do
    # Find servers that have this tool, prioritizing by server priority
    matches = find_servers_with_tool(servers, tool_name)

    case matches do
      [] -> nil
      [single_match] -> 
        tool = Enum.find(single_match.tools, fn t -> 
          (Map.get(t, :name) || Map.get(t, "name")) == tool_name 
        end)
        {single_match, tool}
      multiple_matches ->
        # Sort by priority (higher priority first)
        sorted_matches = Enum.sort_by(multiple_matches, fn server ->
          Map.get(server.config, :priority, 5)
        end, &>=/2)
        
        best_server = hd(sorted_matches)
        tool = Enum.find(best_server.tools, fn t -> 
          (Map.get(t, :name) || Map.get(t, "name")) == tool_name 
        end)
        {best_server, tool}
    end
  end

  defp find_servers_with_tool(servers, tool_name) do
    servers
    |> Map.values()
    |> Enum.filter(fn server_info ->
      Enum.any?(server_info.tools, fn tool ->
        (Map.get(tool, :name) || Map.get(tool, "name")) == tool_name
      end)
    end)
  end

  defp calculate_server_metrics(server_info) do
    registered_at = server_info.registered_at || DateTime.utc_now()
    uptime = DateTime.diff(DateTime.utc_now(), registered_at, :millisecond)
    
    metrics = server_info.metrics
    total_ops = Map.get(metrics, :total_operations, 0)
    error_count = Map.get(metrics, :error_count, 0)
    latencies = Map.get(metrics, :latencies, [])

    error_rate = if total_ops > 0, do: error_count / total_ops * 100, else: 0.0
    avg_latency = if length(latencies) > 0, do: Enum.sum(latencies) / length(latencies), else: 0.0

    %Metrics{
      uptime: uptime,
      last_heartbeat: server_info.last_heartbeat,
      status: server_info.status,
      total_operations: total_ops,
      error_count: error_count,
      error_rate: error_rate,
      avg_latency: avg_latency
    }
  end

  defp update_operation_metrics(metrics, result, latency_ms) do
    total_ops = Map.get(metrics, :total_operations, 0) + 1
    error_count = if result == :error do
      Map.get(metrics, :error_count, 0) + 1
    else
      Map.get(metrics, :error_count, 0)
    end

    # Keep only last 100 latency measurements to avoid unbounded growth
    latencies = [latency_ms | Map.get(metrics, :latencies, [])]
    trimmed_latencies = Enum.take(latencies, 100)

    %{
      total_operations: total_ops,
      error_count: error_count,
      latencies: trimmed_latencies
    }
  end

  defp broadcast_event(state, event) do
    Enum.each(state.subscribers, fn pid ->
      if Process.alive?(pid) do
        send(pid, {:mcp_registry_event, event})
      end
    end)
  end
end
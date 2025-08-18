defmodule TheMaestro.MCP.ConnectionManager do
  @moduledoc """
  MCP Connection Pool Manager

  This GenServer manages a pool of MCP server connections, providing:
  - Connection lifecycle management
  - Health monitoring and heartbeat tracking
  - Tool discovery and registration from connected servers
  - Dynamic server addition/removal
  - Circuit breaker pattern for failing servers
  - Configuration hot-reloading
  """

  use GenServer
  require Logger

  alias TheMaestro.MCP.Discovery

  # Connection info structure that will be returned to callers
  defmodule ConnectionInfo do
    @moduledoc """
    Represents connection information for an MCP server.
    """
    @type t :: %__MODULE__{
            server_id: String.t(),
            connection_pid: pid(),
            transport_pid: pid(),
            status: :connecting | :connected | :error | :disconnected,
            started_at: DateTime.t(),
            last_heartbeat: integer(),
            heartbeat_interval: integer()
          }

    defstruct [
      :server_id,
      :connection_pid,
      :transport_pid,
      :status,
      :started_at,
      :last_heartbeat,
      :heartbeat_interval
    ]
  end

  # Health status structure
  defmodule HealthStatus do
    @moduledoc """
    Represents health monitoring status for an MCP server connection.
    """
    @type t :: %__MODULE__{
            server_id: String.t(),
            status: :connecting | :connected | :error | :disconnected,
            last_heartbeat: integer(),
            error_count: integer(),
            last_error: String.t() | nil
          }

    defstruct [:server_id, :status, :last_heartbeat, :error_count, :last_error]
  end

  # Circuit breaker state
  defmodule CircuitBreaker do
    @moduledoc """
    Implements circuit breaker pattern state for failing MCP server connections.
    """
    @type t :: %__MODULE__{
            failures: integer(),
            failure_window_start: integer(),
            state: :closed | :open | :half_open
          }

    defstruct failures: 0, failure_window_start: 0, state: :closed
  end

  # GenServer state
  defstruct [
    # %{server_id => ConnectionInfo.t()}
    :connections,
    # %{server_id => [tool_definitions]}
    :tools,
    # %{server_id => HealthStatus.t()}
    :health_status,
    # %{server_id => CircuitBreaker.t()}
    :circuit_breakers,
    # %{server_id => timer_ref}
    :heartbeat_timers
  ]

  @type state :: %__MODULE__{
          connections: %{String.t() => ConnectionInfo.t()},
          tools: %{String.t() => [map()]},
          health_status: %{String.t() => HealthStatus.t()},
          circuit_breakers: %{String.t() => CircuitBreaker.t()},
          heartbeat_timers: %{String.t() => reference()}
        }

  ## Client API

  @doc """
  Start the connection manager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start and track a server connection.
  """
  @spec start_connection(GenServer.server(), map()) :: {:ok, pid()} | {:error, term()}
  def start_connection(manager, server_config) do
    GenServer.call(manager, {:start_connection, server_config}, 30_000)
  end

  @doc """
  Stop a server connection.
  """
  @spec stop_connection(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def stop_connection(manager, server_id) do
    GenServer.call(manager, {:stop_connection, server_id})
  end

  @doc """
  Get connection information for a specific server.
  """
  @spec get_connection(GenServer.server(), String.t()) ::
          {:ok, ConnectionInfo.t()} | {:error, :not_found}
  def get_connection(manager, server_id) do
    GenServer.call(manager, {:get_connection, server_id})
  end

  @doc """
  List all active connections.
  """
  @spec list_connections(GenServer.server()) :: [ConnectionInfo.t()]
  def list_connections(manager) do
    GenServer.call(manager, :list_connections)
  end

  @doc """
  Get health status for a specific server.
  """
  @spec get_health_status(GenServer.server(), String.t()) ::
          {:ok, HealthStatus.t()} | {:error, :not_found}
  def get_health_status(manager, server_id) do
    GenServer.call(manager, {:get_health_status, server_id})
  end

  @doc """
  Register tools from a connected server.
  """
  @spec register_tools(GenServer.server(), String.t(), [map()]) :: :ok | {:error, term()}
  def register_tools(manager, server_id, tools) do
    GenServer.call(manager, {:register_tools, server_id, tools})
  end

  @doc """
  Get tools for a specific server.
  """
  @spec get_server_tools(GenServer.server(), String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_server_tools(manager, server_id) do
    GenServer.call(manager, {:get_server_tools, server_id})
  end

  @doc """
  Get all tools with namespace handling for conflicts.
  """
  @spec get_all_tools(GenServer.server()) :: [map()]
  def get_all_tools(manager) do
    GenServer.call(manager, :get_all_tools)
  end

  @doc """
  Add a new server dynamically.
  """
  @spec add_server(GenServer.server(), map()) :: {:ok, pid()} | {:error, term()}
  def add_server(manager, server_config) do
    # add_server is the same as start_connection for our purposes
    start_connection(manager, server_config)
  end

  @doc """
  Remove a server dynamically.
  """
  @spec remove_server(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def remove_server(manager, server_id) do
    # remove_server is the same as stop_connection for our purposes
    stop_connection(manager, server_id)
  end

  @doc """
  Reload configuration from file.
  """
  @spec reload_configuration(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def reload_configuration(manager, config_path) do
    GenServer.call(manager, {:reload_configuration, config_path}, 30_000)
  end

  @doc """
  Test connection to a server.
  """
  @spec test_connection(GenServer.server(), map()) :: {:ok, term()} | {:error, term()}
  def test_connection(manager, server_config) do
    GenServer.call(manager, {:test_connection, server_config}, 30_000)
  end

  @doc """
  Ping a server to check connectivity.
  """
  @spec ping_server(GenServer.server(), String.t()) :: {:ok, integer()} | {:error, term()}
  def ping_server(manager, server_id) do
    GenServer.call(manager, {:ping_server, server_id}, 10_000)
  end

  @doc """
  Execute a tool on a specific server.
  """
  @spec execute_tool(GenServer.server(), String.t(), String.t(), map(), integer()) ::
          {:ok, term()} | {:error, term()}
  def execute_tool(manager, server_id, tool_name, params, timeout \\ 30_000) do
    GenServer.call(manager, {:execute_tool, server_id, tool_name, params}, timeout)
  end

  @doc """
  Get connection metrics for a server.
  """
  @spec get_connection_metrics(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_connection_metrics(manager, server_id) do
    GenServer.call(manager, {:get_connection_metrics, server_id})
  end

  @doc """
  Get performance metrics for a server over a time period.
  """
  @spec get_performance_metrics(GenServer.server(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def get_performance_metrics(manager, server_id, timeframe_hours) do
    GenServer.call(manager, {:get_performance_metrics, server_id, timeframe_hours})
  end

  @doc """
  Get tool usage metrics for a server.
  """
  @spec get_tool_usage_metrics(GenServer.server(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def get_tool_usage_metrics(manager, server_id, timeframe_hours) do
    GenServer.call(manager, {:get_tool_usage_metrics, server_id, timeframe_hours})
  end

  @doc """
  Get error metrics for a server.
  """
  @spec get_error_metrics(GenServer.server(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  def get_error_metrics(manager, server_id, timeframe_hours) do
    GenServer.call(manager, {:get_error_metrics, server_id, timeframe_hours})
  end

  @doc """
  Start a trace for server connection debugging.
  """
  @spec start_trace(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def start_trace(manager, server_id) do
    GenServer.call(manager, {:start_trace, server_id})
  end

  @doc """
  Stop a trace and return results.
  """
  @spec stop_trace(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def stop_trace(manager, trace_id) do
    GenServer.call(manager, {:stop_trace, trace_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      connections: %{},
      tools: %{},
      health_status: %{},
      circuit_breakers: %{},
      heartbeat_timers: %{}
    }

    Logger.info("ConnectionManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_connection, server_config}, _from, state) do
    server_id = Map.get(server_config, :id)

    # Check if connection already exists
    case Map.get(state.connections, server_id) do
      nil ->
        # Check circuit breaker
        case check_circuit_breaker(state, server_id, server_config) do
          {:ok, state} ->
            do_start_connection(server_config, state)

          {:error, :circuit_open} = error ->
            {:reply, error, state}
        end

      _existing ->
        {:reply, {:error, :already_connected}, state}
    end
  end

  def handle_call({:stop_connection, server_id}, _from, state) do
    case Map.get(state.connections, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      connection_info ->
        new_state = do_stop_connection(server_id, connection_info, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_connection, server_id}, _from, state) do
    case Map.get(state.connections, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      connection_info ->
        {:reply, {:ok, connection_info}, state}
    end
  end

  def handle_call(:list_connections, _from, state) do
    connections = Map.values(state.connections)
    {:reply, connections, state}
  end

  def handle_call({:get_health_status, server_id}, _from, state) do
    case Map.get(state.health_status, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      health_status ->
        {:reply, {:ok, health_status}, state}
    end
  end

  def handle_call({:register_tools, server_id, tools}, _from, state) do
    # Check if server exists
    case Map.get(state.connections, server_id) do
      nil ->
        {:reply, {:error, :server_not_found}, state}

      _connection ->
        new_tools = Map.put(state.tools, server_id, tools)
        new_state = %{state | tools: new_tools}
        Logger.debug("Registered #{length(tools)} tools for server #{server_id}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_server_tools, server_id}, _from, state) do
    case Map.get(state.tools, server_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tools ->
        {:reply, {:ok, tools}, state}
    end
  end

  def handle_call(:get_all_tools, _from, state) do
    all_tools = collect_all_tools_with_namespacing(state.tools)
    {:reply, all_tools, state}
  end

  def handle_call({:reload_configuration, config_path}, _from, state) do
    case Discovery.discover_servers(config_path) do
      {:ok, server_configs} ->
        new_state = reload_server_configurations(server_configs, state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to reload configuration: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:test_connection, server_config}, _from, state) do
    # Basic connectivity test without permanent connection
    case start_connection_internal(server_config) do
      {:ok, _connection_pid} ->
        {:reply, {:ok, :connected}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ping_server, server_id}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{status: :connected} = connection ->
        # Send ping and measure response time
        start_time = System.monotonic_time(:millisecond)

        case send_ping_to_connection(connection) do
          :ok ->
            response_time = System.monotonic_time(:millisecond) - start_time
            {:reply, {:ok, response_time}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      nil ->
        {:reply, {:error, :not_connected}, state}

      %ConnectionInfo{status: status} ->
        {:reply, {:error, {:invalid_status, status}}, state}
    end
  end

  def handle_call({:execute_tool, server_id, tool_name, params}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{status: :connected} = connection ->
        case execute_tool_on_connection(connection, tool_name, params) do
          {:ok, result} ->
            {:reply, {:ok, result}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      nil ->
        {:reply, {:error, :not_connected}, state}

      %ConnectionInfo{status: status} ->
        {:reply, {:error, {:invalid_status, status}}, state}
    end
  end

  def handle_call({:get_connection_metrics, server_id}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{} = connection ->
        metrics = gather_connection_metrics(connection)
        {:reply, {:ok, metrics}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_performance_metrics, server_id, timeframe_hours}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{} = connection ->
        metrics = gather_performance_metrics(connection, timeframe_hours)
        {:reply, {:ok, metrics}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_tool_usage_metrics, server_id, timeframe_hours}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{} = _connection ->
        metrics = gather_tool_usage_metrics(server_id, timeframe_hours)
        {:reply, {:ok, metrics}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_error_metrics, server_id, timeframe_hours}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{} = _connection ->
        metrics = gather_error_metrics(server_id, timeframe_hours)
        {:reply, {:ok, metrics}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:start_trace, server_id}, _from, state) do
    case Map.get(state.connections, server_id) do
      %ConnectionInfo{} = connection ->
        trace_id = generate_trace_id(server_id)

        case start_connection_trace(connection, trace_id) do
          :ok ->
            {:reply, {:ok, trace_id}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:stop_trace, trace_id}, _from, state) do
    case stop_connection_trace(trace_id) do
      {:ok, trace_data} ->
        {:reply, {:ok, trace_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:heartbeat, server_id}, state) do
    new_state = do_heartbeat(server_id, state)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle connection process death
    new_state = handle_connection_down(pid, reason, state)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("ConnectionManager received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ConnectionManager terminating: #{inspect(reason)}")

    # Clean up all timers
    Enum.each(state.heartbeat_timers, fn {_server_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    # Stop all connections
    Enum.each(state.connections, fn {server_id, connection_info} ->
      do_stop_connection(server_id, connection_info, state)
    end)

    :ok
  end

  ## Private Helper Functions

  defp do_start_connection(server_config, state) do
    server_id = Map.get(server_config, :id)

    case Discovery.start_server_connection(server_config) do
      {:ok, connection_pid} ->
        # Monitor the connection process
        Process.monitor(connection_pid)

        now = DateTime.utc_now()
        timestamp = System.system_time(:millisecond)
        heartbeat_interval = Map.get(server_config, :heartbeat_interval, 30_000)

        connection_info = %ConnectionInfo{
          server_id: server_id,
          connection_pid: connection_pid,
          # For now, they're the same
          transport_pid: connection_pid,
          status: :connecting,
          started_at: now,
          last_heartbeat: timestamp,
          heartbeat_interval: heartbeat_interval
        }

        health_status = %HealthStatus{
          server_id: server_id,
          status: :connecting,
          last_heartbeat: timestamp,
          error_count: 0,
          last_error: nil
        }

        # Start heartbeat timer if configured
        timer_ref = Process.send_after(self(), {:heartbeat, server_id}, heartbeat_interval)

        new_state = %{
          state
          | connections: Map.put(state.connections, server_id, connection_info),
            health_status: Map.put(state.health_status, server_id, health_status),
            heartbeat_timers: Map.put(state.heartbeat_timers, server_id, timer_ref)
        }

        Logger.info("Successfully started connection for server #{server_id}")
        {:reply, {:ok, connection_pid}, new_state}

      {:error, reason} ->
        Logger.error("Failed to start connection for server #{server_id}: #{inspect(reason)}")

        # Update circuit breaker on failure
        new_state = record_failure(state, server_id, server_config)
        {:reply, {:error, reason}, new_state}
    end
  end

  defp do_stop_connection(server_id, connection_info, state) do
    # Cancel heartbeat timer
    case Map.get(state.heartbeat_timers, server_id) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end

    # Stop the connection process (this is transport-specific)
    if Process.alive?(connection_info.connection_pid) do
      GenServer.stop(connection_info.connection_pid, :normal)
    end

    # Remove from state
    %{
      state
      | connections: Map.delete(state.connections, server_id),
        tools: Map.delete(state.tools, server_id),
        health_status: Map.delete(state.health_status, server_id),
        heartbeat_timers: Map.delete(state.heartbeat_timers, server_id)
    }
  end

  defp do_heartbeat(server_id, state) do
    case Map.get(state.connections, server_id) do
      nil ->
        # Connection no longer exists, ignore heartbeat
        state

      _connection_info ->
        timestamp = System.system_time(:millisecond)

        # Update health status
        updated_health =
          Map.update!(state.health_status, server_id, fn health ->
            %{health | last_heartbeat: timestamp, status: :connected}
          end)

        # Schedule next heartbeat using the server's configured interval
        heartbeat_interval =
          case Map.get(state.connections, server_id) do
            %ConnectionInfo{heartbeat_interval: interval} -> interval
            _ -> 30_000
          end

        timer_ref = Process.send_after(self(), {:heartbeat, server_id}, heartbeat_interval)

        %{
          state
          | health_status: updated_health,
            heartbeat_timers: Map.put(state.heartbeat_timers, server_id, timer_ref)
        }
    end
  end

  defp handle_connection_down(pid, reason, state) do
    # Find which server this PID belonged to
    case find_server_by_pid(state.connections, pid) do
      nil ->
        Logger.debug("Unknown connection process died: #{inspect(pid)}")
        state

      {server_id, _connection_info} ->
        Logger.warning("Connection for server #{server_id} died: #{inspect(reason)}")

        # Update health status to error
        updated_health =
          Map.update(state.health_status, server_id, nil, fn health ->
            %{health | status: :error, error_count: health.error_count + 1}
          end)

        # Remove the connection but keep health status for monitoring
        %{
          state
          | connections: Map.delete(state.connections, server_id),
            health_status: updated_health
        }
    end
  end

  defp find_server_by_pid(connections, pid) do
    Enum.find(connections, fn {_server_id, connection_info} ->
      connection_info.connection_pid == pid
    end)
  end

  defp collect_all_tools_with_namespacing(tools_map) do
    # Collect all tools and handle namespace conflicts by prefixing
    tool_names = collect_tool_names(tools_map)
    conflicts = find_conflicting_names(tool_names)

    Enum.flat_map(tools_map, fn {server_id, tools} ->
      Enum.map(tools, fn tool ->
        tool_name = Map.get(tool, :name) || Map.get(tool, "name")

        if tool_name in conflicts do
          # Prefix with server ID to avoid conflicts
          prefixed_name = "#{server_id}__#{tool_name}"
          Map.put(tool, :name, prefixed_name)
        else
          tool
        end
      end)
    end)
  end

  defp collect_tool_names(tools_map) do
    Enum.flat_map(tools_map, fn {_server_id, tools} ->
      Enum.map(tools, fn tool ->
        Map.get(tool, :name) || Map.get(tool, "name")
      end)
    end)
  end

  defp find_conflicting_names(tool_names) do
    tool_names
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
  end

  defp check_circuit_breaker(state, server_id, server_config) do
    max_failures = Map.get(server_config, :max_failures, 3)
    _failure_window = Map.get(server_config, :failure_window, 60_000)

    case Map.get(state.circuit_breakers, server_id) do
      nil ->
        # No circuit breaker yet, allow connection
        {:ok, state}

      %CircuitBreaker{state: :open} ->
        {:error, :circuit_open}

      %CircuitBreaker{failures: failures} when failures >= max_failures ->
        # Too many failures, open circuit
        new_breaker = %CircuitBreaker{
          failures: failures,
          failure_window_start: System.system_time(:millisecond),
          state: :open
        }

        _new_state = %{
          state
          | circuit_breakers: Map.put(state.circuit_breakers, server_id, new_breaker)
        }

        {:error, :circuit_open}

      _breaker ->
        {:ok, state}
    end
  end

  defp record_failure(state, server_id, server_config) do
    failure_window = Map.get(server_config, :failure_window, 60_000)
    current_time = System.system_time(:millisecond)

    breaker =
      Map.get(state.circuit_breakers, server_id, %CircuitBreaker{
        failures: 0,
        failure_window_start: current_time,
        state: :closed
      })

    # Reset if outside failure window
    breaker =
      if current_time - breaker.failure_window_start > failure_window do
        %CircuitBreaker{
          failures: 1,
          failure_window_start: current_time,
          state: :closed
        }
      else
        %{breaker | failures: breaker.failures + 1}
      end

    %{
      state
      | circuit_breakers: Map.put(state.circuit_breakers, server_id, breaker)
    }
  end

  defp reload_server_configurations(server_configs, state) do
    # Get current server IDs
    current_servers = MapSet.new(Map.keys(state.connections))
    new_servers = MapSet.new(Enum.map(server_configs, & &1.id))

    # Find servers to add and remove
    to_add = MapSet.difference(new_servers, current_servers)
    to_remove = MapSet.difference(current_servers, new_servers)

    # Remove old servers
    state_after_removal =
      Enum.reduce(to_remove, state, fn server_id, acc_state ->
        case Map.get(acc_state.connections, server_id) do
          nil -> acc_state
          connection_info -> do_stop_connection(server_id, connection_info, acc_state)
        end
      end)

    # Add new servers
    _state_after_addition =
      Enum.reduce(to_add, state_after_removal, fn server_id, acc_state ->
        server_config = Enum.find(server_configs, &(&1.id == server_id))

        case do_start_connection(server_config, acc_state) do
          {:reply, {:ok, _pid}, new_state} -> new_state
          {:reply, {:error, _reason}, new_state} -> new_state
        end
      end)
  end

  ## Helper Functions for New API Methods

  defp start_connection_internal(server_config) do
    # Placeholder implementation - would start actual MCP connection
    case validate_server_config(server_config) do
      :ok -> {:ok, :test_connection}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_server_config(config) when is_map(config) do
    required_keys = ["command", "url", "httpUrl"]

    if Enum.any?(required_keys, fn key -> Map.has_key?(config, key) end) do
      :ok
    else
      {:error, :invalid_config}
    end
  end

  defp validate_server_config(_), do: {:error, :invalid_config}

  defp send_ping_to_connection(_connection) do
    # Placeholder implementation - would send actual ping to MCP server
    :ok
  end

  defp execute_tool_on_connection(_connection, _tool_name, _params) do
    # Placeholder implementation - would execute tool on MCP server
    {:ok, %{result: "placeholder_result"}}
  end

  defp gather_connection_metrics(connection) do
    %{
      server_id: connection.server_id,
      status: connection.status,
      uptime: calculate_uptime(connection.started_at),
      last_heartbeat: connection.last_heartbeat,
      heartbeat_interval: connection.heartbeat_interval
    }
  end

  defp gather_performance_metrics(_connection, _timeframe_hours) do
    # Placeholder implementation - would gather actual performance metrics
    %{
      response_time_avg: 150,
      response_time_max: 500,
      request_count: 100,
      error_rate: 0.02
    }
  end

  defp gather_tool_usage_metrics(_server_id, _timeframe_hours) do
    # Placeholder implementation - would gather actual tool usage metrics
    %{
      total_executions: 50,
      most_used_tool: "read_file",
      average_execution_time: 200
    }
  end

  defp gather_error_metrics(_server_id, _timeframe_hours) do
    # Placeholder implementation - would gather actual error metrics
    %{
      total_errors: 2,
      error_rate: 0.02,
      common_errors: ["connection_timeout", "invalid_params"]
    }
  end

  defp generate_trace_id(server_id) do
    timestamp = System.system_time(:millisecond)
    "trace_#{server_id}_#{timestamp}"
  end

  defp start_connection_trace(_connection, _trace_id) do
    # Placeholder implementation - would start actual connection tracing
    :ok
  end

  defp stop_connection_trace(trace_id) do
    # Placeholder implementation - would stop tracing and return data
    {:ok,
     %{
       trace_id: trace_id,
       requests: [],
       responses: [],
       timing_data: %{}
     }}
  end

  defp calculate_uptime(started_at) when is_nil(started_at), do: 0

  defp calculate_uptime(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end
end

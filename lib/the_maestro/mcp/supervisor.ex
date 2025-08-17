defmodule TheMaestro.MCP.Supervisor do
  @moduledoc """
  Main supervisor for the MCP subsystem.

  Manages the supervision tree for all MCP-related processes:
  - MCP Discovery GenServer for server configuration management
  - MCP Registry for server tracking and tool namespace management
  - Connection Manager for connection pool management
  - Dynamic Supervisor for individual server connections
  """

  use Supervisor
  require Logger

  @doc """
  Start the MCP Supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # MCP Registry for server tracking and tool namespace management
      {TheMaestro.MCP.Registry, []},

      # Connection Manager for connection pool management
      {TheMaestro.MCP.ConnectionManager, []},

      # Dynamic Supervisor for individual server connections
      {DynamicSupervisor, strategy: :one_for_one, name: TheMaestro.MCP.ConnectionSupervisor}
    ]

    Logger.info("Starting MCP Supervisor with #{length(children)} children")

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Get the PID of the Connection Supervisor for dynamically starting server connections.
  """
  def connection_supervisor do
    TheMaestro.MCP.ConnectionSupervisor
  end

  @doc """
  Get the PID of the Registry for server and tool management.
  """
  def registry do
    TheMaestro.MCP.Registry
  end

  @doc """
  Access the Discovery module for configuration management.
  Discovery is a utility module, not a supervised process.
  """
  def discovery do
    TheMaestro.MCP.Discovery
  end

  @doc """
  Get the PID of the Connection Manager for connection pool management.
  """
  def connection_manager do
    TheMaestro.MCP.ConnectionManager
  end
end

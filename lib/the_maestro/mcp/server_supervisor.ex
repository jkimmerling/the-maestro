defmodule TheMaestro.MCP.ServerSupervisor do
  @moduledoc """
  Supervisor for MCP server processes.

  This module provides a simplified interface for managing MCP server processes
  through the ConnectionManager. It's designed to be compatible with CLI commands
  that expect this interface.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}

  @doc """
  Start an MCP server.
  """
  @spec start_server(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_server(server_name) do
    start_server(server_name, %{})
  end

  @doc """
  Start an MCP server with options.
  """
  @spec start_server(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start_server(server_name, _options) do
    # Delegate to ConnectionManager
    case get_server_config(server_name) do
      {:ok, server_config} ->
        ConnectionManager.start_connection(ConnectionManager, server_config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stop an MCP server.
  """
  @spec stop_server(String.t()) :: :ok | {:error, term()}
  def stop_server(server_name) do
    ConnectionManager.stop_connection(ConnectionManager, server_name)
  end

  @doc """
  Restart an MCP server.
  """
  @spec restart_server(String.t()) :: {:ok, pid()} | {:error, term()}
  def restart_server(server_name) do
    case stop_server(server_name) do
      :ok ->
        start_server(server_name)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the process ID for a running server.
  """
  @spec get_server_pid(String.t()) :: {:ok, pid()} | {:error, term()}
  def get_server_pid(server_name) do
    case ConnectionManager.get_connection(ConnectionManager, server_name) do
      {:ok, %{connection_pid: pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Functions

  defp get_server_config(server_name) do
    case Config.get_configuration() do
      {:ok, config} ->
        case get_in(config, ["mcpServers", server_name]) do
          nil ->
            {:error, :server_not_found}

          server_config ->
            {:ok, Map.put(server_config, "id", server_name)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end

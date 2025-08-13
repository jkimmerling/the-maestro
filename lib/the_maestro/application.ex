defmodule TheMaestro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias TheMaestro.Tooling.Tools.FileSystem
  alias TheMaestro.Tooling.Tools.OpenAPI
  alias TheMaestro.Tooling.Tools.Shell

  @impl true
  def start(_type, _args) do
    # Check if we're running in escript mode by examining the process name
    is_escript = running_as_escript?()

    children =
      if is_escript do
        # Minimal startup for TUI mode
        [
          # Start the Registry for agent processes
          {Registry, keys: :unique, name: TheMaestro.Agents.Registry},
          # Start the DynamicSupervisor for agent processes
          {TheMaestro.Agents.DynamicSupervisor, []},
          # Start the Tooling registry GenServer
          TheMaestro.Tooling
        ]
      else
        # Full Phoenix application startup
        [
          TheMaestroWeb.Telemetry,
          TheMaestro.Repo,
          {DNSCluster, query: Application.get_env(:the_maestro, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: TheMaestro.PubSub},
          # Start the Finch HTTP client for sending emails
          {Finch, name: TheMaestro.Finch},
          # Start the Registry for agent processes
          {Registry, keys: :unique, name: TheMaestro.Agents.Registry},
          # Start the DynamicSupervisor for agent processes
          {TheMaestro.Agents.DynamicSupervisor, []},
          # Start the Tooling registry GenServer
          TheMaestro.Tooling,
          # Start a worker by calling: TheMaestro.Worker.start_link(arg)
          # {TheMaestro.Worker, arg},
          # Start to serve requests, typically the last entry
          TheMaestroWeb.Endpoint
        ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheMaestro.Supervisor]

    # Register all tools after supervisor starts
    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        # Register built-in tools
        if is_escript do
          # Register only essential tools for TUI mode
          Shell.register_tool()
        else
          # Register all tools for full application
          FileSystem.register_tools()
          Shell.register_tool()
          OpenAPI.register_tool()
        end

        result

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TheMaestroWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Helper function to detect if running as escript
  defp running_as_escript? do
    System.get_env("RUNNING_AS_ESCRIPT") == "true" or
      String.contains?(to_string(System.argv()), "maestro_tui") or
      escript_in_arguments?()
  rescue
    _ -> false
  end

  defp escript_in_arguments? do
    case :init.get_arguments() do
      [] ->
        false

      args ->
        Enum.any?(args, fn arg -> String.contains?(to_string(arg), "maestro_tui") end)
    end
  end
end

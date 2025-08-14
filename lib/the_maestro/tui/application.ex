defmodule TheMaestro.TUI.Application do
  @moduledoc """
  Minimal OTP Application for TUI mode.

  This application module starts only the essential services needed for the TUI,
  avoiding Phoenix web server, file watchers, and other web-related services.
  """

  use Application

  alias TheMaestro.Tooling.Tools.Shell

  @impl true
  def start(_type, _args) do
    children = [
      # Start HTTPoison (needed for device authorization flow)
      {Finch, name: TheMaestro.Finch},
      # Start the Registry for agent processes (needed for core functionality)
      {Registry, keys: :unique, name: TheMaestro.Agents.Registry},
      # Start PubSub for real-time communication (needed for agent messaging)
      {Phoenix.PubSub, name: TheMaestro.PubSub},
      # Start the DynamicSupervisor for agent processes
      {TheMaestro.Agents.DynamicSupervisor, []},
      # Start the Tooling registry GenServer (needed for agent tools)
      TheMaestro.Tooling,
      # Start embedded web server for OAuth device authorization
      {TheMaestro.TUI.EmbeddedServer, [port: 4001]}
    ]

    # Start with minimal supervision tree
    opts = [strategy: :one_for_one, name: TheMaestro.TUI.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        # Register only essential tools for TUI mode
        Shell.register_tool()
        result

      error ->
        error
    end
  end

  @impl true
  def config_change(_changed, _new, _removed) do
    # No Phoenix endpoint to update in TUI mode
    :ok
  end
end

defmodule TheMaestro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TheMaestroWeb.Telemetry,
      TheMaestro.Repo,
      {DNSCluster, query: Application.get_env(:the_maestro, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TheMaestro.PubSub},
      # Start a worker by calling: TheMaestro.Worker.start_link(arg)
      # {TheMaestro.Worker, arg},
      # Start to serve requests, typically the last entry
      TheMaestroWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheMaestro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TheMaestroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

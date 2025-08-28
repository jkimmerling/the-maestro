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
      # Finch pools for HTTP client connection pooling
      {Finch,
       name: :anthropic_finch,
       pools: %{"https://api.anthropic.com" => [size: 10, count: 2]}},
      {Finch,
       name: :openai_finch,
       pools: %{"https://api.openai.com" => [size: 10, count: 2]}},
      {Finch,
       name: :gemini_finch,
       pools: %{"https://generativelanguage.googleapis.com" => [size: 10, count: 2]}},
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

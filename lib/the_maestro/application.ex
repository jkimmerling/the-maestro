defmodule TheMaestro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    finch_pools = Application.get_env(:the_maestro, :finch_pools, [])

    children = [
      TheMaestroWeb.Telemetry,
      TheMaestro.Vault,
      TheMaestro.Repo,
      {DNSCluster, query: Application.get_env(:the_maestro, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:the_maestro, Oban)},
      # Finch pools for HTTP client connection pooling
      finch_child_spec(:anthropic_finch, finch_pools[:anthropic]),
      finch_child_spec(:openai_finch, finch_pools[:openai]),
      finch_child_spec(:gemini_finch, finch_pools[:gemini]),
      {Phoenix.PubSub, name: TheMaestro.PubSub},
      # Provider registry for automatic discovery and validation
      TheMaestro.ProviderRegistry,
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

  # Helper function to build Finch child specifications from configuration
  defp finch_child_spec(name, config) when is_list(config) do
    pool_config = Keyword.get(config, :pool_config, size: 10, count: 1)
    base_url = Keyword.get(config, :base_url, "https://example.com")

    {Finch, name: name, pools: %{base_url => pool_config}}
  end

  defp finch_child_spec(name, _invalid_config) do
    # Fallback configuration if config is missing or invalid
    {Finch, name: name, pools: %{"https://api.anthropic.com" => [size: 10, count: 1]}}
  end
end

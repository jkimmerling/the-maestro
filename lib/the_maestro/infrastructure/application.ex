defmodule TheMaestro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias TheMaestro.Cache.Redis, as: RedisCache

  @impl true
  def start(_type, _args) do
    finch_pools = Application.get_env(:the_maestro, :finch_pools, [])

    children = base_children() ++ conditional_children(finch_pools)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheMaestro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      TheMaestroWeb.Telemetry,
      TheMaestro.Vault,
      TheMaestro.Repo,
      {Phoenix.PubSub, name: TheMaestro.PubSub},
      TheMaestroWeb.Endpoint
    ]
  end

  defp conditional_children(finch_pools) do
    if Mix.env() == :test do
      [
        # Minimal services for tests (Redis mock started in test_helper.exs)
        {Oban, Application.fetch_env!(:the_maestro, Oban)},
        finch_child_spec(:anthropic_finch, finch_pools[:anthropic]),
        finch_child_spec(:openai_finch, finch_pools[:openai]),
        finch_child_spec(:gemini_finch, finch_pools[:gemini]),
        # Include MCP tools cache for testing with Redis mock
        TheMaestro.MCP.UnifiedToolsCache
      ]
    else
      [
        {DNSCluster, query: Application.get_env(:the_maestro, :dns_cluster_query) || :ignore},
        {Oban, Application.fetch_env!(:the_maestro, Oban)},
        # Redis cache connection (required for SuppliedContext caching)
        RedisCache,
        # Finch pools for HTTP client connection pooling
        finch_child_spec(:anthropic_finch, finch_pools[:anthropic]),
        finch_child_spec(:openai_finch, finch_pools[:openai]),
        finch_child_spec(:gemini_finch, finch_pools[:gemini]),
        # Unified MCP tools cache (GenServer with hourly refresh)
        TheMaestro.MCP.UnifiedToolsCache,
        # Session streaming manager (Task.Supervisor + Manager)
        {Task.Supervisor, name: TheMaestro.Sessions.TaskSup},
        TheMaestro.Sessions.Manager,
        # OAuth state store and runtime manager (server starts on-demand)
        TheMaestro.OAuthState,
        TheMaestro.OAuthCallbackRuntime,
        # Provider registry for automatic discovery and validation
        TheMaestro.ProviderRegistry
      ]
    end
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

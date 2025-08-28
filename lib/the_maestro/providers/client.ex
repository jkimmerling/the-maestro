defmodule TheMaestro.Providers.Client do
  @moduledoc """
  Tesla-based HTTP client with Finch adapter for multi-provider API communication.

  Provides configured Tesla clients for different AI providers with connection pooling,
  middleware for JSON handling, logging, and retry capabilities.
  """

  @type provider :: :anthropic | :openai | :gemini
  @type pool_name :: atom()
  @type client_config :: %{
          base_url: String.t(),
          pool: pool_name()
        }

  @doc """
  Builds a Tesla client configured for the specified provider.

  ## Parameters

    * `provider` - The provider atom (`:anthropic`, `:openai`, or `:gemini`)
    
  ## Returns

    * `Tesla.Client.t()` - Configured Tesla client for valid providers
    * `{:error, :invalid_provider}` - For invalid provider atoms
    
  ## Examples

      iex> client = TheMaestro.Providers.Client.build_client(:anthropic)
      iex> Tesla.get(client, "/health")
      
      iex> TheMaestro.Providers.Client.build_client(:invalid)
      {:error, :invalid_provider}
  """
  @spec build_client(provider()) :: Tesla.Client.t() | {:error, :invalid_provider}
  def build_client(provider) when provider in [:anthropic, :openai, :gemini] do
    config = get_provider_config(provider)

    middleware = [
      # Base URL middleware
      {Tesla.Middleware.BaseUrl, config.base_url},
      # JSON middleware for request/response serialization
      Tesla.Middleware.JSON,
      # Logger middleware for request/response logging
      Tesla.Middleware.Logger,
      # Retry middleware for handling transient failures
      {Tesla.Middleware.Retry, delay: 500, max_retries: 3, max_delay: 4_000}
    ]

    # Configure Finch adapter with appropriate pool
    adapter = {Tesla.Adapter.Finch, name: config.pool}

    Tesla.client(middleware, adapter)
  end

  def build_client(_invalid_provider), do: {:error, :invalid_provider}

  # Private function to get provider configuration
  @spec get_provider_config(provider()) :: client_config()
  defp get_provider_config(:anthropic) do
    %{
      base_url: "https://api.anthropic.com",
      pool: :anthropic_finch
    }
  end

  defp get_provider_config(:openai) do
    %{
      base_url: "https://api.openai.com",
      pool: :openai_finch
    }
  end

  defp get_provider_config(:gemini) do
    %{
      base_url: "https://generativelanguage.googleapis.com",
      pool: :gemini_finch
    }
  end
end

defmodule TheMaestro.Providers.Client do
  @moduledoc """
  Tesla-based HTTP client with Finch adapter for multi-provider API communication.

  Provides configured Tesla clients for different AI providers with connection pooling,
  middleware for JSON handling, logging, and retry capabilities. Supports multiple
  authentication modes including API key and OAuth Bearer authentication for Anthropic API.

  ## Authentication Support

  ### API Key Authentication

  Anthropic provider supports API key authentication with exact header requirements:

  - `x-api-key`: API key from configuration
  - `anthropic-version`: "2023-06-01" 
  - `anthropic-beta`: "messages-2023-12-15"
  - `user-agent`: "llxprt/1.0"
  - `accept`: "application/json"
  - `x-client-version`: "1.0.0"

  ### OAuth Bearer Authentication

  Anthropic provider supports OAuth 2.0 Bearer authentication with exact header requirements:

  - `authorization`: "Bearer [ACCESS_TOKEN]" (replaces x-api-key)
  - `anthropic-version`: "2023-06-01"
  - `anthropic-beta`: "oauth-2025-04-20" 
  - `user-agent`: "llxprt/1.0"
  - `accept`: "application/json"
  - `x-client-version`: "1.0.0"

  Headers are injected in exact order for compatibility with llxprt reference.

  ## Configuration

  Configure Anthropic API key in runtime configuration:

      config :the_maestro, :anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY")

  ## Examples

      # Default API key authentication
      client = TheMaestro.Providers.Client.build_client(:anthropic)
      
      # Explicit API key authentication  
      client = TheMaestro.Providers.Client.build_client(:anthropic, :api_key)
      
      # OAuth Bearer authentication
      client = TheMaestro.Providers.Client.build_client(:anthropic, :oauth)
      
      # Make authenticated API calls
      {:ok, response} = Tesla.post(client, "/v1/messages", request_body)

  ## Error Handling

  Returns `{:error, :missing_api_key}` when Anthropic API key is not configured.
  Returns `{:error, :not_found}` when OAuth token is not found in database.
  Returns `{:error, :expired}` when OAuth token has expired.
  Returns `{:error, :invalid_provider}` for unsupported provider atoms.
  """

  alias TheMaestro.Auth.OAuthToken
  alias TheMaestro.Providers.AnthropicConfig

  @type provider :: :anthropic | :openai | :gemini
  @type pool_name :: atom()
  @type auth_type :: :api_key | :oauth
  @type client_config :: %{
          base_url: String.t(),
          pool: pool_name()
        }

  @doc """
  Builds a Tesla client configured for the specified provider.

  ## Parameters

    * `provider` - The provider atom (`:anthropic`, `:openai`, or `:gemini`)
    * `auth_type` - Authentication type (`:api_key` or `:oauth`). Defaults to `:api_key`
    
  ## Returns

    * `Tesla.Client.t()` - Configured Tesla client for valid providers
    * `{:error, :invalid_provider}` - For invalid provider atoms
    * `{:error, :missing_api_key}` - When API key is not configured
    
  ## Examples

      iex> client = TheMaestro.Providers.Client.build_client(:anthropic)
      iex> Tesla.get(client, "/health")
      
      iex> client = TheMaestro.Providers.Client.build_client(:anthropic, :api_key)
      iex> Tesla.get(client, "/v1/messages")
      
      iex> TheMaestro.Providers.Client.build_client(:invalid)
      {:error, :invalid_provider}
  """
  @spec build_client(provider()) ::
          Tesla.Client.t() | {:error, :invalid_provider | :missing_api_key | :not_found | :expired}
  @spec build_client(provider(), auth_type()) ::
          Tesla.Client.t() | {:error, :invalid_provider | :missing_api_key | :not_found | :expired}
  def build_client(provider) when provider in [:anthropic, :openai, :gemini] do
    build_client(provider, :api_key)
  end

  def build_client(_invalid_provider), do: {:error, :invalid_provider}

  def build_client(provider, auth_type) when provider in [:anthropic, :openai, :gemini] do
    case build_middleware(provider, auth_type) do
      {:ok, middleware} ->
        config = get_provider_config(provider)
        adapter = {Tesla.Adapter.Finch, name: config.pool}
        Tesla.client(middleware, adapter)

      {:error, _reason} = error ->
        error
    end
  end

  def build_client(_invalid_provider, _auth_type), do: {:error, :invalid_provider}

  # OAuth token retrieval function
  @spec get_oauth_token(provider()) :: {:ok, OAuthToken.t()} | {:error, :not_found | :expired}
  defp get_oauth_token(_provider) do
    # FIXME: Implement database lookup for OAuth tokens from saved_authentications table
    # For now, return error until database integration is complete
    # This will be implemented in Task 4
    #
    # Future implementation will:
    # 1. Query saved_authentications table for provider OAuth tokens
    # 2. Check token expiry and return :expired if needed
    # 3. Return {:ok, oauth_token} for valid tokens
    {:error, :not_found}
  end

  # Private function to build middleware stack based on provider and auth type
  @spec build_middleware(provider(), auth_type()) :: {:ok, list()} | {:error, :missing_api_key | :not_found | :expired}
  defp build_middleware(:anthropic, :api_key) do
    case AnthropicConfig.load() do
      {:ok, config} ->
        middleware = [
          # Base URL middleware
          {Tesla.Middleware.BaseUrl, config.base_url},
          # Anthropic API headers in exact order as specified
          {Tesla.Middleware.Headers,
           [
             {"x-api-key", config.api_key},
             {"anthropic-version", config.version},
             {"anthropic-beta", config.beta},
             {"user-agent", config.user_agent},
             {"accept", config.accept},
             {"x-client-version", config.client_version}
           ]},
          # JSON middleware for request/response serialization
          Tesla.Middleware.JSON,
          # Logger middleware for request/response logging
          Tesla.Middleware.Logger,
          # Retry middleware for handling transient failures
          {Tesla.Middleware.Retry, delay: 500, max_retries: 3, max_delay: 4_000}
        ]

        {:ok, middleware}

      {:error, :missing_api_key} ->
        {:error, :missing_api_key}
    end
  end

  defp build_middleware(provider, :api_key) when provider in [:openai, :gemini] do
    # For other providers, use basic middleware without authentication headers
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

    {:ok, middleware}
  end

  defp build_middleware(:anthropic, :oauth) do
    case get_oauth_token(:anthropic) do
      {:ok, oauth_token} ->
        config = get_provider_config(:anthropic)

        middleware = [
          # Base URL middleware
          {Tesla.Middleware.BaseUrl, config.base_url},
          # OAuth Bearer token headers (replaces x-api-key)
          {Tesla.Middleware.Headers,
           [
             {"authorization", "Bearer #{oauth_token.access_token}"},
             {"anthropic-version", "2023-06-01"},
             {"anthropic-beta", "oauth-2025-04-20"},
             {"user-agent", "llxprt/1.0"},
             {"accept", "application/json"},
             {"x-client-version", "1.0.0"}
           ]},
          # JSON middleware for request/response serialization
          Tesla.Middleware.JSON,
          # Logger middleware for request/response logging
          Tesla.Middleware.Logger,
          # Retry middleware for handling transient failures
          {Tesla.Middleware.Retry, delay: 500, max_retries: 3, max_delay: 4_000}
        ]

        {:ok, middleware}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_middleware(_provider, :oauth) do
    # OAuth not implemented for other providers yet
    {:error, :oauth_not_implemented}
  end

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

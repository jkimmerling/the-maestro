defmodule TheMaestro.Providers.Client do
  @moduledoc """
  Tesla-based HTTP client with Finch adapter for multi-provider API communication.

  Provides configured Tesla clients for different AI providers with connection pooling,
  middleware for JSON handling, logging, and retry capabilities. Supports multiple
  authentication modes including API key and OAuth Bearer authentication.

  ## Authentication Support

  ### API Key Authentication

  **Anthropic provider** supports API key authentication with exact header requirements:

  - `x-api-key`: API key from configuration
  - `anthropic-version`: "2023-06-01" 
  - `anthropic-beta`: "messages-2023-12-15"
  - `user-agent`: "llxprt/1.0"
  - `accept`: "application/json"
  - `x-client-version`: "1.0.0"

  **OpenAI provider** supports Bearer token authentication with exact header requirements:

  - `authorization`: "Bearer [API_KEY]"
  - `openai-organization`: Organization ID from configuration
  - `openai-beta`: "assistants v2"
  - `user-agent`: "llxprt/1.0"
  - `accept`: "application/json"
  - `x-client-version`: "1.0.0"

  ### OAuth Bearer Authentication

  Anthropic provider supports OAuth 2.0 Bearer authentication with database-backed token storage:

  - `authorization`: "Bearer [ACCESS_TOKEN]" (replaces `x-api-key` header)
  - `anthropic-version`: "2023-06-01"
  - `anthropic-beta`: "oauth-2025-04-20" (OAuth-specific beta version)
  - `user-agent`: "llxprt/1.0"
  - `accept`: "application/json"
  - `x-client-version`: "1.0.0"

  OAuth tokens are retrieved from the `saved_authentications` database table with automatic
  expiry validation. If a token is expired or missing, the client returns an error for
  handling by the calling code or automatic refresh by the TokenRefreshWorker.

  ## OAuth Token Refresh Workflow

  The system includes automated token refresh using Oban background jobs:

  1. **Token Storage**: OAuth tokens stored in `saved_authentications` table with encryption
  2. **Expiry Monitoring**: Client checks token expiry on each use
  3. **Automatic Refresh**: TokenRefreshWorker refreshes tokens at 80% of their lifetime
  4. **Database Updates**: New tokens atomically replace expired tokens
  5. **Error Recovery**: Network failures retry with exponential backoff

  See `TheMaestro.Workers.TokenRefreshWorker` for refresh implementation details.

  ## Configuration

  ### API Key Authentication

  Configure Anthropic API key in runtime configuration:

      config :the_maestro, :anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY")

  Configure OpenAI API key and organization ID in runtime configuration:

      config :the_maestro, :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        organization_id: System.get_env("OPENAI_ORG_ID")

  ### OAuth Authentication

  OAuth tokens are stored in the database and retrieved automatically.
  Configure OAuth client credentials for token refresh:

      config :the_maestro, :anthropic_oauth_client_id,
        System.get_env("ANTHROPIC_CLIENT_ID")

  Environment variables:
  - `ANTHROPIC_CLIENT_ID`: OAuth client ID for token refresh
  - `OPENAI_API_KEY`: OpenAI API key for authentication
  - `OPENAI_ORG_ID`: OpenAI organization ID for API access

  ## Examples

      # Default API key authentication
      client = TheMaestro.Providers.Client.build_client(:anthropic)
      client = TheMaestro.Providers.Client.build_client(:openai)
      
      # Explicit API key authentication  
      client = TheMaestro.Providers.Client.build_client(:anthropic, :api_key)
      client = TheMaestro.Providers.Client.build_client(:openai, :api_key)
      
      # OAuth Bearer authentication (Anthropic only)
      client = TheMaestro.Providers.Client.build_client(:anthropic, :oauth)
      
      # Make authenticated API calls
      {:ok, response} = Tesla.post(client, "/v1/messages", request_body)
      {:ok, response} = Tesla.post(client, "/v1/chat/completions", request_body)

  ## Error Handling

  Returns `{:error, :missing_api_key}` when API key is not configured.
  Returns `{:error, :missing_org_id}` when OpenAI organization ID is not configured.
  Returns `{:error, :not_found}` when OAuth token is not found in database.
  Returns `{:error, :expired}` when OAuth token has expired.
  Returns `{:error, :invalid_provider}` for unsupported provider atoms.
  """

  alias TheMaestro.Auth.OAuthToken
  alias TheMaestro.Providers.AnthropicConfig
  alias TheMaestro.Providers.OpenAIConfig
  alias TheMaestro.SavedAuthentication

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
          Tesla.Client.t()
          | {:error, :invalid_provider | :missing_api_key | :missing_org_id | :not_found | :expired}
  @spec build_client(provider(), auth_type()) ::
          Tesla.Client.t()
          | {:error, :invalid_provider | :missing_api_key | :missing_org_id | :not_found | :expired}
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
  defp get_oauth_token(provider) do
    import Ecto.Query, warn: false
    alias TheMaestro.{Repo, SavedAuthentication}

    # Query for OAuth token for the specified provider
    query =
      from sa in SavedAuthentication,
        where: sa.provider == ^provider and sa.auth_type == :oauth,
        select: sa

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %SavedAuthentication{credentials: credentials, expires_at: expires_at} ->
        # Check if token has expired
        if expires_at && DateTime.compare(DateTime.utc_now(), expires_at) != :lt do
          {:error, :expired}
        else
          # Convert stored credentials to OAuthToken struct
          oauth_token = %OAuthToken{
            access_token: Map.get(credentials, "access_token"),
            refresh_token: Map.get(credentials, "refresh_token"),
            expiry: if(expires_at, do: DateTime.to_unix(expires_at), else: nil),
            scope: Map.get(credentials, "scope"),
            token_type: Map.get(credentials, "token_type", "Bearer")
          }

          {:ok, oauth_token}
        end
    end
  end

  # Private function to build middleware stack based on provider and auth type
  @spec build_middleware(provider(), auth_type()) ::
          {:ok, list()} | {:error, :missing_api_key | :missing_org_id | :not_found | :expired}
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

  defp build_middleware(:openai, :api_key) do
    case OpenAIConfig.load() do
      {:ok, config} ->
        middleware = [
          # Base URL middleware
          {Tesla.Middleware.BaseUrl, config.base_url},
          # OpenAI API headers in exact order as specified
          {Tesla.Middleware.Headers,
           [
             {"authorization", "Bearer #{config.api_key}"},
             {"openai-organization", config.organization_id},
             {"openai-beta", config.beta_version},
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_middleware(provider, :api_key) when provider in [:gemini] do
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
          # OAuth Bearer token headers (must match Claude Code exactly)
          {Tesla.Middleware.Headers,
           [
             {"connection", "keep-alive"},
             {"accept", "application/json"},
             {"x-stainless-retry-count", "0"},
             {"x-stainless-timeout", "60"},
             {"x-stainless-lang", "js"},
             {"x-stainless-package-version", "0.55.1"},
             {"x-stainless-os", "MacOS"},
             {"x-stainless-arch", "arm64"},
             {"x-stainless-runtime", "node"},
             {"x-stainless-runtime-version", "v23.11.0"},
             {"anthropic-dangerous-direct-browser-access", "true"},
             {"anthropic-version", "2023-06-01"},
             {"authorization", "Bearer #{oauth_token.access_token}"},
             {"x-app", "cli"},
             {"user-agent", "claude-cli/1.0.81 (external, cli)"},
             {"content-type", "application/json"},
             {"anthropic-beta",
              "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"},
             {"x-stainless-helper-method", "stream"},
             {"accept-language", "*"},
             {"sec-fetch-mode", "cors"},
             {"accept-encoding", "gzip, deflate, br"}
           ]},
          # JSON middleware for request encoding
          Tesla.Middleware.JSON,
          # Custom OAuth response middleware for decompression + JSON parsing
          {__MODULE__.OAuthResponseMiddleware, []},
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

  # Custom middleware for handling OAuth responses with compression
  defmodule OAuthResponseMiddleware do
    @moduledoc """
    Custom Tesla middleware for handling compressed OAuth responses from Anthropic API.
    Decompresses gzipped responses and parses JSON, similar to llxprt-code implementation.
    """

    @behaviour Tesla.Middleware

    def call(env, next, _options) do
      with {:ok, env} <- Tesla.run(env, next) do
        {:ok, decompress_and_decode_response(env)}
      end
    end

    defp decompress_and_decode_response(%Tesla.Env{body: body, headers: headers} = env)
         when is_binary(body) do
      # Decompress response if needed
      decompressed_body = decompress_response_if_needed(body, headers)

      # Parse JSON
      case Jason.decode(decompressed_body) do
        {:ok, decoded} -> %{env | body: decoded}
        # Return original if JSON parsing fails
        {:error, _} -> env
      end
    end

    defp decompress_and_decode_response(env), do: env

    defp decompress_response_if_needed(body, headers) do
      content_encoding =
        headers
        |> Enum.find(fn {key, _} -> String.downcase(key) == "content-encoding" end)
        |> case do
          {_, encoding} -> String.downcase(encoding)
          nil -> nil
        end

      case content_encoding do
        "gzip" ->
          :zlib.gunzip(body)

        "deflate" ->
          :zlib.uncompress(body)

        _ ->
          body
      end
    end
  end
end

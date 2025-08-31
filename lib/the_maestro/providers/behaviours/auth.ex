defmodule TheMaestro.Providers.Behaviours.Auth do
  @moduledoc """
  Base behaviour for provider authentication operations.

  Provider modules such as `TheMaestro.Providers.OpenAI.OAuth` or
  `TheMaestro.Providers.OpenAI.APIKey` should implement this behaviour.
  """

  alias TheMaestro.Types

  @typedoc "Session identifier"
  @type session_id :: Types.session_id()

  @callback create_session(keyword()) :: {:ok, session_id} | {:error, term()}
  @callback delete_session(session_id) :: :ok | {:error, term()}
  @callback refresh_tokens(session_id) :: {:ok, map()} | {:error, term()}
end

defmodule TheMaestro.Providers.Behaviours.OAuthProvider do
  @moduledoc """
  Behaviour for OAuth provider implementations.

  Defines the callbacks required for OAuth authentication flow including
  PKCE parameters, auth URL generation, and token exchange.
  """

  @doc """
  Generate OAuth authorization URL with PKCE parameters.

  ## Parameters

  - `session_name` - User-defined session name
  - `opts` - Additional options (redirect_uri, scope, etc.)

  ## Returns

  - `{:ok, {auth_url, pkce_params}}` - Authorization URL and PKCE parameters
  - `{:error, term()}` - Error details
  """
  @callback generate_auth_url(session_name :: String.t(), opts :: keyword()) ::
              {:ok, {auth_url :: String.t(), pkce_params :: map()}} | {:error, term()}

  @doc """
  Exchange authorization code for access/refresh tokens.

  ## Parameters

  - `auth_code` - Authorization code from OAuth callback
  - `pkce_params` - PKCE parameters from generate_auth_url/2
  - `session_name` - User-defined session name

  ## Returns

  - `{:ok, tokens}` - Token response map
  - `{:error, term()}` - Error details
  """
  @callback exchange_code(
              auth_code :: String.t(),
              pkce_params :: map(),
              session_name :: String.t()
            ) ::
              {:ok, tokens :: map()} | {:error, term()}

  @doc """
  Refresh OAuth access token using refresh token.

  ## Parameters

  - `refresh_token` - Current refresh token
  - `session_name` - User-defined session name

  ## Returns

  - `{:ok, tokens}` - New token response map
  - `{:error, term()}` - Error details
  """
  @callback refresh_token(refresh_token :: String.t(), session_name :: String.t()) ::
              {:ok, tokens :: map()} | {:error, term()}

  @doc """
  Extract API credentials from OAuth tokens for API usage.

  ## Parameters

  - `tokens` - OAuth tokens map from exchange_code/3 or refresh_token/2
  - `session_name` - User-defined session name

  ## Returns

  - `{:ok, credentials}` - API credentials map
  - `{:error, term()}` - Error details
  """
  @callback extract_api_credentials(tokens :: map(), session_name :: String.t()) ::
              {:ok, credentials :: map()} | {:error, term()}
end

defmodule TheMaestro.Providers.Behaviours.APIKeyProvider do
  @moduledoc """
  Behaviour for API key provider implementations.

  Defines the callbacks required for API key validation, client creation,
  and connection testing.
  """

  @doc """
  Validate API key format and basic structure.

  ## Parameters

  - `api_key` - The API key to validate

  ## Returns

  - `:ok` - API key format is valid
  - `{:error, term()}` - Validation error details
  """
  @callback validate_api_key(api_key :: String.t()) :: :ok | {:error, term()}

  @doc """
  Create authenticated client for API operations.

  ## Parameters

  - `api_key` - Valid API key
  - `opts` - Additional client options

  ## Returns

  - `{:ok, client}` - Configured client
  - `{:error, term()}` - Client creation error
  """
  @callback create_client(api_key :: String.t(), opts :: keyword()) ::
              {:ok, client :: term()} | {:error, term()}

  @doc """
  Test API connection and key validity.

  ## Parameters

  - `client` - Client created by create_client/2

  ## Returns

  - `:ok` - Connection successful
  - `{:error, term()}` - Connection or authentication error
  """
  @callback test_connection(client :: term()) :: :ok | {:error, term()}
end

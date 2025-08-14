defmodule TheMaestro.Providers.Auth.ProviderAuth do
  @moduledoc """
  Behaviour for provider-specific authentication implementations.

  This behaviour defines a contract for implementing authentication with different 
  LLM providers, supporting multiple authentication methods (OAuth and API keys).
  """

  @typedoc """
  Authentication provider identifier.
  """
  @type provider :: :anthropic | :google | :openai

  @typedoc """
  Authentication method.
  """
  @type auth_method :: :oauth | :api_key

  @typedoc """
  Authentication parameters for initialization.
  """
  @type auth_params :: %{
          optional(:api_key) => String.t(),
          optional(:oauth_code) => String.t(),
          optional(:refresh_token) => String.t(),
          optional(:user_id) => String.t(),
          any() => any()
        }

  @typedoc """
  Validated and processed credentials.
  """
  @type credentials :: %{
          optional(:access_token) => String.t(),
          optional(:refresh_token) => String.t(),
          optional(:expires_at) => DateTime.t(),
          optional(:api_key) => String.t()
        }

  @doc """
  Returns the list of authentication methods available for this provider.

  ## Parameters
    - `provider`: The provider identifier

  ## Returns
    A list of available authentication methods
  """
  @callback get_available_methods(provider()) :: [auth_method()]

  @doc """
  Authenticates with the provider using the specified method and parameters.

  ## Parameters
    - `provider`: The provider identifier
    - `method`: The authentication method to use
    - `params`: Authentication parameters

  ## Returns
    - `{:ok, credentials}`: Successfully authenticated
    - `{:error, reason}`: Authentication failed
  """
  @callback authenticate(provider(), auth_method(), auth_params()) ::
              {:ok, credentials()} | {:error, term()}

  @doc """
  Validates existing credentials for the provider.

  ## Parameters
    - `provider`: The provider identifier
    - `credentials`: The credentials to validate

  ## Returns
    - `{:ok, validated_credentials}`: Credentials are valid (possibly refreshed)
    - `{:error, reason}`: Credentials are invalid or expired
  """
  @callback validate_credentials(provider(), credentials()) ::
              {:ok, credentials()} | {:error, term()}

  @doc """
  Refreshes credentials if possible.

  ## Parameters
    - `provider`: The provider identifier
    - `credentials`: Current credentials containing refresh token

  ## Returns
    - `{:ok, new_credentials}`: Successfully refreshed
    - `{:error, reason}`: Refresh failed
  """
  @callback refresh_credentials(provider(), credentials()) ::
              {:ok, credentials()} | {:error, term()}

  @doc """
  Initiates OAuth authorization flow.

  ## Parameters
    - `provider`: The provider identifier
    - `options`: OAuth flow options (e.g., redirect_uri, state)

  ## Returns
    - `{:ok, auth_url}`: Authorization URL for user to visit
    - `{:error, reason}`: Failed to initiate OAuth flow
  """
  @callback initiate_oauth_flow(provider(), map()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Exchanges OAuth authorization code for access tokens.

  ## Parameters
    - `provider`: The provider identifier
    - `code`: Authorization code from OAuth callback
    - `options`: Exchange options (e.g., redirect_uri, state)

  ## Returns
    - `{:ok, credentials}`: Successfully exchanged for tokens
    - `{:error, reason}`: Exchange failed
  """
  @callback exchange_oauth_code(provider(), String.t(), map()) ::
              {:ok, credentials()} | {:error, term()}
end

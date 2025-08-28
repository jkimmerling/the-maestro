defmodule TheMaestro.Auth do
  @moduledoc """
  OAuth 2.0 authentication module for Anthropic API integration.

  Provides OAuth URL generation and authorization code exchange functionality
  with exact llxprt configuration compliance for Anthropic API authentication.

  ## Configuration Values

  Uses exact Anthropic OAuth configuration from llxprt reference implementation:
  - client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  - authorization_endpoint: "https://claude.ai/oauth/authorize"
  - token_endpoint: "https://console.anthropic.com/v1/oauth/token"
  - redirect_uri: "https://console.anthropic.com/oauth/code/callback"
  - scopes: ["org:create_api_key", "user:profile", "user:inference"]

  ## Example Usage

      # Generate OAuth URL
      {:ok, {auth_url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()

      # Exchange authorization code for tokens
      {:ok, oauth_token} = TheMaestro.Auth.exchange_code_for_tokens(
        "auth_code_from_user",
        pkce_params
      )
  """

  alias TheMaestro.Providers.Client
  require Logger

  # Embedded struct definitions per Phoenix conventions for simple structs
  defmodule AnthropicOAuthConfig do
    @moduledoc """
    Configuration structure for Anthropic OAuth 2.0 authentication.
    Matches llxprt configuration exactly.
    """

    @type t :: %__MODULE__{
            client_id: String.t(),
            authorization_endpoint: String.t(),
            token_endpoint: String.t(),
            redirect_uri: String.t(),
            scopes: [String.t()]
          }

    defstruct [
      client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
      authorization_endpoint: "https://claude.ai/oauth/authorize",
      token_endpoint: "https://console.anthropic.com/v1/oauth/token",
      redirect_uri: "https://console.anthropic.com/oauth/code/callback",
      scopes: ["org:create_api_key", "user:profile", "user:inference"]
    ]
  end

  defmodule OAuthToken do
    @moduledoc """
    OAuth token structure matching llxprt format.
    """

    @type t :: %__MODULE__{
            access_token: String.t(),
            refresh_token: String.t() | nil,
            expiry: integer(),
            scope: String.t() | nil,
            token_type: String.t()
          }

    defstruct [
      :access_token,
      :refresh_token,
      :expiry,
      :scope,
      token_type: "Bearer"
    ]
  end

  defmodule DeviceCodeResponse do
    @moduledoc """
    Simulated device code response for OAuth flow.
    """

    @type t :: %__MODULE__{
            device_code: String.t(),
            user_code: String.t(),
            verification_uri: String.t(),
            verification_uri_complete: String.t(),
            expires_in: integer(),
            interval: integer()
          }

    defstruct [
      :device_code,
      :user_code,
      :verification_uri,
      :verification_uri_complete,
      :expires_in,
      :interval
    ]
  end

  defmodule PKCEParams do
    @moduledoc """
    PKCE parameters for OAuth 2.0 security.
    """

    @type t :: %__MODULE__{
            code_verifier: String.t(),
            code_challenge: String.t(),
            code_challenge_method: String.t()
          }

    defstruct [
      :code_verifier,
      :code_challenge,
      code_challenge_method: "S256"
    ]
  end

  # Public API functions

  @doc """
  Generate OAuth authorization URL with PKCE parameters.

  Creates an OAuth 2.0 authorization URL with PKCE (Proof Key for Code Exchange)
  security parameters using exact llxprt parameter order.

  ## Returns

    * `{:ok, {String.t(), PKCEParams.t()}}` - Success with URL and PKCE params
    * `{:error, term()}` - Error during URL generation

  ## Examples

      iex> {:ok, {auth_url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()
      iex> is_binary(auth_url)
      true
      iex> is_struct(pkce_params, TheMaestro.Auth.PKCEParams)
      true
  """
  @spec generate_oauth_url() :: {:ok, {String.t(), PKCEParams.t()}} | {:error, term()}
  def generate_oauth_url do
    # Generate PKCE parameters
    pkce_params = generate_pkce_params()
    config = %AnthropicOAuthConfig{}

    # Build URL parameters in exact llxprt order
    params = %{
      "code" => "true",
      "client_id" => config.client_id,
      "response_type" => "code",
      "redirect_uri" => config.redirect_uri,
      "scope" => Enum.join(config.scopes, " "),
      "code_challenge" => pkce_params.code_challenge,
      "code_challenge_method" => pkce_params.code_challenge_method,
      "state" => pkce_params.code_verifier
    }

    auth_url = "#{config.authorization_endpoint}?#{URI.encode_query(params)}"
    Logger.info("Generated OAuth URL with PKCE parameters")

    {:ok, {auth_url, pkce_params}}
  rescue
    error ->
      Logger.error("Failed to generate OAuth URL: #{inspect(error)}")
      {:error, :url_generation_failed}
  end

  @doc """
  Exchange authorization code for OAuth tokens.

  Exchanges the authorization code received from user for access and refresh tokens
  using JSON request format (not form-encoded) as required by llxprt.

  ## Parameters

    * `auth_code_input` - Authorization code from user (format: "code#state" or "code")
    * `pkce_params` - PKCE parameters from URL generation

  ## Returns

    * `{:ok, OAuthToken.t()}` - Success with OAuth tokens
    * `{:error, term()}` - Error during token exchange

  ## Examples

      iex> pkce_params = %TheMaestro.Auth.PKCEParams{
      ...>   code_verifier: "test_verifier",
      ...>   code_challenge: "test_challenge",
      ...>   code_challenge_method: "S256"
      ...> }
      iex> TheMaestro.Auth.exchange_code_for_tokens("auth_code", pkce_params)
      # Returns {:ok, %OAuthToken{}} or {:error, reason}
  """
  @spec exchange_code_for_tokens(String.t(), PKCEParams.t()) ::
          {:ok, OAuthToken.t()} | {:error, term()}
  def exchange_code_for_tokens(auth_code_input, pkce_params) do
    # Parse code and state from user input (format: code#state or just code)
    {auth_code, state} = parse_auth_code_input(auth_code_input, pkce_params.code_verifier)

    config = %AnthropicOAuthConfig{}

    # Build request body as JSON (NOT form-encoded)
    request_body = %{
      "grant_type" => "authorization_code",
      "code" => auth_code,
      "state" => state,
      "client_id" => config.client_id,
      "redirect_uri" => config.redirect_uri,
      "code_verifier" => pkce_params.code_verifier
    }

    # Send JSON request using existing Tesla + Finch infrastructure
    client = Client.build_client(:anthropic)
    headers = [{"content-type", "application/json"}]

    case Tesla.post(client, config.token_endpoint, request_body, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        map_token_response(response_body)

      {:ok, %Tesla.Env{status: status, body: response_body}} ->
        Logger.error("Token exchange failed with status #{status}: #{response_body}")
        {:error, {:token_exchange_failed, status, response_body}}

      {:error, reason} ->
        Logger.error("Token request failed: #{inspect(reason)}")
        {:error, {:token_request_failed, reason}}
    end
  rescue
    error ->
      Logger.error("Token exchange error: #{inspect(error)}")
      {:error, :token_exchange_error}
  end

  @doc """
  Generate PKCE code verifier and challenge using S256 method.

  ## Returns

    * `PKCEParams.t()` - Generated PKCE parameters

  ## Examples

      iex> pkce = TheMaestro.Auth.generate_pkce_params()
      iex> pkce.code_challenge_method
      "S256"
  """
  @spec generate_pkce_params() :: PKCEParams.t()
  def generate_pkce_params do
    # Generate 32-byte random code_verifier using cryptographically secure random
    code_verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    # Generate code_challenge using SHA256 hash of verifier, Base64URL encoded
    code_challenge =
      :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)

    %PKCEParams{
      code_verifier: code_verifier,
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }
  end

  # Private helper functions

  # Parse authorization code input handling both "code#state" and "code" formats
  defp parse_auth_code_input(auth_code_input, default_state) do
    case String.split(auth_code_input, "#", parts: 2) do
      [auth_code, state] -> {auth_code, state}
      [auth_code] -> {auth_code, default_state}
    end
  end

  # Map Anthropic's token response to standardized OAuthToken struct
  defp map_token_response(response_body) do
    case response_body do
      %{
        "access_token" => access_token,
        "expires_in" => expires_in
      } = data ->
        expiry = System.system_time(:second) + expires_in

        oauth_token = %OAuthToken{
          access_token: access_token,
          refresh_token: Map.get(data, "refresh_token"),
          expiry: expiry,
          scope: Map.get(data, "scope"),
          token_type: Map.get(data, "token_type", "Bearer")
        }

        Logger.info("Successfully mapped token response")
        {:ok, oauth_token}

      _ ->
        Logger.error("Invalid token response format: #{inspect(response_body)}")
        {:error, :invalid_token_response}
    end
  end
end

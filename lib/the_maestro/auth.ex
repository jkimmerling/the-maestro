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

  Configuration can be customized via environment variables in `config/runtime.exs`:
  - ANTHROPIC_CLIENT_ID (defaults to hardcoded public client ID)

  ## OAuth Setup Process

  ### Step 1: Generate OAuth URL
  Generate a secure OAuth authorization URL with PKCE parameters:

      {:ok, {auth_url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()

  The `auth_url` will contain all necessary parameters and should be presented to the user
  for authorization. The `pkce_params` must be retained for the token exchange step.

  ### Step 2: User Authorization
  Direct the user to visit the `auth_url` in their browser. They will:
  1. See Anthropic's authorization page
  2. Review the requested permissions (create API keys, profile access, inference)
  3. Click "Authorize" to grant access
  4. Be redirected with an authorization code in the URL fragment

  ### Step 3: Extract Authorization Code
  The user should copy the authorization code from the redirect URL. The code appears
  after the callback URL in format: `code#state` or just `code`.

  ### Step 4: Exchange Code for Tokens
  Exchange the authorization code for access and refresh tokens:

      {:ok, oauth_token} = TheMaestro.Auth.exchange_code_for_tokens(
        "authorization_code_from_user",
        pkce_params
      )

  The resulting `oauth_token` contains:
  - `access_token`: For API authentication
  - `refresh_token`: For token renewal (may be nil)
  - `expiry`: Unix timestamp when token expires
  - `scope`: Granted permissions
  - `token_type`: Always "Bearer"

  ## Complete Workflow Example

      # Step 1: Generate OAuth URL
      {:ok, {auth_url, pkce_params}} = TheMaestro.Auth.generate_oauth_url()
      
      # Present auth_url to user for authorization
      IO.puts("Visit: " <> auth_url)
      IO.puts("After authorization, copy the code from the redirect URL")
      
      # Step 2: Get code from user input
      auth_code = IO.gets("Enter authorization code: ") |> String.trim()
      
      # Step 3: Exchange for tokens
      case TheMaestro.Auth.exchange_code_for_tokens(auth_code, pkce_params) do
        {:ok, oauth_token} ->
          IO.puts("Success! Access token: " <> String.slice(oauth_token.access_token, 0, 20) <> "...")
          # Store oauth_token.access_token for API calls
          
        {:error, reason} ->
          IO.puts("OAuth failed: " <> inspect(reason))
      end

  ## Security Features

  - **PKCE (Proof Key for Code Exchange)**: Uses S256 method for enhanced security
  - **State Parameter**: Prevents CSRF attacks using code verifier as state
  - **Secure Random Generation**: Cryptographically secure random values
  - **JSON Request Format**: Follows llxprt standard (not form-encoded)

  ## Error Handling

  Functions return `{:ok, result}` or `{:error, reason}` tuples:
  - `:url_generation_failed` - PKCE or URL construction error
  - `:token_exchange_failed` - HTTP error with status and body
  - `:token_request_failed` - Network or connection error  
  - `:invalid_token_response` - Malformed response from Anthropic
  - `:token_exchange_error` - Unexpected error during processing

  ## Integration Notes

  This module uses HTTPoison for OAuth token requests (separate from Tesla API client)
  because OAuth and API endpoints have different authentication requirements.
  OAuth endpoints require unauthenticated JSON requests, while API endpoints
  require authenticated requests with different client configurations.
  """

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

    defstruct client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
              authorization_endpoint: "https://claude.ai/oauth/authorize",
              token_endpoint: "https://console.anthropic.com/v1/oauth/token",
              redirect_uri: "https://console.anthropic.com/oauth/code/callback",
              scopes: ["org:create_api_key", "user:profile", "user:inference"]
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

      # After user authorization, exchange code for tokens
      {:ok, {auth_url, pkce_params}} = generate_oauth_url()
      # ... user visits auth_url and gets authorization code ...
      
      # Exchange code for tokens (handles both formats)
      {:ok, oauth_token} = exchange_code_for_tokens("auth_code_123", pkce_params)
      {:ok, oauth_token} = exchange_code_for_tokens("auth_code_123#state_456", pkce_params)
      
      # Access token details
      oauth_token.access_token  # "sk-ant-oat01-..."
      oauth_token.expiry        # Unix timestamp
      oauth_token.token_type    # "Bearer"

  ## Error Cases

    * `{:error, :token_exchange_error}` - Unexpected error during processing
    * `{:error, {:token_exchange_failed, status, body}}` - HTTP error from Anthropic
    * `{:error, {:token_request_failed, reason}}` - Network or connection error
    * `{:error, :invalid_token_response}` - Malformed response format

  ## Note
  This function makes real HTTP requests to Anthropic's OAuth endpoints.
  The request is sent as JSON (not form-encoded) following llxprt specifications.
  Uses HTTPoison client separate from Tesla API client for endpoint compatibility.
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

    # Send JSON request to OAuth token endpoint (like llxprt fetch)
    # Use direct HTTP request since OAuth endpoint is different from API endpoint
    headers = [{"content-type", "application/json"}]
    json_body = Jason.encode!(request_body)

    case HTTPoison.post(config.token_endpoint, json_body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        map_token_response(Jason.decode!(response_body))

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
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

  Creates cryptographically secure PKCE (Proof Key for Code Exchange) parameters
  for OAuth 2.0 authorization. Uses 32-byte random code verifier and SHA256
  hash for code challenge following RFC 7636 specification.

  ## Returns

    * `PKCEParams.t()` - Generated PKCE parameters with verifier, challenge, and method

  ## Examples

      iex> pkce = TheMaestro.Auth.generate_pkce_params()
      iex> pkce.code_challenge_method
      "S256"
      iex> String.length(pkce.code_verifier) >= 43
      true
      iex> String.length(pkce.code_challenge) >= 43
      true

  ## Security Features

  - Uses `:crypto.strong_rand_bytes/1` for cryptographically secure randomness
  - 32-byte verifier provides sufficient entropy for security
  - Base64URL encoding without padding follows RFC 7636
  - SHA256 hash provides strong one-way function for challenge
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

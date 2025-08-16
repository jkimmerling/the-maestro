defmodule TheMaestro.Providers.Auth.AnthropicDeviceFlow do
  @moduledoc """
  Anthropic OAuth 2.0 Device Flow Implementation

  Implements OAuth 2.0 device authorization grant flow for Anthropic Claude API.
  Based on the OAuth 2.0 Device Authorization Grant specification (RFC 8628).
  
  This implementation mimics Claude Code's device flow authentication pattern
  for compatibility with Anthropic's OAuth infrastructure.
  """

  require Logger

  # Anthropic OAuth configuration matching llxprt-code reference
  @default_config %{
    client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e", # Anthropic's public OAuth client ID
    authorization_endpoint: "https://claude.ai/oauth/authorize", # Use claude.ai like llxprt-code "max" mode
    token_endpoint: "https://console.anthropic.com/v1/oauth/token",
    scopes: ["org:create_api_key", "user:profile", "user:inference"]
  }

  defmodule DeviceCodeResponse do
    @moduledoc """
    Device code response structure for simulated device flow
    """
    defstruct [
      :device_code,
      :user_code,
      :verification_uri,
      :verification_uri_complete,
      :expires_in,
      :interval
    ]
  end

  defmodule TokenResponse do
    @moduledoc """
    OAuth token response structure
    """
    defstruct [
      :access_token,
      :refresh_token,
      :expiry,
      :scope,
      :token_type
    ]
  end


  defmodule State do
    @moduledoc """
    Internal state for device flow authentication
    """
    defstruct [
      :config,
      :code_verifier,
      :code_challenge,
      :state
    ]
  end

  @doc """
  Initialize a new device flow with optional configuration override
  """
  def new(config_override \\ %{}) do
    config = Map.merge(@default_config, config_override)
    %State{config: config}
  end

  @doc """
  Generate PKCE code verifier and challenge using S256 method
  """
  def generate_pkce(flow_state) do
    # Generate a random code verifier (43-128 characters)
    verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    
    # Generate code challenge using S256 (SHA256 hash)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    
    %{flow_state | code_verifier: verifier, code_challenge: challenge}
  end

  @doc """
  Initiate the OAuth flow by constructing the authorization URL.
  Since Anthropic doesn't have a true device flow, we simulate it with authorization code flow.
  """
  def initiate_device_flow(flow_state \\ new()) do
    # Generate PKCE parameters
    flow_state = generate_pkce(flow_state)
    
    # Use verifier as state like llxprt-code does
    flow_state = %{flow_state | state: flow_state.code_verifier}
    
    # Build authorization URL with PKCE parameters
    params = %{
      code: "true",
      client_id: flow_state.config.client_id,
      response_type: "code",
      redirect_uri: "https://console.anthropic.com/oauth/code/callback",
      scope: Enum.join(flow_state.config.scopes, " "),
      code_challenge: flow_state.code_challenge,
      code_challenge_method: "S256",
      state: flow_state.state
    }
    
    auth_url = "#{flow_state.config.authorization_endpoint}?#{URI.encode_query(params)}"
    
    # Return a simulated device code response with the authorization URL
    device_response = %DeviceCodeResponse{
      device_code: flow_state.code_verifier, # Use verifier as a tracking ID
      user_code: "ANTHROPIC", # Display code for user
      verification_uri: "https://console.anthropic.com/oauth/authorize",
      verification_uri_complete: auth_url,
      expires_in: 1800, # 30 minutes
      interval: 5 # 5 seconds polling interval
    }
    
    Logger.info("Initiated Anthropic device flow with verifier length: #{String.length(flow_state.code_verifier)}")
    
    {:ok, device_response, flow_state}
  end

  @doc """
  Exchange authorization code for access token (PKCE flow)
  """
  def exchange_code_for_token(auth_code_with_state, flow_state) do
    if !flow_state.code_verifier do
      {:error, "No PKCE code verifier found - OAuth flow not initialized"}
    else
      # llxprt-code splits the code and state - format: code#state
      splits = String.split(auth_code_with_state, "#")
      auth_code = Enum.at(splits, 0)
      state_from_response = Enum.at(splits, 1) || flow_state.state
      
      Logger.info("Exchanging authorization code: #{String.slice(auth_code, 0, 10)}... (length: #{String.length(auth_code)})")
      
      # llxprt-code sends JSON in exact field order - must match exactly
      # CRITICAL: state field is required and must be included!
      request_body = %{
        grant_type: "authorization_code",
        code: auth_code,
        state: state_from_response,
        client_id: flow_state.config.client_id,
        redirect_uri: "https://console.anthropic.com/oauth/code/callback",
        code_verifier: flow_state.code_verifier
      }
      
      # Headers exactly as llxprt-code - only Content-Type, no Accept header
      headers = [
        {"Content-Type", "application/json"}
      ]
      
      body = Jason.encode!(request_body)
      
      Logger.debug("Token request body: #{body}")
      
      case HTTPoison.post(flow_state.config.token_endpoint, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              Logger.info("Token response: access_token present: #{!!data["access_token"]}, refresh_token present: #{!!data["refresh_token"]}, expires_in: #{data["expires_in"]}")
              {:ok, map_token_response(data)}
            
            {:error, reason} ->
              {:error, {:token_decode_failed, reason}}
          end
        
        {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
          Logger.error("Token exchange failed with status #{status}: #{response_body}")
          {:error, {:token_exchange_failed, status, response_body}}
        
        {:error, reason} ->
          Logger.error("Token request failed: #{inspect(reason)}")
          {:error, {:token_request_failed, reason}}
      end
    end
  end

  @doc """
  Poll for the access token after user authorization.
  This implements the actual device flow polling mechanism.
  """
  def poll_for_token(device_code, flow_state, timeout_ms \\ 1800000) do # 30 minutes
    start_time = System.monotonic_time(:millisecond)
    interval = 5000 # 5 seconds
    
    poll_loop(device_code, flow_state, start_time, timeout_ms, interval)
  end
  
  defp poll_loop(device_code, flow_state, start_time, timeout_ms, interval) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - start_time >= timeout_ms do
      {:error, "Authorization timeout - user did not complete authentication"}
    else
      request_body = %{
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: device_code,
        client_id: flow_state.config.client_id
      }
      
      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]
      
      body = URI.encode_query(request_body)
      
      case HTTPoison.post(flow_state.config.token_endpoint, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, data} -> {:ok, map_token_response(data)}
            {:error, reason} -> {:error, {:token_decode_failed, reason}}
          end
        
        {:ok, %HTTPoison.Response{body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"error" => "authorization_pending"}} ->
              # Continue polling
              :timer.sleep(interval)
              poll_loop(device_code, flow_state, start_time, timeout_ms, interval)
            
            {:ok, %{"error" => "slow_down"}} ->
              # Slow down polling
              :timer.sleep(interval * 2)
              poll_loop(device_code, flow_state, start_time, timeout_ms, interval * 2)
            
            {:ok, %{"error" => error, "error_description" => description}} ->
              {:error, "Token polling failed: #{description || error}"}
            
            {:ok, %{"error" => error}} ->
              {:error, "Token polling failed: #{error}"}
            
            {:error, _} ->
              # Network error - continue polling
              :timer.sleep(interval)
              poll_loop(device_code, flow_state, start_time, timeout_ms, interval)
          end
        
        {:error, _} ->
          # Network error - continue polling
          :timer.sleep(interval)
          poll_loop(device_code, flow_state, start_time, timeout_ms, interval)
      end
    end
  end

  @doc """
  Refresh an expired access token using a refresh token.
  """
  def refresh_token(refresh_token, flow_state) do
    request_body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: flow_state.config.client_id
    }
    
    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
    
    body = URI.encode_query(request_body)
    
    case HTTPoison.post(flow_state.config.token_endpoint, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, data} -> {:ok, map_token_response(data)}
          {:error, reason} -> {:error, {:refresh_decode_failed, reason}}
        end
      
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:refresh_failed, status, response_body}}
      
      {:error, reason} ->
        {:error, {:refresh_request_failed, reason}}
    end
  end

  @doc """
  Map Anthropic's token response to our standard token format.
  """
  defp map_token_response(data) do
    expiry = case data["expires_in"] do
      nil -> nil
      expires_in when is_integer(expires_in) ->
        System.system_time(:second) + expires_in
      _ -> nil
    end
    
    %TokenResponse{
      access_token: data["access_token"],
      refresh_token: data["refresh_token"],
      expiry: expiry,
      scope: data["scope"],
      token_type: "Bearer"
    }
  end

  @doc """
  Launch browser securely for OAuth authentication
  """
  def launch_browser(url) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [url])
      {:unix, _} -> System.cmd("xdg-open", [url])
      {:win32, _} -> System.cmd("cmd", ["/c", "start", url])
      _ -> {:error, :unsupported_os}
    end
  end

  @doc """
  Check if we should launch browser (not in CI/headless environments)
  """
  def should_launch_browser?() do
    # Don't launch in CI environments
    !System.get_env("CI") && !System.get_env("GITHUB_ACTIONS") && 
    System.get_env("DISPLAY") != nil
  end
end
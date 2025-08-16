defmodule TheMaestro.Providers.Auth.AnthropicAuth do
  @moduledoc """
  Anthropic (Claude) authentication provider implementation.

  This module implements OAuth device flow and API key authentication for Anthropic's Claude API.
  It follows Anthropic's authentication patterns and mimics Claude Code's device flow authentication.
  
  Completely revamped to match llxprt-code reference implementation for Claude Code compatibility.
  """

  @behaviour TheMaestro.Providers.Auth.ProviderAuth

  alias TheMaestro.Providers.Auth.ProviderAuth
  alias TheMaestro.Providers.Auth.AnthropicDeviceFlow

  require Logger

  # Configuration matching llxprt-code reference
  @api_base_url "https://api.anthropic.com/v1"

  @impl ProviderAuth
  def get_available_methods(:anthropic) do
    # OAuth (using device flow under the hood) and API key are available
    [:oauth, :api_key]
  end

  @impl ProviderAuth
  def authenticate(:anthropic, :api_key, %{api_key: api_key} = _params) do
    case validate_api_key(api_key) do
      :ok ->
        credentials = %{
          "api_key" => api_key,
          "token_type" => "api_key"
        }

        Logger.info("Successfully authenticated with Anthropic using API key")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("Anthropic API key validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def authenticate(:anthropic, :oauth, params) do
    # Initialize device flow (OAuth implementation)
    flow_state = AnthropicDeviceFlow.new()
    
    {:ok, device_response, updated_flow_state} = AnthropicDeviceFlow.initiate_device_flow(flow_state)
    
    # Display authentication instructions
    display_device_flow_instructions(device_response)
    
    # Check if we have an authorization code provided directly
    case Map.get(params, :auth_code) do
      nil ->
        # Wait for user to complete authentication manually
        Logger.info("Waiting for user to complete authentication at: #{device_response.verification_uri_complete}")
        {:error, {:manual_auth_required, device_response.verification_uri_complete}}
      
      auth_code ->
        # Exchange provided authorization code for tokens
        complete_device_flow_with_state(auth_code, updated_flow_state)
    end
  end

  def authenticate(:anthropic, method, _params) do
    {:error, {:unsupported_method, method}}
  end

  @impl ProviderAuth
  def validate_credentials(:anthropic, %{"api_key" => api_key}) do
    case validate_api_key(api_key) do
      :ok -> {:ok, %{"api_key" => api_key, "token_type" => "api_key"}}
      error -> error
    end
  end

  def validate_credentials(:anthropic, %{"access_token" => token} = credentials) do
    case validate_access_token(token) do
      :ok ->
        {:ok, credentials}

      {:error, :expired} ->
        # Try to refresh if we have a refresh token
        case credentials["refresh_token"] do
          nil -> {:error, :expired}
          _refresh_token -> refresh_credentials(:anthropic, credentials)
        end

      error ->
        error
    end
  end

  def validate_credentials(:anthropic, credentials) do
    Logger.error("Invalid credential format for Anthropic: #{inspect(credentials)}")
    {:error, :invalid_credentials}
  end

  @impl ProviderAuth
  def refresh_credentials(:anthropic, %{"refresh_token" => refresh_token} = credentials) do
    flow_state = AnthropicDeviceFlow.new()
    
    case AnthropicDeviceFlow.refresh_token(refresh_token, flow_state) do
      {:ok, token_struct} ->
        refreshed_credentials = %{
          "access_token" => token_struct.access_token,
          "refresh_token" => token_struct.refresh_token || credentials["refresh_token"],
          "expires_at" => token_struct.expiry,
          "token_type" => token_struct.token_type,
          "scope" => token_struct.scope
        }

        Logger.info("Successfully refreshed Anthropic OAuth credentials")
        {:ok, refreshed_credentials}

      {:error, reason} ->
        Logger.error("Failed to refresh Anthropic credentials: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_credentials(:anthropic, %{"api_key" => _api_key} = credentials) do
    # API keys don't need refresh, just validate
    validate_credentials(:anthropic, credentials)
  end

  def refresh_credentials(:anthropic, _credentials) do
    {:error, {:cannot_refresh, :missing_refresh_token}}
  end

  @impl ProviderAuth
  def initiate_oauth_flow(:anthropic, options \\ %{}) do
    # Use device flow instead of traditional OAuth
    flow_state = AnthropicDeviceFlow.new()
    
    {:ok, device_response, updated_flow_state} = AnthropicDeviceFlow.initiate_device_flow(flow_state)
    
    # Check if we need to return flow state data for web UI
    case Map.get(options, :return_flow_state, false) do
      true ->
        # Return both URL and flow state for web UI
        {:ok, %{
          auth_url: device_response.verification_uri_complete,
          code_verifier: updated_flow_state.code_verifier,
          state: updated_flow_state.state
        }}
      false ->
        # Return just URL for backward compatibility
        {:ok, device_response.verification_uri_complete}
    end
  end

  @impl ProviderAuth
  def exchange_oauth_code(:anthropic, code, options \\ %{}) do
    # Use device flow for code exchange
    flow_state = AnthropicDeviceFlow.new()
    
    # Set the code verifier from options if provided
    flow_state = case Map.get(options, :code_verifier) do
      nil ->
        # Try to get from process dictionary (backward compatibility)
        case Process.get(:oauth_code_verifier) do
          nil -> flow_state
          verifier -> %{flow_state | code_verifier: verifier, state: verifier}
        end
      verifier ->
        # Set both code_verifier and state to the same value like llxprt-code does
        %{flow_state | code_verifier: verifier, state: verifier}
    end
    
    case AnthropicDeviceFlow.exchange_code_for_token(code, flow_state) do
      {:ok, token_struct} ->
        credentials = %{
          "access_token" => token_struct.access_token,
          "refresh_token" => token_struct.refresh_token,
          "expires_at" => token_struct.expiry,
          "token_type" => token_struct.token_type,
          "scope" => token_struct.scope
        }
        {:ok, credentials}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Complete device flow authentication with authorization code.
  This is a convenience function for completing the device flow after receiving the auth code.
  """
  def complete_device_flow_auth(:anthropic, auth_code) do
    flow_state = AnthropicDeviceFlow.new()
    complete_device_flow_with_state(auth_code, flow_state)
  end

  # Device Flow Helper Functions

  defp display_device_flow_instructions(device_response) do
    IO.puts("\n🔐 Anthropic Claude OAuth Authentication")
    IO.puts("─" |> String.duplicate(40))
    
    # Try to launch browser if appropriate
    if AnthropicDeviceFlow.should_launch_browser?() do
      IO.puts("🌐 Opening browser for authentication...")
      IO.puts("If the browser does not open, please visit:")
      IO.puts("#{device_response.verification_uri_complete}")
      
      case AnthropicDeviceFlow.launch_browser(device_response.verification_uri_complete) do
        {_, 0} -> :ok
        _ -> IO.puts("⚠️  Failed to open browser automatically.")
      end
    else
      IO.puts("🌐 Visit this URL to authorize:")
      IO.puts("#{device_response.verification_uri_complete}")
    end
    
    IO.puts("─" |> String.duplicate(40))
    IO.puts("📋 After authorization, you'll receive a code to enter.")
    IO.puts("⏰ This authorization will expire in #{device_response.expires_in} seconds.")
  end

  defp complete_device_flow_with_state(auth_code, flow_state) do
    case AnthropicDeviceFlow.exchange_code_for_token(auth_code, flow_state) do
      {:ok, token_struct} ->
        credentials = %{
          "access_token" => token_struct.access_token,
          "refresh_token" => token_struct.refresh_token,
          "expires_at" => token_struct.expiry,
          "token_type" => token_struct.token_type,
          "scope" => token_struct.scope
        }

        Logger.info("Successfully authenticated with Anthropic using device flow")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("Anthropic device flow authentication failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private Functions

  defp validate_api_key(api_key) when is_binary(api_key) do
    # Anthropic API keys typically start with "sk-ant-"
    if String.starts_with?(api_key, "sk-ant-") and String.length(api_key) > 20 do
      # Test the API key by making a simple request
      test_api_key(api_key)
    else
      {:error, :invalid_api_key_format}
    end
  end

  defp validate_api_key(_), do: {:error, :invalid_api_key_format}

  defp test_api_key(api_key) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"X-API-Key", api_key}
    ]

    # Make a minimal request to validate the key
    case HTTPoison.get("#{@api_base_url}/messages", headers) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :unauthorized}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        {:error, :forbidden}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("Failed to test Anthropic API key: #{inspect(reason)}")
        {:error, :api_request_failed}
    end
  end

  defp validate_access_token(token) do
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.get("#{@api_base_url}/user", headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :expired}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:token_validation_failed, status}}

      {:error, reason} ->
        Logger.error("Failed to validate Anthropic access token: #{inspect(reason)}")
        {:error, :token_request_failed}
    end
  end

  # Removed old OAuth functions - now using device flow implementation
end

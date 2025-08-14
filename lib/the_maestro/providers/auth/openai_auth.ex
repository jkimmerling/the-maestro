defmodule TheMaestro.Providers.Auth.OpenAIAuth do
  @moduledoc """
  OpenAI (ChatGPT) authentication provider implementation.

  This module implements OAuth and API key authentication for OpenAI's ChatGPT API.
  It follows OpenAI's authentication patterns and security best practices.
  """

  @behaviour TheMaestro.Providers.Auth.ProviderAuth

  alias TheMaestro.Providers.Auth.ProviderAuth

  require Logger

  # OpenAI OAuth scopes and URLs
  @oauth_scopes ["read", "write"]
  @oauth_base_url "https://api.openai.com/oauth"
  @api_base_url "https://api.openai.com/v1"

  @impl ProviderAuth
  def get_available_methods(:openai) do
    methods = [:api_key]

    # Add OAuth if configured
    if get_oauth_client_id() && get_oauth_client_secret() do
      [:oauth | methods]
    else
      methods
    end
  end

  @impl ProviderAuth
  def authenticate(:openai, :api_key, %{api_key: api_key} = _params) do
    case validate_api_key(api_key) do
      :ok ->
        credentials = %{
          api_key: api_key,
          token_type: "api_key"
        }

        Logger.info("Successfully authenticated with OpenAI using API key")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("OpenAI API key validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def authenticate(:openai, :oauth, %{oauth_code: code, redirect_uri: redirect_uri} = params) do
    state = Map.get(params, :state)

    case exchange_code_for_tokens(code, redirect_uri, state) do
      {:ok, tokens} ->
        credentials = %{
          access_token: tokens[:access_token],
          refresh_token: tokens[:refresh_token],
          expires_at: calculate_expiry(tokens[:expires_in]),
          token_type: "Bearer",
          scope: tokens[:scope]
        }

        Logger.info("Successfully authenticated with OpenAI using OAuth")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("OpenAI OAuth authentication failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def authenticate(:openai, method, _params) do
    {:error, {:unsupported_method, method}}
  end

  @impl ProviderAuth
  def validate_credentials(:openai, %{api_key: api_key}) do
    case validate_api_key(api_key) do
      :ok -> {:ok, %{api_key: api_key, token_type: "api_key"}}
      error -> error
    end
  end

  def validate_credentials(:openai, %{access_token: token} = credentials) do
    case validate_access_token(token) do
      :ok ->
        {:ok, credentials}

      {:error, :expired} ->
        # Try to refresh if we have a refresh token
        case credentials[:refresh_token] do
          nil -> {:error, :expired}
          _refresh_token -> refresh_credentials(:openai, credentials)
        end

      error ->
        error
    end
  end

  def validate_credentials(:openai, credentials) do
    Logger.error("Invalid credential format for OpenAI: #{inspect(credentials)}")
    {:error, :invalid_credentials}
  end

  @impl ProviderAuth
  def refresh_credentials(:openai, %{refresh_token: refresh_token} = credentials) do
    case refresh_access_token(refresh_token) do
      {:ok, new_tokens} ->
        refreshed_credentials = %{
          credentials
          | access_token: new_tokens[:access_token],
            expires_at: calculate_expiry(new_tokens[:expires_in])
        }

        # Keep the refresh token if a new one wasn't provided
        refreshed_credentials =
          if new_tokens[:refresh_token] do
            %{refreshed_credentials | refresh_token: new_tokens[:refresh_token]}
          else
            refreshed_credentials
          end

        Logger.info("Successfully refreshed OpenAI OAuth credentials")
        {:ok, refreshed_credentials}

      {:error, reason} ->
        Logger.error("Failed to refresh OpenAI credentials: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_credentials(:openai, %{api_key: _api_key} = credentials) do
    # API keys don't need refresh, just validate
    validate_credentials(:openai, credentials)
  end

  def refresh_credentials(:openai, _credentials) do
    {:error, {:cannot_refresh, :missing_refresh_token}}
  end

  @impl ProviderAuth
  def initiate_oauth_flow(:openai, options \\ %{}) do
    if get_oauth_client_id() && get_oauth_client_secret() do
      state = generate_state()
      redirect_uri = Map.get(options, :redirect_uri, get_default_redirect_uri())

      auth_params = %{
        client_id: get_oauth_client_id(),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: Enum.join(@oauth_scopes, " "),
        state: state
      }

      auth_url = "#{@oauth_base_url}/authorize?" <> URI.encode_query(auth_params)

      Logger.info("Initiated OpenAI OAuth flow with state: #{state}")
      {:ok, auth_url}
    else
      {:error, :oauth_not_configured}
    end
  end

  @impl ProviderAuth
  def exchange_oauth_code(:openai, code, options \\ %{}) do
    redirect_uri = Map.get(options, :redirect_uri, get_default_redirect_uri())
    exchange_code_for_tokens(code, redirect_uri, Map.get(options, :state))
  end

  # Private Functions

  defp validate_api_key(api_key) when is_binary(api_key) do
    # OpenAI API keys start with "sk-" for secret keys
    if String.starts_with?(api_key, "sk-") and String.length(api_key) > 20 do
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
      {"Content-Type", "application/json"}
    ]

    # Make a minimal request to validate the key (list models endpoint)
    case HTTPoison.get("#{@api_base_url}/models", headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :unauthorized}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        {:error, :forbidden}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("Failed to test OpenAI API key: #{inspect(reason)}")
        {:error, :api_request_failed}
    end
  end

  defp validate_access_token(token) do
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.get("#{@api_base_url}/models", headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :expired}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:token_validation_failed, status}}

      {:error, reason} ->
        Logger.error("Failed to validate OpenAI access token: #{inspect(reason)}")
        {:error, :token_request_failed}
    end
  end

  defp exchange_code_for_tokens(code, redirect_uri, _state) do
    token_params = %{
      client_id: get_oauth_client_id(),
      client_secret: get_oauth_client_secret(),
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(token_params)

    case HTTPoison.post("#{@oauth_base_url}/token", body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, tokens} ->
            {:ok, atomize_keys(tokens)}

          {:error, reason} ->
            {:error, {:token_decode_failed, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:token_exchange_failed, status, response_body}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  defp refresh_access_token(refresh_token) do
    token_params = %{
      client_id: get_oauth_client_id(),
      client_secret: get_oauth_client_secret(),
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(token_params)

    case HTTPoison.post("#{@oauth_base_url}/token", body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, tokens} ->
            {:ok, atomize_keys(tokens)}

          {:error, reason} ->
            {:error, {:refresh_decode_failed, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:refresh_failed, status, response_body}}

      {:error, reason} ->
        {:error, {:refresh_request_failed, reason}}
    end
  end

  defp calculate_expiry(nil), do: nil

  defp calculate_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
  end

  defp calculate_expiry(_), do: nil

  defp generate_state do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp get_default_redirect_uri do
    "http://localhost:4000/auth/openai/callback"
  end

  defp atomize_keys(map) when is_map(map) do
    for {key, value} <- map, into: %{} do
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      {atom_key, value}
    end
  end

  defp get_oauth_client_id do
    Application.get_env(:the_maestro, [:providers, :openai, :oauth_client_id])
  end

  defp get_oauth_client_secret do
    Application.get_env(:the_maestro, [:providers, :openai, :oauth_client_secret])
  end
end

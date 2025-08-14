defmodule TheMaestro.Providers.Auth.GoogleAuth do
  @moduledoc """
  Google (Gemini) authentication provider implementation.

  This module extends the existing Gemini authentication system to work with
  the new multi-provider authentication architecture while maintaining
  compatibility with existing OAuth flows.
  """

  @behaviour TheMaestro.Providers.Auth.ProviderAuth

  alias TheMaestro.Providers.Auth.ProviderAuth
  alias TheMaestro.Providers.Gemini

  require Logger

  @impl ProviderAuth
  def get_available_methods(:google) do
    methods = [:api_key]

    # OAuth is always available for Google/Gemini
    [:oauth | methods]
  end

  @impl ProviderAuth
  def authenticate(:google, :api_key, %{api_key: api_key} = _params) do
    case validate_api_key(api_key) do
      :ok ->
        credentials = %{
          api_key: api_key,
          token_type: "api_key"
        }

        Logger.info("Successfully authenticated with Google/Gemini using API key")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("Google/Gemini API key validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def authenticate(:google, :oauth, %{oauth_code: code, redirect_uri: redirect_uri} = _params) do
    case Gemini.exchange_authorization_code(code, redirect_uri) do
      {:ok, tokens} ->
        credentials = %{
          access_token: tokens[:access_token],
          refresh_token: tokens[:refresh_token],
          expires_at: calculate_expiry(tokens[:expires_at]),
          token_type: "Bearer",
          scope: tokens[:scope]
        }

        Logger.info("Successfully authenticated with Google/Gemini using OAuth")
        {:ok, credentials}

      {:error, reason} ->
        Logger.error("Google/Gemini OAuth authentication failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def authenticate(:google, method, _params) do
    {:error, {:unsupported_method, method}}
  end

  @impl ProviderAuth
  def validate_credentials(:google, %{api_key: api_key}) do
    case validate_api_key(api_key) do
      :ok -> {:ok, %{api_key: api_key, token_type: "api_key"}}
      error -> error
    end
  end

  def validate_credentials(:google, %{access_token: _token} = credentials) do
    # Create a temporary auth context to use existing Gemini validation
    auth_context = %{
      type: :oauth,
      credentials: credentials,
      config: %{}
    }

    case Gemini.validate_auth(auth_context) do
      :ok ->
        {:ok, credentials}

      {:error, :expired} ->
        # Try to refresh if we have a refresh token
        case credentials[:refresh_token] do
          nil -> {:error, :expired}
          _refresh_token -> refresh_credentials(:google, credentials)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_credentials(:google, credentials) do
    Logger.error("Invalid credential format for Google/Gemini: #{inspect(credentials)}")
    {:error, :invalid_credentials}
  end

  @impl ProviderAuth
  def refresh_credentials(:google, %{refresh_token: _refresh_token} = credentials) do
    # Create a temporary auth context to use existing Gemini refresh logic
    auth_context = %{
      type: :oauth,
      credentials: credentials,
      config: %{}
    }

    case Gemini.refresh_auth(auth_context) do
      {:ok, updated_context} ->
        refreshed_credentials = updated_context.credentials

        Logger.info("Successfully refreshed Google/Gemini OAuth credentials")
        {:ok, refreshed_credentials}

      {:error, reason} ->
        Logger.error("Failed to refresh Google/Gemini credentials: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_credentials(:google, %{api_key: _api_key} = credentials) do
    # API keys don't need refresh, just validate
    validate_credentials(:google, credentials)
  end

  def refresh_credentials(:google, _credentials) do
    {:error, {:cannot_refresh, :missing_refresh_token}}
  end

  @impl ProviderAuth
  def initiate_oauth_flow(:google, options \\ %{}) do
    {:ok, flow_data} = Gemini.web_authorization_flow(options)
    Logger.info("Initiated Google/Gemini OAuth flow")
    {:ok, flow_data.auth_url}
  end

  @impl ProviderAuth
  def exchange_oauth_code(:google, code, options \\ %{}) do
    redirect_uri = Map.get(options, :redirect_uri, get_default_redirect_uri())

    case Gemini.exchange_authorization_code(code, redirect_uri) do
      {:ok, tokens} ->
        credentials = %{
          access_token: tokens[:access_token],
          refresh_token: tokens[:refresh_token],
          expires_at: calculate_expiry(tokens[:expires_at]),
          token_type: "Bearer",
          scope: tokens[:scope]
        }

        {:ok, credentials}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp validate_api_key(api_key) when is_binary(api_key) do
    # Gemini API keys start with "AIza"
    if String.starts_with?(api_key, "AIza") and String.length(api_key) > 20 do
      # Use existing Gemini validation by creating a temporary auth context
      auth_context = %{
        type: :api_key,
        credentials: %{api_key: api_key},
        config: %{}
      }

      case Gemini.validate_auth(auth_context) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_api_key_format}
    end
  end

  defp validate_api_key(_), do: {:error, :invalid_api_key_format}

  defp calculate_expiry(nil), do: nil

  defp calculate_expiry(expires_at) when is_integer(expires_at) do
    DateTime.from_unix(expires_at)
    |> case do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp calculate_expiry(%DateTime{} = datetime), do: datetime

  defp calculate_expiry(_), do: nil

  defp get_default_redirect_uri do
    "http://localhost:4000/auth/google/callback"
  end
end

defmodule TheMaestro.Providers.Auth do
  @moduledoc """
  Main authentication coordinator for multi-provider LLM authentication.

  This module provides a unified interface for authenticating with different LLM providers
  (Anthropic Claude, Google Gemini, OpenAI ChatGPT) using various authentication methods
  (OAuth, API keys). It handles credential storage, validation, and refresh operations.
  """

  alias TheMaestro.Providers.Auth.{
    CredentialStore,
    ProviderAuth,
    ProviderRegistry
  }

  alias TheMaestro.Providers.LLMProvider

  require Logger

  @typedoc """
  Authentication result containing provider context.
  """
  @type auth_result :: %{
          provider: ProviderAuth.provider(),
          method: ProviderAuth.auth_method(),
          credentials: ProviderAuth.credentials(),
          auth_context: LLMProvider.auth_context()
        }

  @doc """
  Lists all available providers and their supported authentication methods.

  ## Returns
    A map of providers to their available authentication methods
  """
  @spec get_available_providers() :: %{ProviderAuth.provider() => [ProviderAuth.auth_method()]}
  def get_available_providers do
    ProviderRegistry.list_providers()
    |> Enum.into(%{}, fn provider ->
      methods = ProviderRegistry.get_provider_methods(provider)
      {provider, methods}
    end)
  end

  @doc """
  Authenticates with a specific provider using the given method.

  ## Parameters
    - `provider`: The LLM provider to authenticate with
    - `method`: The authentication method to use
    - `params`: Authentication parameters
    - `user_id`: User identifier for credential storage

  ## Returns
    - `{:ok, auth_result}`: Successfully authenticated
    - `{:error, reason}`: Authentication failed
  """
  @spec authenticate(ProviderAuth.provider(), ProviderAuth.auth_method(), map(), String.t()) ::
          {:ok, auth_result()} | {:error, term()}
  def authenticate(provider, method, params, user_id) do
    Logger.info("Authenticating with provider: #{provider}, method: #{method}")

    with {:ok, provider_module} <- ProviderRegistry.get_provider_module(provider),
         {:ok, credentials} <- provider_module.authenticate(provider, method, params),
         {:ok, stored_credentials} <-
           CredentialStore.store_credentials(user_id, provider, method, credentials),
         {:ok, auth_context} <- build_auth_context(provider, method, stored_credentials) do
      result = %{
        provider: provider,
        method: method,
        credentials: stored_credentials,
        auth_context: auth_context
      }

      Logger.info("Successfully authenticated with #{provider} using #{method}")
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("Authentication failed for #{provider}/#{method}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves valid credentials for a user and provider.

  This function will attempt to load cached credentials and validate them,
  refreshing if necessary and possible.

  ## Parameters
    - `user_id`: User identifier
    - `provider`: The LLM provider
    - `method`: Optional specific authentication method to use

  ## Returns
    - `{:ok, auth_result}`: Valid credentials found/refreshed
    - `{:error, reason}`: No valid credentials available
  """
  @spec get_credentials(String.t(), ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          {:ok, auth_result()} | {:error, term()}
  def get_credentials(user_id, provider, method \\ nil) do
    with {:ok, provider_module} <- ProviderRegistry.get_provider_module(provider),
         {:ok, stored_creds} <- CredentialStore.get_credentials(user_id, provider, method),
         {:ok, validated_creds} <-
           provider_module.validate_credentials(provider, stored_creds.credentials) do
      # Update stored credentials if they were refreshed during validation
      if validated_creds != stored_creds.credentials do
        CredentialStore.update_credentials(stored_creds.id, validated_creds)
      end

      {:ok, build_auth_result(provider, stored_creds.auth_method, validated_creds)}
    else
      {:error, :not_found} ->
        {:error, :credentials_not_found}

      {:error, :expired} = error ->
        # Try to refresh if possible
        case attempt_refresh(user_id, provider, method) do
          {:ok, result} -> {:ok, result}
          {:error, _} -> error
        end

      {:error, reason} = error ->
        Logger.error("Failed to get credentials for #{user_id}/#{provider}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Initiates OAuth authorization flow for a provider.

  ## Parameters
    - `provider`: The LLM provider
    - `options`: OAuth flow options

  ## Returns
    - `{:ok, auth_url}`: Authorization URL for user to visit
    - `{:error, reason}`: Failed to initiate flow
  """
  @spec initiate_oauth_flow(ProviderAuth.provider(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def initiate_oauth_flow(provider, options \\ %{}) do
    with {:ok, provider_module} <- ProviderRegistry.get_provider_module(provider) do
      provider_module.initiate_oauth_flow(provider, options)
    end
  end

  @doc """
  Completes OAuth authorization by exchanging code for tokens.

  ## Parameters
    - `provider`: The LLM provider
    - `code`: Authorization code from OAuth callback
    - `user_id`: User identifier for credential storage
    - `options`: Exchange options

  ## Returns
    - `{:ok, auth_result}`: Successfully completed OAuth flow
    - `{:error, reason}`: OAuth completion failed
  """
  @spec complete_oauth_flow(ProviderAuth.provider(), String.t(), String.t(), map()) ::
          {:ok, auth_result()} | {:error, term()}
  def complete_oauth_flow(provider, code, user_id, options \\ %{}) do
    with {:ok, provider_module} <- ProviderRegistry.get_provider_module(provider),
         {:ok, credentials} <- provider_module.exchange_oauth_code(provider, code, options),
         {:ok, stored_credentials} <-
           CredentialStore.store_credentials(user_id, provider, :oauth, credentials),
         {:ok, auth_context} <- build_auth_context(provider, :oauth, stored_credentials) do
      result = %{
        provider: provider,
        method: :oauth,
        credentials: stored_credentials,
        auth_context: auth_context
      }

      Logger.info("Successfully completed OAuth flow for #{user_id}/#{provider}")
      {:ok, result}
    end
  end

  @doc """
  Revokes/removes stored credentials for a user and provider.

  ## Parameters
    - `user_id`: User identifier
    - `provider`: The LLM provider
    - `method`: Optional specific method to remove

  ## Returns
    - `:ok`: Credentials removed
    - `{:error, reason}`: Failed to remove credentials
  """
  @spec revoke_credentials(String.t(), ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          :ok | {:error, term()}
  def revoke_credentials(user_id, provider, method \\ nil) do
    CredentialStore.delete_credentials(user_id, provider, method)
  end

  @doc """
  Lists all stored credentials for a user.

  ## Parameters
    - `user_id`: User identifier

  ## Returns
    List of stored credential summaries (no sensitive data)
  """
  @spec list_user_credentials(String.t()) :: [map()]
  def list_user_credentials(user_id) do
    CredentialStore.list_user_credentials(user_id)
  end

  # Private Functions

  defp build_auth_context(provider, method, credentials) do
    auth_type =
      case method do
        :oauth -> :oauth
        :api_key -> :api_key
      end

    context = %{
      type: auth_type,
      credentials: credentials,
      config: %{provider: provider}
    }

    {:ok, context}
  end

  defp build_auth_result(provider, method, credentials) do
    {:ok, auth_context} = build_auth_context(provider, method, credentials)

    %{
      provider: provider,
      method: method,
      credentials: credentials,
      auth_context: auth_context
    }
  end

  defp attempt_refresh(user_id, provider, method) do
    with {:ok, provider_module} <- ProviderRegistry.get_provider_module(provider),
         {:ok, stored_creds} <- CredentialStore.get_credentials(user_id, provider, method),
         {:ok, refreshed_creds} <-
           provider_module.refresh_credentials(provider, stored_creds.credentials),
         {:ok, _} <- CredentialStore.update_credentials(stored_creds.id, refreshed_creds) do
      Logger.info("Successfully refreshed credentials for #{user_id}/#{provider}")
      {:ok, build_auth_result(provider, stored_creds.auth_method, refreshed_creds)}
    else
      error ->
        Logger.error(
          "Failed to refresh credentials for #{user_id}/#{provider}: #{inspect(error)}"
        )

        error
    end
  end
end

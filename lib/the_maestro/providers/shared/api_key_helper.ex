defmodule TheMaestro.Providers.Shared.APIKeyHelper do
  @moduledoc """
  Shared utilities for API key providers.

  CRITICAL: Only extracts common patterns - NO changes to actual API calls,
  headers, or authentication logic. Provider-specific behavior is preserved.
  """

  alias TheMaestro.Provider
  alias TheMaestro.SavedAuthentication

  @doc """
  Common create_session logic with provider-specific validation callback.

  This extracts the repeated pattern of:
  1. Extract name and credentials from opts
  2. Validate session name
  3. Validate API key (using provider-specific function)
  4. Persist session

  Each provider maintains its own validation logic and credential structure.
  """
  @spec create_session(atom(), keyword(), function()) ::
          {:ok, String.t()} | {:error, term()}
  def create_session(provider, opts, validate_api_key_fn) when is_list(opts) do
    name = Keyword.get(opts, :name)
    credentials = Keyword.get(opts, :credentials) || %{}
    api_key = extract_api_key(credentials)

    with :ok <- Provider.validate_session_name(name),
         :ok <- validate_api_key_fn.(api_key),
         {:ok, _sa} <- persist_session(provider, name, api_key, credentials) do
      {:ok, name}
    else
      {:error, _} = err -> err
    end
  end

  @doc """
  Common delete_session logic.

  All providers have identical delete logic - this extracts the duplication
  while keeping the provider and auth_type parameters provider-specific.
  """
  @spec delete_session(atom(), atom(), String.t()) :: :ok | {:error, term()}
  def delete_session(provider, auth_type, session_id) when is_binary(session_id) do
    case SavedAuthentication.delete_named_session(provider, auth_type, session_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc """
  Extract API key from credentials map.

  Handles both string and atom keys consistently across providers.
  """
  def extract_api_key(credentials) do
    Map.get(credentials, "api_key") || Map.get(credentials, :api_key)
  end

  # Private helper functions

  @spec persist_session(atom(), String.t(), String.t(), map()) ::
          {:ok, SavedAuthentication.t()} | {:error, term()}
  defp persist_session(provider, name, api_key, credentials) do
    credentials_map = build_credentials_map(provider, api_key, credentials)

    SavedAuthentication.upsert_named_session(provider, :api_key, name, %{
      credentials: credentials_map,
      expires_at: nil
    })
  end

  # Provider-specific credential building
  # CRITICAL: Each provider maintains its specific credential format

  defp build_credentials_map(:gemini, api_key, credentials) do
    # Gemini-specific: include user_project if present
    user_project = Map.get(credentials, "user_project") || Map.get(credentials, :user_project)
    %{api_key: api_key, user_project: user_project}
  end

  defp build_credentials_map(_provider, api_key, _credentials) do
    # Default: just the API key
    %{api_key: api_key}
  end
end

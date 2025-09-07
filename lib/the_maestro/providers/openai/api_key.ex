defmodule TheMaestro.Providers.OpenAI.APIKey do
  @moduledoc """
  OpenAI API Key provider implementation.

  Provides creation of named API key sessions and client helpers.
  """

  @behaviour TheMaestro.Providers.Behaviours.Auth
  @behaviour TheMaestro.Providers.Behaviours.APIKeyProvider

  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Shared.{APIKeyHelper, ConnectionTester}
  alias TheMaestro.Types

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    # Use shared helper while maintaining EXACT same logic
    APIKeyHelper.create_session(:openai, opts, &validate_api_key/1)
  end

  def create_session(_), do: {:error, :invalid_options}

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(session_id) when is_binary(session_id) do
    # Use shared helper - identical logic across all providers
    APIKeyHelper.delete_session(:openai, :api_key, session_id)
  end

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(_session_id), do: {:error, :not_applicable}

  @impl true
  @spec validate_api_key(String.t()) :: :ok | {:error, term()}
  def validate_api_key(api_key) when is_binary(api_key) do
    cond do
      api_key == "" -> {:error, :invalid_api_key}
      String.starts_with?(api_key, "sk-") and String.length(api_key) > 20 -> :ok
      true -> {:error, :invalid_api_key_format}
    end
  end

  def validate_api_key(_), do: {:error, :invalid_api_key}

  @impl true
  @spec create_client(String.t(), keyword()) :: {:ok, Req.Request.t()} | {:error, term()}
  def create_client(api_key, opts \\ []) do
    with :ok <- validate_api_key(api_key),
         {:ok, req} <- ReqClientFactory.create_client(:openai, :api_key, opts) do
      # Override Authorization header with provided api_key if needed
      req = Req.Request.put_header(req, "authorization", "Bearer " <> api_key)
      {:ok, req}
    end
  end

  @impl true
  @spec test_connection(Req.Request.t()) :: :ok | {:error, term()}
  def test_connection(%Req.Request{} = req) do
    # CRITICAL: Keep OpenAI-specific endpoint exactly as is
    # Only the response handling is shared
    ConnectionTester.test_connection(req, "/v1/models")
  end

  # no-op
end

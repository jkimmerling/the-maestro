defmodule TheMaestro.Providers.OpenAI.APIKey do
  @moduledoc """
  OpenAI API Key provider implementation.

  Provides creation of named API key sessions and client helpers.
  """

  @behaviour TheMaestro.Providers.Behaviours.Auth
  @behaviour TheMaestro.Providers.Behaviours.APIKeyProvider

  require Logger
  alias TheMaestro.Provider
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    name = Keyword.get(opts, :name)
    credentials = Keyword.get(opts, :credentials) || %{}
    api_key = Map.get(credentials, "api_key") || Map.get(credentials, :api_key)

    with :ok <- Provider.validate_session_name(name),
         :ok <- validate_api_key(api_key),
         {:ok, _sa} <-
           SavedAuthentication.upsert_named_session(:openai, :api_key, name, %{
             credentials: %{api_key: api_key},
             expires_at: nil
           }) do
      {:ok, name}
    else
      {:error, _} = err -> err
    end
  end

  def create_session(_), do: {:error, :invalid_options}

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(session_id) when is_binary(session_id) do
    case SavedAuthentication.delete_named_session(:openai, :api_key, session_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, _} = err -> err
    end
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
    case Req.request(req, method: :get, url: "/v1/models") do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, (is_binary(body) && body) || Jason.encode!(body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  # no-op
end

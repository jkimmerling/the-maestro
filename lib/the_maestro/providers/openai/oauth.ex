defmodule TheMaestro.Providers.OpenAI.OAuth do
  @moduledoc """
  OpenAI OAuth provider implementation using Req.

  Supports creating named OAuth sessions by exchanging an authorization code
  (PKCE) and persisting the resulting credentials. Also supports token refresh
  for ChatGPT-mode OAuth flows when a refresh token is available.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth

  require Logger
  alias TheMaestro.Auth
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    with {:ok, name, code, pkce} <- validate_opts(opts) do
      do_create_session(name, code, pkce)
    end
  end

  def create_session(_), do: {:error, :invalid_options}

  defp do_create_session(name, code, pkce) do
    with {:ok, %Auth.OAuthToken{} = tokens} <- Auth.exchange_openai_code_for_tokens(code, pkce),
         mode <- openai_mode_from_tokens(tokens) do
      case mode do
        :chatgpt ->
          case Auth.persist_oauth_token(:openai, name, tokens) do
            :ok -> {:ok, name}
            {:error, reason} -> {:error, reason}
          end

        :api_key ->
          exchange_and_persist_api_key(name, tokens)
      end
    end
  end

  defp exchange_and_persist_api_key(name, %Auth.OAuthToken{} = tokens) do
    with {:ok, api_key} <- Auth.exchange_openai_id_token_for_api_key(tokens.id_token),
         {:ok, _sa} <-
           SavedAuthentication.upsert_named_session(:openai, :api_key, name, %{
             credentials: %{api_key: api_key},
             expires_at: nil
           }) do
      {:ok, name}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp openai_mode_from_tokens(%Auth.OAuthToken{id_token: nil}), do: :chatgpt

  defp openai_mode_from_tokens(%Auth.OAuthToken{id_token: idt}) do
    case Auth.determine_openai_auth_mode(idt) do
      {:ok, m} -> m
      _ -> :chatgpt
    end
  end

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id), do: :ok

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(session_name) when is_binary(session_name) do
    with %SavedAuthentication{credentials: %{"refresh_token" => refresh_token}} <-
           SavedAuthentication.get_named_session(:openai, :oauth, session_name),
         true <-
           (is_binary(refresh_token) and refresh_token != "") or {:error, :no_refresh_token},
         {:ok, config} <- Auth.get_openai_oauth_config(),
         headers <- [{"content-type", "application/x-www-form-urlencoded"}],
         body <-
           URI.encode_query(%{
             "grant_type" => "refresh_token",
             "client_id" => config.client_id,
             "refresh_token" => refresh_token
           }),
         req <- Req.new(headers: headers, finch: :openai_finch),
         {:ok, %Req.Response{status: 200, body: raw}} <-
           Req.request(req, method: :post, url: config.token_endpoint, body: body),
         decoded <- if(is_binary(raw), do: Jason.decode!(raw), else: raw),
         {:ok, %Auth.OAuthToken{} = token} <- Auth.validate_openai_token_response(decoded),
         :ok <- Auth.persist_oauth_token(:openai, session_name, token) do
      {:ok,
       %{
         access_token: token.access_token,
         refresh_token: token.refresh_token,
         token_type: token.token_type,
         expiry: token.expiry,
         scope: token.scope
       }}
    else
      %SavedAuthentication{} ->
        {:error, :no_refresh_token}

      nil ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         {:token_refresh_failed, status, (is_binary(body) && body) || Jason.encode!(body)}}

      {:error, _} = err ->
        err
    end
  end

  # Input validation helpers
  defp validate_opts(opts) do
    name = Keyword.get(opts, :name)
    code = Keyword.get(opts, :auth_code) || Keyword.get(opts, :code)
    pkce = Keyword.get(opts, :pkce_params)

    cond do
      !is_binary(name) or name == "" -> {:error, :missing_session_name}
      !is_binary(code) or code == "" -> {:error, :missing_auth_code}
      is_nil(pkce) -> {:error, :missing_pkce_params}
      true -> {:ok, name, code, pkce}
    end
  end
end

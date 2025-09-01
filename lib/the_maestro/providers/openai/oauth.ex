defmodule TheMaestro.Providers.OpenAI.OAuth do
  @moduledoc """
  OpenAI OAuth provider implementation using Req.

  Supports creating named OAuth sessions by exchanging an authorization code
  (PKCE) and persisting the resulting credentials. Also supports token refresh
  for ChatGPT-mode OAuth flows when a refresh token is available.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth

  require Logger
  alias TheMaestro.Types
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Auth

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    name = Keyword.get(opts, :name)
    code = Keyword.get(opts, :auth_code) || Keyword.get(opts, :code)
    pkce = Keyword.get(opts, :pkce_params)

    cond do
      is_nil(name) or name == "" -> {:error, :missing_session_name}
      is_nil(code) or code == "" -> {:error, :missing_auth_code}
      is_nil(pkce) -> {:error, :missing_pkce_params}
      true -> do_create_session(name, code, pkce)
    end
  end

  def create_session(_), do: {:error, :invalid_options}

  defp do_create_session(name, code, pkce) do
    with {:ok, %Auth.OAuthToken{} = tokens} <- Auth.exchange_openai_code_for_tokens(code, pkce) do
      mode =
        case tokens.id_token do
          nil ->
            :chatgpt

          idt ->
            case Auth.determine_openai_auth_mode(idt) do
              {:ok, m} -> m
              _ -> :chatgpt
            end
        end

      case mode do
        :chatgpt ->
          case Auth.persist_oauth_token(:openai, name, tokens) do
            :ok -> {:ok, name}
            {:error, reason} -> {:error, reason}
          end

        :api_key ->
          with {:ok, api_key} <- Auth.exchange_openai_id_token_for_api_key(tokens.id_token),
               {:ok, _sa} <-
                 SavedAuthentication.upsert_named_session(:openai, :oauth, name, %{
                   credentials: %{"access_token" => api_key, "token_type" => "Bearer"},
                   expires_at: nil
                 }) do
            {:ok, name}
          else
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id), do: :ok

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(session_name) when is_binary(session_name) do
    case SavedAuthentication.get_named_session(:openai, :oauth, session_name) do
      %SavedAuthentication{credentials: %{"refresh_token" => refresh_token}} = _saved
      when is_binary(refresh_token) and refresh_token != "" ->
        with {:ok, config} <- Auth.get_openai_oauth_config() do
          headers = [{"content-type", "application/x-www-form-urlencoded"}]

          body =
            URI.encode_query(%{
              "grant_type" => "refresh_token",
              "client_id" => config.client_id,
              "refresh_token" => refresh_token
            })

          req = Req.new(headers: headers, finch: :openai_finch)

          case Req.request(req, method: :post, url: config.token_endpoint, body: body) do
            {:ok, %Req.Response{status: 200, body: raw}} ->
              decoded = if is_binary(raw), do: Jason.decode!(raw), else: raw

              with {:ok, %Auth.OAuthToken{} = token} <-
                     Auth.validate_openai_token_response(decoded),
                   :ok <- Auth.persist_oauth_token(:openai, session_name, token) do
                {:ok,
                 %{
                   access_token: token.access_token,
                   refresh_token: token.refresh_token,
                   token_type: token.token_type,
                   expiry: token.expiry,
                   scope: token.scope
                 }}
              end

            {:ok, %Req.Response{status: status, body: body}} ->
              {:error,
               {:token_refresh_failed, status, (is_binary(body) && body) || Jason.encode!(body)}}

            {:error, reason} ->
              {:error, {:token_refresh_request_failed, reason}}
          end
        end

      %SavedAuthentication{} ->
        {:error, :no_refresh_token}

      _ ->
        {:error, :not_found}
    end
  end
end

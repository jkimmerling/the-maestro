defmodule TheMaestro.Providers.Anthropic.OAuth do
  @moduledoc """
  Anthropic OAuth provider implementation using Req.

  Supports creating named OAuth sessions by exchanging an authorization code
  (PKCE) and persisting the resulting credentials. Also supports token refresh
  via Anthropic's JSON token endpoint when a refresh token is available.
  """
  @behaviour TheMaestro.Providers.Behaviours.Auth

  alias TheMaestro.Auth
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    with {:ok, name, code, pkce} <- validate_opts(opts),
         {:ok, %Auth.OAuthToken{} = token} <- Auth.exchange_code_for_tokens(code, pkce),
         :ok <- Auth.persist_oauth_token(:anthropic, name, token) do
      {:ok, name}
    end
  end

  def create_session(_), do: {:error, :invalid_options}

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id), do: :ok

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(session_name) when is_binary(session_name) do
    with %SavedAuthentication{credentials: %{"refresh_token" => refresh_token}} <-
           SavedAuthentication.get_named_session(:anthropic, :oauth, session_name),
         true <-
           (is_binary(refresh_token) and refresh_token != "") or {:error, :no_refresh_token},
         cfg <- Auth.AnthropicOAuthConfig.__struct__(),
         headers <- [{"content-type", "application/json"}],
         body <- %{
           "grant_type" => "refresh_token",
           "client_id" => cfg.client_id,
           "refresh_token" => refresh_token
         },
         req <- Req.new(headers: headers, finch: :anthropic_finch),
         {:ok, %Req.Response{status: 200, body: raw}} <-
           Req.request(req, method: :post, url: cfg.token_endpoint, json: body),
         decoded <- if(is_binary(raw), do: Jason.decode!(raw), else: raw),
         {:ok, %Auth.OAuthToken{} = token} <- map_token_response(decoded),
         :ok <- Auth.persist_oauth_token(:anthropic, session_name, token) do
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

    code =
      Keyword.get(opts, :auth_code_input) || Keyword.get(opts, :auth_code) ||
        Keyword.get(opts, :code)

    pkce = Keyword.get(opts, :pkce_params)

    cond do
      !is_binary(name) or name == "" -> {:error, :missing_session_name}
      !is_binary(code) or code == "" -> {:error, :missing_auth_code}
      is_nil(pkce) -> {:error, :missing_pkce_params}
      true -> {:ok, name, code, pkce}
    end
  end

  # Local mapping to Auth.OAuthToken for Anthropic responses
  defp map_token_response(response_body) do
    case response_body do
      %{"access_token" => access_token, "expires_in" => expires_in} = data ->
        expiry = System.system_time(:second) + expires_in

        {:ok,
         %Auth.OAuthToken{
           access_token: access_token,
           refresh_token: Map.get(data, "refresh_token"),
           expiry: expiry,
           scope: Map.get(data, "scope"),
           token_type: Map.get(data, "token_type", "Bearer")
         }}

      _ ->
        {:error, :invalid_token_response}
    end
  end
end

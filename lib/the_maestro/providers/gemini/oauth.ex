defmodule TheMaestro.Providers.Gemini.OAuth do
  @moduledoc """
  Gemini OAuth provider implementation using Google OAuth 2.0 (PKCE).

  Implements named session creation by exchanging an authorization code
  for tokens at Google's OAuth token endpoint and persists credentials
  in `SavedAuthentication`. Supports token refresh.
  """

  @behaviour TheMaestro.Providers.Behaviours.Auth

  require Logger

  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types
  @dialyzer {:nowarn_function, persist_tokens: 2}

  @google_oauth_token_url "https://oauth2.googleapis.com/token"

  # Defaults aligned with gemini-cli reference (installed application flow)
  @default_client_id "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
  @default_client_secret "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"

  @doc false
  @spec client_id() :: String.t()
  def client_id do
    System.get_env("GEMINI_OAUTH_CLIENT_ID") || @default_client_id
  end

  @doc false
  @spec client_secret() :: String.t()
  def client_secret do
    System.get_env("GEMINI_OAUTH_CLIENT_SECRET") || @default_client_secret
  end

  @doc false
  @spec redirect_uri() :: String.t()
  def redirect_uri do
    # Fallback to standard localhost callback used by gemini-cli
    System.get_env("GEMINI_OAUTH_REDIRECT_URI") || "http://localhost:1455/oauth2callback"
  end

  @impl true
  @spec create_session(Types.request_opts()) :: {:ok, Types.session_id()} | {:error, term()}
  def create_session(opts) when is_list(opts) do
    name = Keyword.get(opts, :name)

    code =
      Keyword.get(opts, :auth_code_input) || Keyword.get(opts, :auth_code) ||
        Keyword.get(opts, :code)

    pkce = Keyword.get(opts, :pkce_params)

    with :ok <- validate_name(name),
         {:ok, token_map} <- exchange_code_for_tokens(code, pkce),
         {:ok, _saved} <- persist_tokens(name, token_map) do
      {:ok, name}
    else
      {:error, _} = err -> err
    end
  end

  def create_session(_), do: {:error, :invalid_options}

  @impl true
  @spec delete_session(Types.session_id()) :: :ok | {:error, term()}
  def delete_session(_session_id), do: :ok

  @impl true
  @spec refresh_tokens(Types.session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(session_name) when is_binary(session_name) do
    with %SavedAuthentication{credentials: %{"refresh_token" => refresh}} <-
           SavedAuthentication.get_named_session(:gemini, :oauth, session_name),
         true <- (is_binary(refresh) and refresh != "") or {:error, :no_refresh_token},
         {:ok, resp} <- refresh_token(refresh),
         {:ok, _saved} <- persist_tokens(session_name, resp) do
      {:ok, resp}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  # ===== Internal: token exchange and refresh =====

  @spec exchange_code_for_tokens(String.t() | nil, map() | nil) :: {:ok, map()} | {:error, term()}
  def exchange_code_for_tokens(code, pkce) do
    cond do
      !is_binary(code) or code == "" -> {:error, :missing_auth_code}
      is_nil(pkce) -> {:error, :missing_pkce_params}
      true -> do_code_exchange(code, pkce)
    end
  end

  defp do_code_exchange(code, pkce) do
    payload = %{
      grant_type: "authorization_code",
      client_id: client_id(),
      client_secret: client_secret(),
      code: code,
      code_verifier: pkce[:code_verifier] || pkce["code_verifier"],
      redirect_uri: redirect_uri()
    }

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    req = Req.new(headers: headers, finch: :gemini_finch)

    case Req.request(req, method: :post, url: @google_oauth_token_url, form: payload) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decoded = if is_binary(body), do: Jason.decode!(body), else: body
        map_token_response(decoded)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         {:token_exchange_failed, status, (is_binary(body) && body) || Jason.encode!(body)}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  @spec refresh_token(String.t()) :: {:ok, map()} | {:error, term()}
  defp refresh_token(refresh_token) do
    payload = %{
      grant_type: "refresh_token",
      client_id: client_id(),
      client_secret: client_secret(),
      refresh_token: refresh_token
    }

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    req = Req.new(headers: headers, finch: :gemini_finch)

    case Req.request(req, method: :post, url: @google_oauth_token_url, form: payload) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decoded = if is_binary(body), do: Jason.decode!(body), else: body
        map_token_response(decoded)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         {:token_refresh_failed, status, (is_binary(body) && body) || Jason.encode!(body)}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  @spec map_token_response(map()) :: {:ok, map()} | {:error, term()}
  defp map_token_response(%{"access_token" => access_token, "expires_in" => expires_in} = data) do
    expiry_unix = System.system_time(:second) + expires_in

    {:ok,
     %{
       access_token: access_token,
       refresh_token: Map.get(data, "refresh_token"),
       token_type: Map.get(data, "token_type", "Bearer"),
       scope: Map.get(data, "scope"),
       expiry: expiry_unix
     }}
  end

  defp map_token_response(_), do: {:error, :invalid_token_response}

  @spec persist_tokens(String.t(), map()) :: {:ok, SavedAuthentication.t()} | {:error, term()}
  defp persist_tokens(session_name, token_map) do
    expires_at =
      case token_map[:expiry] || token_map["expiry"] do
        nil -> nil
        unix when is_integer(unix) -> DateTime.from_unix!(unix)
      end

    SavedAuthentication.upsert_named_session(:gemini, :oauth, session_name, %{
      credentials: %{
        access_token: token_map[:access_token] || token_map["access_token"],
        refresh_token: token_map[:refresh_token] || token_map["refresh_token"],
        token_type: token_map[:token_type] || token_map["token_type"],
        scope: token_map[:scope] || token_map["scope"]
      },
      expires_at: expires_at
    })
  end

  @spec validate_name(term()) :: :ok | {:error, term()}
  defp validate_name(name) when is_binary(name) and name != "", do: :ok
  defp validate_name(_), do: {:error, :missing_session_name}
end

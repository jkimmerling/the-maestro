defmodule TheMaestro.OAuthCallbackPlug do
  @moduledoc """
  Minimal Plug to receive OAuth redirects on http://localhost:1455/auth/callback.

  It reads `code` and `state`, looks up PKCE/session in `TheMaestro.OAuthState`,
  completes the provider OAuth flow by calling `TheMaestro.Provider.create_session/3`,
  and renders a simple HTML success or error page.
  """

  import Plug.Conn
  alias TheMaestro.OAuthCallbackRuntime
  alias TheMaestro.OAuthState
  alias TheMaestro.Provider
  require Logger

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/auth/callback"} = conn, _opts) do
    params = fetch_query_params(conn).params
    code = Map.get(params, "code")
    state = Map.get(params, "state")

    mapping = if is_binary(state), do: OAuthState.take(state), else: nil

    case {code, state, mapping} do
      {code, state, %{provider: provider, session_name: name, pkce_params: pkce}}
      when is_binary(code) and is_binary(state) ->
        result =
          Provider.create_session(provider, :oauth,
            name: name,
            pkce_params: normalize_pkce(pkce),
            auth_code: code
          )

        # Mapping already consumed via take/1; no further action
        # Broadcast completion to UI and stop runtime server
        case result do
          {:ok, _} ->
            TheMaestroWeb.Endpoint.broadcast("oauth:events", "completed", %{
              provider: to_string(provider),
              session_name: name
            })

            OAuthCallbackRuntime.notify_success()

          _ ->
            :ok
        end

        respond(conn, result)

      _ ->
        respond(conn, {:error, :invalid_or_missing_state})
    end
  end

  def call(conn, _opts) do
    send_resp(conn, 404, "Not Found")
  end

  defp normalize_pkce(list) when is_list(list), do: Map.new(list)
  defp normalize_pkce(%{code_verifier: _} = pkce), do: pkce
  defp normalize_pkce(%TheMaestro.Auth.PKCEParams{} = pkce), do: Map.from_struct(pkce)
  defp normalize_pkce(pkce) when is_map(pkce), do: pkce

  defp respond(conn, {:ok, _session}) do
    html = ~s(
      <html><body style="font-family: system-ui;">
        <h1>✅ OAuth Success</h1>
        <p>You can return to the app. This window can be closed.</p>
        <p><a href="/dashboard">Go to Dashboard</a></p>
      </body></html>
    )
    send_resp(conn, 200, html)
  end

  defp respond(conn, {:error, reason}) do
    html = ~s(
      <html><body style="font-family: system-ui;color:#b91c1c;">
        <h1>❌ OAuth Error</h1>
        <p>#{Plug.HTML.html_escape(to_string(reason))}</p>
      </body></html>
    )
    send_resp(conn, 400, html)
  end
end

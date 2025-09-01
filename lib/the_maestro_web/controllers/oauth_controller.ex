defmodule TheMaestroWeb.OAuthController do
  use TheMaestroWeb, :controller

  alias TheMaestro.Auth

  def openai_callback(conn, %{"code" => code, "session" => session} = _params) do
    pkce = Auth.generate_pkce_params()

    result = Auth.finish_openai_oauth(code, pkce, session)
    json(conn, %{result: inspect(result)})
  end

  def anthropic_callback(conn, %{"code" => code, "session" => session} = _params) do
    pkce = Auth.generate_pkce_params()

    result = Auth.finish_anthropic_oauth(code, pkce, session)
    json(conn, %{result: inspect(result)})
  end

  def gemini_callback(conn, %{"code" => code, "session" => session} = params) do
    # For Gemini, we accept optional `state` param and treat it as the PKCE code_verifier.
    # This mirrors the loopback/installed-app flow patterns.
    state = Map.get(params, "state")

    pkce =
      if is_binary(state) and state != "",
        do: %{code_verifier: state},
        else: Auth.generate_pkce_params()

    result = Auth.finish_gemini_oauth(code, pkce, session)
    json(conn, %{result: inspect(result)})
  end
end

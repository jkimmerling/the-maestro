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
end

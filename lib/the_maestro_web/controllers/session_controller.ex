defmodule TheMaestroWeb.SessionController do
  use TheMaestroWeb, :controller

  def start_chat(conn, params) do
    # Extract provider/model selection from params
    provider = params["provider"]
    model = params["model"]
    auth_method = params["auth_method"]

    # Create session data
    session_data = %{
      provider: provider,
      model: model,
      auth_method: auth_method,
      selected_at: DateTime.utc_now()
    }

    # Store in session and redirect to agent
    conn
    |> put_session(:provider_selection, session_data)
    |> put_flash(:info, "Successfully configured #{provider} with #{model}")
    |> redirect(to: ~p"/agent")
  end
end

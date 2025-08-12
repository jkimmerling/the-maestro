defmodule TheMaestroWeb.AuthController do
  @moduledoc """
  Authentication controller for web-based user authentication using Google OAuth.

  This controller handles the Phoenix/LiveView authentication flow using Ueberauth,
  which is separate from the CLI OAuth flow handled by OAuthController.
  """
  use TheMaestroWeb, :controller
  plug Ueberauth

  require Logger

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("Successful OAuth authentication for user: #{auth.info.email}")

    user_info = %{
      "id" => auth.uid,
      "email" => auth.info.email,
      "name" => auth.info.name,
      "avatar" => auth.info.image
    }

    conn
    |> put_session(:current_user, user_info)
    |> put_flash(:info, "Successfully authenticated!")
    |> redirect(to: ~p"/agent")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    Logger.error("OAuth authentication failed")

    conn
    |> put_flash(:error, "Failed to authenticate. Please try again.")
    |> redirect(to: ~p"/")
  end

  @doc """
  Logs out the current user by clearing the session.
  """
  def logout(conn, _params) do
    Logger.info("User logged out")

    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  @doc """
  Redirects to Google OAuth authorization URL.
  This is typically handled by Ueberauth, but we can customize if needed.
  """
  def request(conn, _params) do
    # This is handled by Ueberauth - just redirect to the provider
    redirect(conn, external: "/auth/google")
  end
end

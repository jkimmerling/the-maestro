defmodule TheMaestroWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug to enforce authentication based on application configuration.
  
  If authentication is enabled in config, this plug will check for a valid
  session and redirect to login if not found. If authentication is disabled,
  this plug will pass through without checking.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if authentication_required?() do
      case get_session(conn, :current_user) do
        nil -> 
          conn
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/")
          |> halt()
        _user -> 
          conn
      end
    else
      # Authentication is disabled, allow access
      conn
    end
  end

  defp authentication_required? do
    Application.get_env(:the_maestro, :require_authentication, true)
  end
end
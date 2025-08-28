defmodule TheMaestroWeb.PageController do
  use TheMaestroWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

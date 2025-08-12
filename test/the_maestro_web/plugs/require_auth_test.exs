defmodule TheMaestroWeb.Plugs.RequireAuthTest do
  use TheMaestroWeb.ConnCase

  alias TheMaestroWeb.Plugs.RequireAuth

  describe "when authentication is required" do
    setup do
      # Enable authentication for these tests
      Application.put_env(:the_maestro, :require_authentication, true)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "allows access when user is logged in", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)
        |> RequireAuth.call(%{})

      refute conn.halted
    end

    test "redirects to home when user is not logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuth.call(%{})

      assert conn.halted
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) == "You must log in to access this page."
    end
  end

  describe "when authentication is disabled" do
    setup do
      # Disable authentication for these tests
      Application.put_env(:the_maestro, :require_authentication, false)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "allows access even when no user is logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> RequireAuth.call(%{})

      refute conn.halted
    end
  end
end

defmodule TheMaestroWeb.AgentLiveTest do
  use TheMaestroWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "when authentication is enabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, true)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "displays user info when logged in", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com", "name" => "Test User"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)

      {:ok, _view, html} = live(conn, ~p"/agent")

      assert html =~ "Welcome, Test User!"
      assert html =~ "Agent chat interface will be implemented in Story 2.3"
    end

    test "redirects to home when not logged in", %{conn: conn} do
      conn = init_test_session(conn, %{})

      # When authentication is enabled and no user is logged in,
      # the RequireAuth plug should redirect to home
      assert {:error,
              {:redirect, %{to: "/", flash: %{"error" => "You must log in to access this page."}}}} =
               live(conn, ~p"/agent")
    end
  end

  describe "when authentication is disabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, false)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "allows anonymous access", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, _view, html} = live(conn, ~p"/agent")

      assert html =~ "Anonymous access"
      assert html =~ "Agent chat interface will be implemented in Story 2.3"
    end
  end
end

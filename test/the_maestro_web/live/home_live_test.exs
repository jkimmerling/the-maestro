defmodule TheMaestroWeb.HomeLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, ~p"/")

    assert disconnected_html =~ "Welcome to The Maestro"
    assert render(page_live) =~ "Welcome to The Maestro"
  end

  test "displays basic navigation and layout", %{conn: conn} do
    {:ok, _page_live, html} = live(conn, ~p"/")

    assert html =~ "The Maestro"
    assert html =~ "AI Agent System"
  end

  describe "authentication enabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, true)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "shows login button when user is not logged in", %{conn: conn} do
      conn = init_test_session(conn, %{})
      
      {:ok, _page_live, html} = live(conn, ~p"/")

      assert html =~ "Login with Google"
      refute html =~ "Logout"
      refute html =~ "Open Agent Chat"
    end

    test "shows logout button and agent link when user is logged in", %{conn: conn} do
      user_info = %{"id" => "123", "email" => "test@example.com", "name" => "Test User"}
      
      conn = 
        conn
        |> init_test_session(%{})
        |> put_session(:current_user, user_info)
      
      {:ok, _page_live, html} = live(conn, ~p"/")

      assert html =~ "Open Agent Chat"
      assert html =~ "Logout"
      refute html =~ "Login with Google"
    end
  end

  describe "authentication disabled" do
    setup do
      Application.put_env(:the_maestro, :require_authentication, false)
      on_exit(fn -> Application.put_env(:the_maestro, :require_authentication, true) end)
      :ok
    end

    test "shows direct agent access without authentication", %{conn: conn} do
      conn = init_test_session(conn, %{})
      
      {:ok, _page_live, html} = live(conn, ~p"/")

      assert html =~ "Open Agent Chat"
      assert html =~ "View on GitHub"
      refute html =~ "Login with Google"
      refute html =~ "Logout"
    end
  end
end

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

  test "shows provider setup and github links", %{conn: conn} do
    conn = init_test_session(conn, %{})

    {:ok, _page_live, html} = live(conn, ~p"/")

    assert html =~ "Setup Provider & Chat"
    assert html =~ "View on GitHub"
    refute html =~ "Login with Google"
    refute html =~ "Logout"
  end
end

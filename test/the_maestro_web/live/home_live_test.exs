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
end

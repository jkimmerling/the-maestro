defmodule TheMaestroWeb.PageControllerTest do
  use TheMaestroWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Dashboard"
  end
end

defmodule TheMaestroWeb.SessionSaveWithoutMcpE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias TheMaestro.Auth

  test "create session succeeds with no MCP selected", %{conn: conn} do
    {:ok, sa} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name:
          "test_openai_api_key_session-" <> Integer.to_string(System.unique_integer([:positive])),
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, view, _} = live(conn, ~p"/dashboard")

    view |> element("button[phx-click='open_session_modal']") |> render_click()
    assert has_element?(view, "#session-modal")

    form_data = %{"session" => %{"auth_id" => sa.id}}
    view |> element("#session-modal-form") |> render_submit(form_data)

    assert render(view) =~ "Session created"
    refute has_element?(view, "#session-modal")
  end

  # Chat config save path is covered elsewhere; this test targets the session modal path specifically
end

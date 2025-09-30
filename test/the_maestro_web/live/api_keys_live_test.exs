defmodule TheMaestroWeb.ApiKeysLiveTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @label "My TUI Token"

  test "lists keys and creates with token reveal", %{conn: conn} do
    {:ok, index_live, html} = live(conn, ~p"/api_keys")
    assert html =~ "API Keys"

    assert {:ok, form_live, _} =
             index_live
             |> element("a", "New API Key")
             |> render_click()
             |> follow_redirect(conn, ~p"/api_keys/new")

    assert render(form_live) =~ "New Api key"

    assert form_live
           |> form("#api_key-form", api_key: %{"label" => ""})
           |> render_change() =~ "can&#39;t be blank"

    render_submit(form_live |> form("#api_key-form", api_key: %{"label" => @label}))

    html2 = render(form_live)
    assert html2 =~ "API key created"
    assert html2 =~ "Copy this API token now"
  end

  test "revoke from index", %{conn: conn} do
    {key, _token} = TheMaestro.ApiKeys.create_key!("Temp")
    {:ok, view, _} = live(conn, ~p"/api_keys")
    assert has_element?(view, "#api_keys-#{key.id}")
    render_click(element(view, "#api_keys-#{key.id} a", "Revoke"))
    html = render(view)
    assert html =~ "true"
  end

  test "rotate shows token", %{conn: conn} do
    {key, _token} = TheMaestro.ApiKeys.create_key!("Temp2")
    {:ok, show_live, _} = live(conn, ~p"/api_keys/#{key}")

    assert {:ok, form_live, _} =
             show_live
             |> element("a", "Rotate")
             |> render_click()
             |> follow_redirect(conn, ~p"/api_keys/#{key}/edit?return_to=show")

    render_submit(form_live |> form("#api_key-form", api_key: %{"label" => key.label}))
    html = render(form_live)
    assert html =~ "API key rotated"
    assert html =~ "Copy this API token now"
  end
end

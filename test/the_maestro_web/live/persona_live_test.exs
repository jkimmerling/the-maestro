defmodule TheMaestroWeb.PersonaLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  import TheMaestro.PersonasFixtures

  @create_attrs %{name: "some name", prompt_text: "some prompt_text"}
  @update_attrs %{name: "some updated name", prompt_text: "some updated prompt_text"}
  @invalid_attrs %{name: nil, prompt_text: nil}
  defp create_persona(_) do
    persona = persona_fixture()

    %{persona: persona}
  end

  describe "Index" do
    setup [:create_persona]

    test "lists all personas", %{conn: conn, persona: persona} do
      {:ok, _index_live, html} = live(conn, ~p"/personas")

      assert html =~ "Listing Personas"
      assert html =~ persona.name
    end

    test "saves new persona", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/personas")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Persona")
               |> render_click()
               |> follow_redirect(conn, ~p"/personas/new")

      assert render(form_live) =~ "New Persona"

      assert form_live
             |> form("#persona-form", persona: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      _ =
        form_live
        |> form("#persona-form", persona: @create_attrs)
        |> render_submit()

      {:ok, index_live, _} = live(conn, ~p"/personas")
      html = render(index_live)
      assert html =~ "some name"
    end

    test "updates persona in listing", %{conn: conn, persona: persona} do
      {:ok, index_live, _html} = live(conn, ~p"/personas")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#personas-#{persona.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/personas/#{persona}/edit")

      assert render(form_live) =~ "Edit Persona"

      assert form_live
             |> form("#persona-form", persona: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      _ =
        form_live
        |> form("#persona-form", persona: @update_attrs)
        |> render_submit()

      {:ok, index_live, _} = live(conn, ~p"/personas")
      html = render(index_live)
      assert html =~ "some updated name"
    end

    test "deletes persona in listing", %{conn: conn, persona: persona} do
      {:ok, index_live, _html} = live(conn, ~p"/personas")

      assert index_live |> element("#personas-#{persona.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#personas-#{persona.id}")
    end
  end

  describe "Show" do
    setup [:create_persona]

    test "displays persona", %{conn: conn, persona: persona} do
      {:ok, _show_live, html} = live(conn, ~p"/personas/#{persona}")

      assert html =~ "Show Persona"
      assert html =~ persona.name
    end

    test "updates persona and returns to show", %{conn: conn, persona: persona} do
      {:ok, show_live, _html} = live(conn, ~p"/personas/#{persona}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/personas/#{persona}/edit?return_to=show")

      assert render(form_live) =~ "Edit Persona"

      assert form_live
             |> form("#persona-form", persona: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      _ =
        form_live
        |> form("#persona-form", persona: @update_attrs)
        |> render_submit()

      {:ok, show_live, _} = live(conn, ~p"/personas/#{persona}")
      html = render(show_live)
      assert html =~ "some updated name"
    end
  end
end

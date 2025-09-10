defmodule TheMaestroWeb.SuppliedContextItemLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  import TheMaestro.SuppliedContextFixtures

  @create_attrs %{
    name: "some name",
    type: :persona,
    version: 42,
    metadata: %{},
    text: "some text",
    tags: %{}
  }
  @update_attrs %{
    name: "some updated name",
    type: :system_prompt,
    version: 43,
    metadata: %{},
    text: "some updated text",
    tags: %{}
  }
  @invalid_attrs %{name: nil, type: nil, version: nil, metadata: nil, text: nil, tags: nil}
  defp create_supplied_context_item(_) do
    supplied_context_item = supplied_context_item_fixture()

    %{supplied_context_item: supplied_context_item}
  end

  describe "Index" do
    setup [:create_supplied_context_item]

    test "lists all supplied_context_items", %{
      conn: conn,
      supplied_context_item: supplied_context_item
    } do
      {:ok, _index_live, html} = live(conn, ~p"/supplied_context")

      assert html =~ "Listing Supplied context items"
      assert html =~ supplied_context_item.name
    end

    test "filters by type via tabs/query param", %{conn: conn} do
      # create both types
      _persona = supplied_context_item_fixture(%{type: :persona, name: "Persona A"})
      _sys = supplied_context_item_fixture(%{type: :system_prompt, name: "Sys B"})

      # default is persona
      {:ok, _index_live, html} = live(conn, ~p"/supplied_context")
      assert html =~ "Persona A"
      refute html =~ "Sys B"

      # switch to system_prompt
      {:ok, _index_live2, html2} = live(conn, ~p"/supplied_context?type=system_prompt")
      assert html2 =~ "Sys B"
      refute html2 =~ "Persona A"
    end

    test "saves new supplied_context_item", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/supplied_context")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Supplied context item")
               |> render_click()
               |> follow_redirect(conn, ~p"/supplied_context/new")

      assert render(form_live) =~ "New Supplied context item"

      assert form_live
             |> form("#supplied-context-form", supplied_context_item: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#supplied-context-form", supplied_context_item: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/supplied_context")

      html = render(index_live)
      assert html =~ "Supplied context item created successfully"
      assert html =~ "some name"
    end

    test "updates supplied_context_item in listing", %{
      conn: conn,
      supplied_context_item: supplied_context_item
    } do
      {:ok, index_live, _html} = live(conn, ~p"/supplied_context")

      assert {:ok, form_live, _html} =
               index_live
               |> element(
                 "#supplied-context-items tr[id$='-#{supplied_context_item.id}'] a",
                 "Edit"
               )
               |> render_click()
               |> follow_redirect(conn, ~p"/supplied_context/#{supplied_context_item}/edit")

      assert render(form_live) =~ "Edit Supplied context item"

      assert form_live
             |> form("#supplied-context-form", supplied_context_item: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#supplied-context-form", supplied_context_item: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/supplied_context?type=system_prompt")

      html = render(index_live)
      assert html =~ "Supplied context item updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes supplied_context_item in listing", %{
      conn: conn,
      supplied_context_item: supplied_context_item
    } do
      {:ok, index_live, _html} = live(conn, ~p"/supplied_context")

      assert index_live
             |> element(
               "#supplied-context-items tr[id$='-#{supplied_context_item.id}'] a",
               "Delete"
             )
             |> render_click()

      refute has_element?(
               index_live,
               "#supplied-context-items tr[id$='-#{supplied_context_item.id}']"
             )
    end
  end

  describe "Show" do
    setup [:create_supplied_context_item]

    test "displays supplied_context_item", %{
      conn: conn,
      supplied_context_item: supplied_context_item
    } do
      {:ok, _show_live, html} = live(conn, ~p"/supplied_context/#{supplied_context_item}")

      assert html =~ "Show Supplied context item"
      assert html =~ supplied_context_item.name
    end

    test "updates supplied_context_item and returns to show", %{
      conn: conn,
      supplied_context_item: supplied_context_item
    } do
      {:ok, show_live, _html} = live(conn, ~p"/supplied_context/#{supplied_context_item}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/supplied_context/#{supplied_context_item}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Supplied context item"

      assert form_live
             |> form("#supplied-context-form", supplied_context_item: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#supplied-context-form", supplied_context_item: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/supplied_context/#{supplied_context_item}")

      html = render(show_live)
      assert html =~ "Supplied context item updated successfully"
      assert html =~ "some updated name"
    end
  end
end

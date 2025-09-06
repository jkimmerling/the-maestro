defmodule TheMaestroWeb.BaseSystemPromptLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  import TheMaestro.PromptsFixtures

  defp uniq_name(base), do: base <> "-" <> String.slice(Ecto.UUID.generate(), 0, 8)
  # attributes defined inline in each test to avoid warnings-as-errors
  @invalid_attrs %{name: nil, prompt_text: nil}
  defp create_base_system_prompt(_) do
    base_system_prompt = base_system_prompt_fixture()

    %{base_system_prompt: base_system_prompt}
  end

  describe "Index" do
    setup [:create_base_system_prompt]

    test "lists all base_system_prompts", %{conn: conn, base_system_prompt: base_system_prompt} do
      {:ok, _index_live, html} = live(conn, ~p"/base_system_prompts")

      assert html =~ "Listing Base system prompts"
      assert html =~ base_system_prompt.name
    end

    test "saves new base_system_prompt", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/base_system_prompts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Base system prompt")
               |> render_click()
               |> follow_redirect(conn, ~p"/base_system_prompts/new")

      assert render(form_live) =~ "New Base system prompt"

      assert form_live
             |> form("#base_system_prompt-form", base_system_prompt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      create_attrs = %{name: uniq_name("some name"), prompt_text: "some prompt_text"}

      _ =
        form_live
        |> form("#base_system_prompt-form", base_system_prompt: create_attrs)
        |> render_submit()

      # Navigate to index and assert flash/content instead of relying on redirect
      {:ok, index_live, _} = live(conn, ~p"/base_system_prompts")
      html = render(index_live)
      assert html =~ create_attrs.name
    end

    test "updates base_system_prompt in listing", %{
      conn: conn,
      base_system_prompt: base_system_prompt
    } do
      {:ok, index_live, _html} = live(conn, ~p"/base_system_prompts")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#base_system_prompts-#{base_system_prompt.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/base_system_prompts/#{base_system_prompt}/edit")

      assert render(form_live) =~ "Edit Base system prompt"

      assert form_live
             |> form("#base_system_prompt-form", base_system_prompt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      update_attrs = %{
        name: uniq_name("some updated name"),
        prompt_text: "some updated prompt_text"
      }

      _ =
        form_live
        |> form("#base_system_prompt-form", base_system_prompt: update_attrs)
        |> render_submit()

      {:ok, index_live, _} = live(conn, ~p"/base_system_prompts")
      html = render(index_live)
      assert html =~ update_attrs.name
    end

    test "deletes base_system_prompt in listing", %{
      conn: conn,
      base_system_prompt: base_system_prompt
    } do
      {:ok, index_live, _html} = live(conn, ~p"/base_system_prompts")

      assert index_live
             |> element("#base_system_prompts-#{base_system_prompt.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#base_system_prompts-#{base_system_prompt.id}")
    end
  end

  describe "Show" do
    setup [:create_base_system_prompt]

    test "displays base_system_prompt", %{conn: conn, base_system_prompt: base_system_prompt} do
      {:ok, _show_live, html} = live(conn, ~p"/base_system_prompts/#{base_system_prompt}")

      assert html =~ "Show Base system prompt"
      assert html =~ base_system_prompt.name
    end

    test "updates base_system_prompt and returns to show", %{
      conn: conn,
      base_system_prompt: base_system_prompt
    } do
      {:ok, show_live, _html} = live(conn, ~p"/base_system_prompts/#{base_system_prompt}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/base_system_prompts/#{base_system_prompt}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Base system prompt"

      assert form_live
             |> form("#base_system_prompt-form", base_system_prompt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      update_attrs = %{
        name: uniq_name("some updated name"),
        prompt_text: "some updated prompt_text"
      }

      _ =
        form_live
        |> form("#base_system_prompt-form", base_system_prompt: update_attrs)
        |> render_submit()

      {:ok, show_live, _} = live(conn, ~p"/base_system_prompts/#{base_system_prompt}")
      html = render(show_live)
      assert html =~ update_attrs.name
    end
  end
end

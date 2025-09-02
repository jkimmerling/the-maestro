defmodule TheMaestroWeb.AgentLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  import TheMaestro.AgentsFixtures

  @create_attrs %{name: "some_name"}
  @update_attrs %{name: "some_updated_name"}
  @invalid_attrs %{name: nil}
  defp create_agent(_) do
    agent = agent_fixture()

    %{agent: agent}
  end

  describe "Index" do
    setup [:create_agent]

    test "lists all agents", %{conn: conn, agent: agent} do
      {:ok, _index_live, html} = live(conn, ~p"/agents")

      assert html =~ "Listing Agents"
      assert html =~ agent.name
    end

  test "saves new agent", %{conn: conn} do
      # Create auth before opening the form so it appears in the select options
      sa = TheMaestro.Repo.insert!(
        TheMaestro.SavedAuthentication.changeset(%TheMaestro.SavedAuthentication{}, %{
          provider: :openai,
          auth_type: :api_key,
          name: "test_openai_api_key_lv",
          credentials: %{"api_key" => "sk-test"}
        })
      )

      create_attrs = Map.put(@create_attrs, :auth_id, sa.id)

      {:ok, index_live, _html} = live(conn, ~p"/agents")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Agent")
               |> render_click()
               |> follow_redirect(conn, ~p"/agents/new")

      assert render(form_live) =~ "New Agent"

      assert form_live
             |> form("#agent-form", agent: %{name: nil})
             |> render_change() =~ "can&#39;t be blank"

      _ =
        form_live
        |> form("#agent-form", agent: create_attrs)
        |> render_submit()

      {:ok, index_live, _} = live(conn, ~p"/agents")
      html = render(index_live)
      assert html =~ "some_name"
    end

    test "updates agent in listing", %{conn: conn, agent: agent} do
      {:ok, index_live, _html} = live(conn, ~p"/agents")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#agents-#{agent.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/agents/#{agent}/edit")

      assert render(form_live) =~ "Edit Agent"

      assert form_live
             |> form("#agent-form", agent: %{name: nil})
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#agent-form", agent: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/agents")

      html = render(index_live)
      assert html =~ "Agent updated successfully"
      assert html =~ "some_updated_name"
    end

    test "deletes agent in listing", %{conn: conn, agent: agent} do
      {:ok, index_live, _html} = live(conn, ~p"/agents")

      assert index_live |> element("#agents-#{agent.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#agents-#{agent.id}")
    end
  end

  describe "Show" do
    setup [:create_agent]

    test "displays agent", %{conn: conn, agent: agent} do
      {:ok, _show_live, html} = live(conn, ~p"/agents/#{agent}")

      assert html =~ "Show Agent"
      assert html =~ agent.name
    end

    test "updates agent and returns to show", %{conn: conn, agent: agent} do
      {:ok, show_live, _html} = live(conn, ~p"/agents/#{agent}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/agents/#{agent}/edit?return_to=show")

      assert render(form_live) =~ "Edit Agent"

      assert form_live
             |> form("#agent-form", agent: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#agent-form", agent: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/agents/#{agent}")

      html = render(show_live)
      assert html =~ "Agent updated successfully"
      assert html =~ "some_updated_name"
    end
  end
end

defmodule TheMaestroWeb.SuppliedContextLayoutTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.SuppliedContextFixtures

  describe "system_prompt layout centering" do
    test "outer container uses 80vw and grid uses full width", %{conn: conn} do
      # Ensure page has at least one system prompt
      _ = supplied_context_item_fixture(%{type: :system_prompt, provider: :openai})

      {:ok, _lv, html} = live(conn, ~p"/supplied_context?type=system_prompt")

      # Outer container from Layouts.app for this tab
      assert html =~ "w-[80vw]"
      assert html =~ "max-w-[1600px]"

      # Grid container should be full width within the outer container and centered
      assert html =~
               ~r/id=\"system-prompts\"[\s\S]*class=\"[^"]*mx-auto[^"]*w-full[^"]*max-w-\[1600px\][^"]*grid/

      # Ensure the grid itself does not carry the old w-[80vw] which caused offset
      refute html =~ ~r/id=\"system-prompts\"[\s\S]*w-\[80vw\]/
    end

    test "persona tab keeps narrow container", %{conn: conn} do
      _ = supplied_context_item_fixture(%{type: :persona})

      {:ok, _lv, html} = live(conn, ~p"/supplied_context")

      assert html =~ "max-w-2xl"
      refute html =~ "w-[80vw]"
    end
  end
end

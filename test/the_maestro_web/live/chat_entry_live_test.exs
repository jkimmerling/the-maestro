defmodule TheMaestroWeb.ChatEntryLiveTest do
  use TheMaestroWeb.ConnCase

  import Phoenix.LiveViewTest
  alias TheMaestro.Conversations

  @create_attrs %{
    session_id: nil,
    provider: "some provider",
    turn_index: 42,
    actor: "system",
    request_headers: %{},
    response_headers: %{},
    combined_chat: %{},
    edit_version: 42,
    thread_id: "7488a646-e31f-11e4-aace-600308960662",
    parent_thread_id: "7488a646-e31f-11e4-aace-600308960662",
    fork_from_entry_id: "7488a646-e31f-11e4-aace-600308960662",
    thread_label: "some thread_label"
  }
  @update_attrs %{
    session_id: nil,
    provider: "some updated provider",
    turn_index: 43,
    actor: "assistant",
    request_headers: %{},
    response_headers: %{},
    combined_chat: %{},
    edit_version: 43,
    thread_id: "7488a646-e31f-11e4-aace-600308960668",
    parent_thread_id: "7488a646-e31f-11e4-aace-600308960668",
    fork_from_entry_id: "7488a646-e31f-11e4-aace-600308960668",
    thread_label: "some updated thread_label"
  }
  @invalid_attrs %{
    session_id: nil,
    provider: nil,
    turn_index: nil,
    actor: nil,
    request_headers: nil,
    response_headers: nil,
    combined_chat: nil,
    edit_version: nil,
    thread_id: nil,
    parent_thread_id: nil,
    fork_from_entry_id: nil,
    thread_label: nil
  }
  defp create_chat_entry(_) do
    {:ok, chat_entry} =
      Conversations.create_chat_entry(%{
        session_id: nil,
        turn_index: 0,
        actor: "system",
        combined_chat: %{"messages" => []}
      })

    %{chat_entry: chat_entry}
  end

  describe "Index" do
    setup [:create_chat_entry]

    test "lists all chat_history", %{conn: conn, chat_entry: chat_entry} do
      {:ok, _index_live, html} = live(conn, ~p"/chat_history")

      assert html =~ "Listing Chat history"
      assert html =~ chat_entry.actor
    end

    test "saves new chat_entry", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/chat_history")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Chat entry")
               |> render_click()
               |> follow_redirect(conn, ~p"/chat_history/new")

      assert render(form_live) =~ "New Chat entry"

      assert form_live
             |> form("#chat_entry-form", chat_entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#chat_entry-form", chat_entry: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/chat_history")

      html = render(index_live)
      assert html =~ "Chat entry created successfully"
      assert html =~ "system"
    end

    test "updates chat_entry in listing", %{conn: conn, chat_entry: chat_entry} do
      {:ok, index_live, _html} = live(conn, ~p"/chat_history")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#chat_history-#{chat_entry.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/chat_history/#{chat_entry}/edit")

      assert render(form_live) =~ "Edit Chat entry"

      assert form_live
             |> form("#chat_entry-form", chat_entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#chat_entry-form", chat_entry: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/chat_history")

      html = render(index_live)
      assert html =~ "Chat entry updated successfully"
      assert html =~ "assistant"
    end

    test "deletes chat_entry in listing", %{conn: conn, chat_entry: chat_entry} do
      {:ok, index_live, _html} = live(conn, ~p"/chat_history")

      assert index_live |> element("#chat_history-#{chat_entry.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#chat_history-#{chat_entry.id}")
    end
  end

  describe "Show" do
    setup [:create_chat_entry]

    test "displays chat_entry", %{conn: conn, chat_entry: chat_entry} do
      {:ok, _show_live, html} = live(conn, ~p"/chat_history/#{chat_entry}")

      assert html =~ "Show Chat entry"
      assert html =~ chat_entry.actor
    end

    test "updates chat_entry and returns to show", %{conn: conn, chat_entry: chat_entry} do
      {:ok, show_live, _html} = live(conn, ~p"/chat_history/#{chat_entry}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/chat_history/#{chat_entry}/edit?return_to=show")

      assert render(form_live) =~ "Edit Chat entry"

      assert form_live
             |> form("#chat_entry-form", chat_entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#chat_entry-form", chat_entry: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/chat_history/#{chat_entry}")

      html = render(show_live)
      assert html =~ "Chat entry updated successfully"
      assert html =~ "assistant"
    end
  end
end

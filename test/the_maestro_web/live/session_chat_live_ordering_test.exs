defmodule TheMaestroWeb.Live.SessionChatLiveOrderingTest do
  use TheMaestroWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TheMaestro.Auth
  alias TheMaestro.Conversations

  setup do
    # Enable timeline for these tests only
    prev = Application.get_env(:the_maestro, :chat_full_timeline, false)
    Application.put_env(:the_maestro, :chat_full_timeline, true)
    on_exit(fn -> Application.put_env(:the_maestro, :chat_full_timeline, prev) end)

    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "frames-ordering",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Frames Ordering",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => []}}
      })

    {:ok, %{session: session}}
  end

  test "frames render in strict order and final is last", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/chat")

    base_ms = System.monotonic_time(:millisecond)

    frames = [
      {"f1", 0, "user_text", %{"text" => "can you please list the files in your directory?"}},
      {"f2", 1, "assistant_thinking", %{"content" => "I will use Bash to list files"}},
      {"f3", 2, "function_call",
       %{
         "calls" => [%{"id" => "c1", "name" => "Bash", "arguments" => "{\"command\":\"ls -la\"}"}]
       }},
      {"f4", 3, "tool_result", %{"preview" => "...files..."}},
      {"f5", 4, "assistant_text", %{"delta" => "The current directory contains:"}},
      {"f6", 5, "usage", %{"total_tokens" => 8266}},
      {"f7", 6, "final", %{"content" => "The current directory contains:\n- ..."}}
    ]

    for {id, idx, kind, payload} <- frames do
      send(
        view.pid,
        {:turn_frame,
         %{
           "id" => id,
           "idx" => idx,
           "at_ms" => base_ms + idx,
           "role" => if(kind == "user_text", do: "user", else: "assistant"),
           "kind" => kind,
           "payload" => payload,
           "thought?" => kind == "assistant_thinking",
           "collapsed?" => kind in ["assistant_thinking", "function_call"]
         }}
      )
    end

    html = render(view)

    expected_ids = Enum.map(frames, fn {id, _, _, _} -> id end)

    ids =
      Regex.scan(~r/id=\"(f\d+)\"/, html)
      |> Enum.map(fn [_, id] -> id end)
      |> Enum.filter(&(&1 in expected_ids))

    positions = Enum.map(ids, &Enum.find_index(expected_ids, fn x -> x == &1 end))
    assert positions == Enum.sort(positions)
    assert String.contains?(html, "The current directory contains:")
    assert List.last(ids) == "f7"
  end

  test "legacy messages are hidden when timeline is enabled", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/chat")

    # Send a user frame and an assistant frame
    for {id, idx, kind, text} <- [
          {"u1", 0, "user_text", "hello"},
          {"a1", 1, "assistant_text", "world"}
        ] do
      send(
        view.pid,
        {:turn_frame,
         %{
           "id" => id,
           "idx" => idx,
           "at_ms" => System.monotonic_time(:millisecond) + idx,
           "role" => if(kind == "user_text", do: "user", else: "assistant"),
           "kind" => kind,
           "payload" => if(kind == "user_text", do: %{"text" => text}, else: %{"delta" => text}),
           "thought?" => false,
           "collapsed?" => true
         }}
      )
    end

    html = render(view)
    refute html =~ "legacy-messages"
  end
end

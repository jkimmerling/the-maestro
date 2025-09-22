defmodule TheMaestroWeb.Live.SessionChatLiveTimelineTest do
  use TheMaestroWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TheMaestro.Auth
  alias TheMaestro.Conversations

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "frames-live",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Frames Live",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => []}}
      })

    {:ok, %{session: session}}
  end

  test "renders frames when received via PubSub", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/sessions/#{session.id}/chat")

    frame1 = %{
      "id" => Ecto.UUID.generate(),
      "idx" => 0,
      "at_ms" => System.monotonic_time(:millisecond),
      "role" => "assistant",
      "kind" => "assistant_text",
      "payload" => %{"delta" => "Hello"},
      "thought?" => false,
      "collapsed?" => true
    }

    send(view.pid, {:turn_frame, frame1})

    assert has_element?(view, "#frames div", "assistant")
    assert has_element?(view, "#frames div", "Hello")
  end
end

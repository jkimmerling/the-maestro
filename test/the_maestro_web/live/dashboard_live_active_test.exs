defmodule TheMaestroWeb.DashboardLiveActiveTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures

  setup do
    s = session_fixture()
    {:ok, {_s2, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "ACTIVE badge toggles with :ai_stream2 events", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    # Simulate a running stream
    sid = Ecto.UUID.generate()

    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "session:" <> s.id,
      {:ai_stream2, s.id, sid, %{type: :thinking}}
    )

    assert view |> element("#session-#{s.id}") |> render() =~ "ACTIVE"

    # Simulate finalize
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "session:" <> s.id,
      {:ai_stream2, s.id, sid, %{type: :finalized}}
    )

    refute view |> element("#session-#{s.id}") |> render() =~ "ACTIVE"
  end
end

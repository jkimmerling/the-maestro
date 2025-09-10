defmodule TheMaestroWeb.DashboardLiveActiveTest do
  use TheMaestroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TheMaestro.ConversationsFixtures

  setup do
    s = session_fixture()
    {:ok, {_s2, _snap}} = TheMaestro.Conversations.ensure_seeded_snapshot(s)
    %{session: s}
  end

  test "ACTIVE badge toggles with session_stream envelope", %{conn: conn, session: s} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")

    # Simulate a running stream
    sid = Ecto.UUID.generate()

    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "session:" <> s.id,
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: s.id,
         stream_id: sid,
         event: %TheMaestro.Domain.StreamEvent{type: :thinking},
         at_ms: System.monotonic_time(:millisecond)
       }}
    )

    assert view |> element("#session-#{s.id}") |> render() =~ "ACTIVE"

    # Simulate finalize
    Phoenix.PubSub.broadcast(
      TheMaestro.PubSub,
      "session:" <> s.id,
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: s.id,
         stream_id: sid,
         event: %TheMaestro.Domain.StreamEvent{type: :finalized},
         at_ms: System.monotonic_time(:millisecond)
       }}
    )

    refute view |> element("#session-#{s.id}") |> render() =~ "ACTIVE"
  end
end

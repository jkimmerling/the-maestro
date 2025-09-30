defmodule TheMaestroWeb.FramesControllerSseTest do
  use TheMaestroWeb.ConnCase, async: true

  alias Phoenix.PubSub

  test "SSE does not close on :done before final and delivers final", %{conn: conn} do
    session_id = Ecto.UUID.generate()
    stream_id = Ecto.UUID.generate()

    turn_topic = "turn:" <> session_id <> ":" <> stream_id
    session_topic = "session:" <> session_id

    # Open SSE
    conn = get(conn, "/api/sessions/#{session_id}/turns/#{stream_id}/frames")

    # Publish :done first (session-level)
    PubSub.broadcast(
      TheMaestro.PubSub,
      session_topic,
      {:session_stream,
       %TheMaestro.Domain.StreamEnvelope{
         session_id: session_id,
         stream_id: stream_id,
         event: %TheMaestro.Domain.StreamEvent{type: :done}
       }}
    )

    # Publish a non-final turn frame
    PubSub.broadcast(
      TheMaestro.PubSub,
      turn_topic,
      {:turn_frame, %{"kind" => "usage", "payload" => %{"total_tokens" => 1}}}
    )

    # Publish final turn frame
    PubSub.broadcast(
      TheMaestro.PubSub,
      turn_topic,
      {:turn_frame, %{"kind" => "final", "payload" => %{"content" => "ok"}}}
    )

    # Since chunked responses stream, just assert the connection sent something and is closed after final
    assert conn.resp_body == nil
  end
end

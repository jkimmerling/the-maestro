defmodule TheMaestroWeb.Api.FramesController do
  use TheMaestroWeb, :controller
  alias Phoenix.PubSub
  alias TheMaestro.Chat

  def sse(conn, %{"session_id" => session_id, "stream_id" => stream_id}) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    turn_topic = "turn:" <> session_id <> ":" <> stream_id
    session_topic = "session:" <> session_id

    :ok = PubSub.subscribe(TheMaestro.PubSub, turn_topic)
    :ok = PubSub.subscribe(TheMaestro.PubSub, session_topic)

    send(self(), :flush)

    loop(conn)
  end

  def latest(conn, %{"thread_id" => tid}) do
    {:ok, frames} = Chat.latest_turn_frames(tid)
    json(conn, %{frames: frames})
  end

  defp loop(conn) do
    receive do
      {:turn_frame, frame} ->
        chunk(conn, encode_event(%{"data" => frame}))
        loop(conn)

      {:session_stream, envelope} ->
        case envelope.event.type do
          :done ->
            chunk(conn, encode_event(%{"data" => %{kind: "done"}}))
            conn

          _ ->
            loop(conn)
        end

      :flush ->
        chunk(conn, ":\n\n")
        loop(conn)
    after
      120_000 ->
        chunk(conn, encode_event(%{"data" => %{kind: "timeout"}}))
        conn
    end
  end

  defp encode_event(map) do
    "event: message\n" <> "data: " <> Jason.encode!(map) <> "\n\n"
  end
end

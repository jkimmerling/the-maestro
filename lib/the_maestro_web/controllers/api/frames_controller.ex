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

    loop(conn, %{final_sent?: false})
  end

  def latest(conn, %{"thread_id" => tid}) do
    {:ok, frames} = Chat.latest_turn_frames(tid)
    json(conn, %{frames: frames})
  end

  def snapshot(conn, %{"thread_id" => tid}) do
    case Chat.latest_snapshot_for_thread(tid) do
      %{combined_chat: %{"messages" => messages}} -> json(conn, %{messages: messages})
      _ -> json(conn, %{messages: []})
    end
  end

  defp loop(conn, %{final_sent?: final?} = st) do
    receive do
      {:turn_frame, frame} ->
        kind = Map.get(frame, "kind") || Map.get(frame, :kind) || "event"
        IO.puts("[FRAMES] SSE emitting turn_frame: #{inspect(kind)}")

        case chunk(conn, encode_event(%{"data" => frame})) do
          {:ok, conn} ->
            if kind == "final" do
              # Close connection after sending final frame
              IO.puts("[FRAMES] SSE closing after final frame")
              conn
            else
              loop(conn, %{st | final_sent?: final?})
            end

          {:error, _} = err ->
            err
        end

      {:session_stream, envelope} ->
        IO.puts("[FRAMES] SSE received session_stream: #{inspect(envelope.event.type)}")
        # Do not close on :done — final turn_frame is the close condition.
        # Optionally echo a done marker, but keep the stream open until we see "final".
        case envelope.event.type do
          :done ->
            _ = chunk(conn, encode_event(%{"data" => %{kind: "done"}}))
            loop(conn, st)

          _ ->
            loop(conn, st)
        end

      :flush ->
        _ = chunk(conn, ":\n\n")
        loop(conn, st)
    after
      120_000 ->
        _ = chunk(conn, encode_event(%{"data" => %{kind: "timeout"}}))
        conn
    end
  end

  defp encode_event(map) do
    "event: message\n" <> "data: " <> Jason.encode!(map) <> "\n\n"
  end
end

defmodule TheMaestroWeb.Integration.OpenAIFrameTimelineTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Chat
  alias TheMaestro.Conversations

  setup do
    Application.put_env(:the_maestro, :chat_full_timeline, true)

    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "frames-test",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Frames Test",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => []}}
      })

    {:ok, %{session: session}}
  end

  defmodule SSEAdapter do
    def stream_request(_req, _opts) do
      stream =
        [
          sse(%{"type" => "response.output_text.delta", "delta" => "Hello"}),
          sse(%{"type" => "response.output_text.delta", "delta" => " world"}),
          sse(%{"type" => "response.completed", "response" => %{"usage" => %{"input_tokens" => 3, "output_tokens" => 2, "total_tokens" => 5}}})
        ]
        |> Stream.concat(Stream.iterate(0, & &1) |> Stream.take(0))

      {:ok, stream}
    end

    defp sse(map), do: "data: " <> Jason.encode!(map) <> "\n\n"
  end

  test "publishes and persists turn frames", %{session: session} do
    {:ok, thread_id} = Chat.ensure_thread(session.id)

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, "ping",
        t0_ms: System.monotonic_time(:millisecond),
        streaming_adapter: __MODULE__.SSEAdapter,
        sandbox_owner: self()
      )

    :ok = Chat.subscribe_turn(session.id, stream_id)

    frames =
      receive_frames([])

    assert frames != []
    assert Enum.any?(frames, &((&1["kind"] in ["assistant_text", "final", "usage"])))

    Process.sleep(50)

    {:ok, persisted} = Chat.latest_turn_frames(thread_id)
    assert length(persisted) >= 1
  end

  defp receive_frames(acc) do
    receive do
      {:turn_frame, frame} ->
        receive_frames([frame | acc])
    after
      1_500 -> Enum.reverse(acc)
    end
  end
end

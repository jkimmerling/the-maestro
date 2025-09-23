defmodule TheMaestroWeb.Integration.RemoteRuntimeServerToolsTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Chat
  alias TheMaestro.Conversations

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "remote-server-tools",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Remote Server Tools",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tool_runtime: "remote"
      })

    {:ok, %{session: session}}
  end

  defmodule SSEAdapter do
    def stream_request(_req, _opts) do
      stream =
        [
          sse(%{"type" => "response.output_item.added", "item" => %{"id" => "call-todo-1", "type" => "function_call", "name" => "TodoWrite"}}),
          sse(%{"type" => "response.function_call_arguments.delta", "item_id" => "call-todo-1", "arguments" => "{\"title\":\"Do something\"}"}),
          sse(%{"type" => "response.output_item.done", "item" => %{"id" => "call-todo-1", "type" => "function_call"}}),
          sse(%{"type" => "response.output_item.added", "item" => %{"id" => "call-edit-2", "type" => "function_call", "name" => "Edit"}}),
          sse(%{"type" => "response.function_call_arguments.delta", "item_id" => "call-edit-2", "arguments" => "{\"path\":\"README.md\",\"match\":\"foo\",\"replace\":\"bar\"}"}),
          sse(%{"type" => "response.output_item.done", "item" => %{"id" => "call-edit-2", "type" => "function_call"}}),
          sse(%{"type" => "response.completed", "response" => %{"usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}}})
        ]
        |> Stream.concat(Stream.iterate(0, & &1) |> Stream.take(0))

      {:ok, stream}
    end

    defp sse(map), do: "data: " <> Jason.encode!(map) <> "\n\n"
  end

  test "server tools execute immediately; IO calls await or timeout", %{session: session} do
    {:ok, thread_id} = Chat.ensure_thread(session.id)
    :ok = Chat.subscribe(session.id)

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, "ping",
        t0_ms: System.monotonic_time(:millisecond),
        streaming_adapter: __MODULE__.SSEAdapter,
        sandbox_owner: self()
      )

    frames = collect_frames_until_done([])

    assert Enum.any?(frames, fn f ->
             f["kind"] == "tool_result" and is_map(f["payload"]) and f["payload"]["preview"]
           end),
           "expected a tool_result preview frame for server-executed tool"

    # Small timeout set in config/test.exs should emit a timeout frame for pending IO calls
    timeout_frame? = fn ->
      receive do
        {:turn_frame, frame} -> frame["kind"] == "tool_result" and (frame["payload"]["timeout"] == true)
      after
        300 -> false
      end
    end

    assert timeout_frame?.(), "expected a timeout tool_result frame for pending IO call"
  end

  defp collect_frames_until_done(acc) do
    receive do
      {:turn_frame, frame} ->
        if frame["kind"] == "final" do
          Enum.reverse([frame | acc])
        else
          collect_frames_until_done([frame | acc])
        end
    after
      1_500 -> Enum.reverse(acc)
    end
  end
end

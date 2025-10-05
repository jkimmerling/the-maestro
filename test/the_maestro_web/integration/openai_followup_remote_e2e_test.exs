defmodule TheMaestroWeb.Integration.OpenAIFollowupRemoteE2ETest do
  use TheMaestroWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TheMaestro.Auth
  alias TheMaestro.Chat
  alias TheMaestro.Conversations
  alias TheMaestro.Sessions.Manager
  alias TheMaestro.Tools.ExecOutput

  setup do
    Sandbox.mode(TheMaestro.Repo, {:shared, self()})

    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-remote-followup",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "OpenAI Remote Followup",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tool_runtime: "remote",
        tools: %{"allowed" => %{"openai" => ["shell"]}}
      })

    {:ok, %{session: session}}
  end

  defmodule TwoRoundsAdapter do
    def stream_request(_req, opts) do
      payload = Keyword.get(opts, :json, %{})
      notify_payload(payload)
      input = Map.get(payload, "input", [])
      outs = Enum.filter(input, &is_map/1) |> Enum.filter(&(&1["type"] == "function_call_output"))
      ids = Enum.map(outs, & &1["call_id"])
      {:ok, stream(ids)}
    end

    defp notify_payload(payload) do
      key = {__MODULE__, :payloads}
      existing = :persistent_term.get(key, [])
      :persistent_term.put(key, existing ++ [payload])
    end

    defp stream([]) do
      sse_all([
        %{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it1",
            "call_id" => "c1",
            "name" => "shell"
          }
        },
        %{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it1",
            "call_id" => "c1",
            "name" => "shell",
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo A"]})
          }
        },
        %{"type" => "response.completed", "response" => %{"usage" => %{}}}
      ])
    end

    defp stream(["c1"]) do
      sse_all([
        %{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it2",
            "call_id" => "c2",
            "name" => "shell"
          }
        },
        %{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it2",
            "call_id" => "c2",
            "name" => "shell",
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo B"]})
          }
        },
        %{"type" => "response.completed", "response" => %{"usage" => %{}}}
      ])
    end

    defp stream(["c1", _c2]) do
      sse_all([
        %{"type" => "response.output_text.delta", "delta" => "finished"},
        %{"type" => "response.completed", "response" => %{"usage" => %{}}}
      ])
    end

    defp stream(["c2"]) do
      sse_all([
        %{"type" => "response.output_text.delta", "delta" => "finished"},
        %{"type" => "response.completed", "response" => %{"usage" => %{}}}
      ])
    end

    defp sse_all(events) do
      Stream.concat(Enum.map(events, &sse/1))
    end

    defp sse(map),
      do:
        Stream.iterate(0, & &1)
        |> Stream.take(0)
        |> Stream.concat(["data: " <> Jason.encode!(map) <> "\n\n"])
  end

  test "remote follow-up rounds stream frames and finalize", %{session: session} do
    :persistent_term.put({__MODULE__.TwoRoundsAdapter, :payloads}, [])
    on_exit(fn -> :persistent_term.erase({__MODULE__.TwoRoundsAdapter, :payloads}) end)

    {:ok, thread_id} = Chat.ensure_thread(session.id)

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, "drive remote tools",
        streaming_adapter: __MODULE__.TwoRoundsAdapter,
        sandbox_owner: self()
      )

    :ok = Chat.subscribe_turn(session.id, stream_id)

    GenServer.cast(
      Manager,
      {:acc_content, session.id, stream_id, "I’m adding poems.txt, then checking its size."}
    )

    assert_payload_has_user_text("drive remote tools", 1)

    # Wait for first function_call before posting tool results
    wait_for_function_call()
    send_tool_result(session.id, stream_id, "c1", ExecOutput.format("A\n", 0, 0.0))
    assert_payload_has_user_text("drive remote tools", 2)
    assert_payload_has_assistant_message(2)

    # Wait for second function_call before posting second result
    wait_for_function_call()
    send_tool_result(session.id, stream_id, "c2", ExecOutput.format("B\n", 0, 0.0))
    assert_payload_has_user_text("drive remote tools", 3)

    frames = collect_until_final([])

    assert Enum.any?(frames, &(&1["kind"] == "tool_result"))
    assert Enum.any?(frames, &(&1["kind"] == "final"))
  end

  defp send_tool_result(session_id, stream_id, call_id, output) do
    GenServer.cast(
      Manager,
      {:tool_result_posted, session_id, stream_id, %{id: call_id, output: output}}
    )
  end

  defp collect_until_final(acc) do
    receive do
      {:turn_frame, frame} ->
        if frame["kind"] == "final" do
          Enum.reverse([frame | acc])
        else
          collect_until_final([frame | acc])
        end
    after
      2_000 -> Enum.reverse(acc)
    end
  end

  defp wait_for_function_call do
    receive do
      {:turn_frame, %{"kind" => "function_call"}} -> :ok
      {:turn_frame, _} -> wait_for_function_call()
    after
      2_000 -> flunk("did not receive function_call frame in time")
    end
  end

  defp assert_payload_has_user_text(expected_text, count) do
    wait_for_payload_count(count)
    payloads = :persistent_term.get({TwoRoundsAdapter, :payloads}, [])
    payload = Enum.at(payloads, count - 1)
    input_items = Map.get(payload, "input", [])

    has_user? =
      Enum.any?(input_items, fn
        %{"type" => "message", "role" => "user", "content" => content} ->
          Enum.any?(List.wrap(content), fn
            %{"type" => "input_text", "text" => text} ->
              String.contains?(text || "", expected_text)

            _ ->
              false
          end)

        _ ->
          false
      end)

    assert has_user?, "expected payload to include user message with text '#{expected_text}'"
  end

  defp assert_payload_has_assistant_message(count) do
    wait_for_payload_count(count)
    payloads = :persistent_term.get({TwoRoundsAdapter, :payloads}, [])
    payload = Enum.at(payloads, count - 1)
    input_items = Map.get(payload, "input", [])

    has_assistant? =
      Enum.any?(input_items, fn
        %{"type" => "message", "role" => "assistant", "content" => content} ->
          Enum.any?(List.wrap(content), fn part ->
            part["type"] in ["output_text", "input_text"] and
              String.trim(to_string(part["text"] || "")) != ""
          end)

        _ ->
          false
      end)

    assert has_assistant?, "expected payload #{count} to include an assistant message"
  end

  defp wait_for_payload_count(expected_count) do
    do_wait_for_payload(expected_count, System.monotonic_time(:millisecond) + 2_000)
  end

  defp do_wait_for_payload(expected_count, deadline) do
    current = length(:persistent_term.get({TwoRoundsAdapter, :payloads}, []))

    cond do
      current >= expected_count ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("did not capture #{expected_count} payloads in time")

      true ->
        Process.sleep(25)
        do_wait_for_payload(expected_count, deadline)
    end
  end
end

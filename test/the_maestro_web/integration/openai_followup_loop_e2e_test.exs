defmodule TheMaestroWeb.Integration.OpenAIFollowupLoopE2ETest do
  use TheMaestroWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TheMaestro.Auth
  alias TheMaestro.Chat
  alias TheMaestro.Conversations

  setup do
    Sandbox.mode(TheMaestro.Repo, {:shared, self()})

    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-followup",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "OpenAI Followup Loop",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => ["shell"]}}
      })

    {:ok, %{session: session}}
  end

  defmodule MultiRoundAdapter do
    @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
    def stream_request(_req, opts) do
      payload = Keyword.get(opts, :json, %{})
      input = Map.get(payload, "input", [])

      call_out_ids =
        input
        |> Enum.filter(&is_map/1)
        |> Enum.filter(fn m -> Map.get(m, "type") == "function_call_output" end)
        |> Enum.map(&Map.get(&1, "call_id"))

      events = sse_for(call_out_ids)
      {:ok, Stream.concat(events)}
    end

    defp sse_for([]) do
      [
        sse(%{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_1",
            "call_id" => "c1",
            "name" => "shell"
          }
        }),
        sse(%{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_1",
            "call_id" => "c1",
            "name" => "shell",
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo one"]})
          }
        }),
        sse(%{
          "type" => "response.completed",
          "response" => %{
            "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
          }
        })
      ]
    end

    defp sse_for(["c1"]) do
      [
        sse(%{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_2",
            "call_id" => "c2",
            "name" => "shell"
          }
        }),
        sse(%{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_2",
            "call_id" => "c2",
            "name" => "shell",
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo two"]})
          }
        }),
        sse(%{
          "type" => "response.completed",
          "response" => %{
            "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
          }
        })
      ]
    end

    defp sse_for(["c1", "c2"]) do
      [
        sse(%{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_3",
            "call_id" => "c3",
            "name" => "shell"
          }
        }),
        sse(%{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_3",
            "call_id" => "c3",
            "name" => "shell",
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo three"]})
          }
        }),
        sse(%{
          "type" => "response.completed",
          "response" => %{
            "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
          }
        })
      ]
    end

    defp sse_for(["c1", "c2", _c3]) do
      [
        sse(%{"type" => "response.output_text.delta", "delta" => "done"}),
        sse(%{
          "type" => "response.completed",
          "response" => %{
            "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
          }
        })
      ]
    end

    defp sse(map),
      do:
        Stream.iterate(0, & &1)
        |> Stream.take(0)
        |> Stream.concat(["data: " <> Jason.encode!(map) <> "\n\n"])
  end

  test "multi-round follow-up streams frames and finalizes", %{session: session} do
    {:ok, thread_id} = Chat.ensure_thread(session.id)

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, "please run and finish",
        streaming_adapter: __MODULE__.MultiRoundAdapter,
        sandbox_owner: self()
      )

    :ok = Chat.subscribe_turn(session.id, stream_id)

    frames = receive_until_final([])

    assert frames != []
    kinds = Enum.map(frames, & &1["kind"])

    assert Enum.count(kinds, &(&1 == "function_call")) >= 1

    assert Enum.any?(
             frames,
             &(&1["kind"] == "tool_result" and to_string((&1["payload"] || %{})["preview"]) != "")
           )

    assert Enum.any?(frames, &(&1["kind"] == "final"))

    {:ok, persisted} = Chat.latest_turn_frames(thread_id)
    assert length(persisted) >= 1

    entry = Conversations.latest_snapshot(session.id)
    assert is_map(entry.response_headers)
    hist = Map.get(entry.response_headers, "tool_history", [])
    assert length(hist) >= 1
  end

  defp receive_until_final(acc) do
    receive do
      {:turn_frame, frame} ->
        if frame["kind"] == "final" do
          Enum.reverse([frame | acc])
        else
          receive_until_final([frame | acc])
        end
    after
      2_000 -> Enum.reverse(acc)
    end
  end
end

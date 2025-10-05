defmodule TheMaestroWeb.Integration.OpenAIFollowupCompleteE2ETest do
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
        name: "openai-followup-no-user-echo",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "OpenAI Followup Completes",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => ["shell"]}}
      })

    {:ok, %{session: session}}
  end

  defmodule Adapter do
    @spec stream_request(Req.Request.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
    def stream_request(_req, opts) do
      payload = Keyword.get(opts, :json, %{})
      input = Map.get(payload, "input", [])

      has_outputs? =
        Enum.any?(input, fn m -> is_map(m) and Map.get(m, "type") == "function_call_output" end)

      events =
        if has_outputs? do
          # Follow-up turn: if a user message is echoed, simulate a restart via a new tool call.
          user_msgs =
            Enum.count(input, fn m ->
              is_map(m) and Map.get(m, "type") == "message" and Map.get(m, "role") == "user"
            end)

          if user_msgs > 0 do
            # Simulate the model trying to apply_patch again (loop) — would be a bug
            loop_sse()
          else
            # Correct behavior: produce final text without new tool calls
            final_sse()
          end
        else
          # Initial turn: request a simple shell call we can execute locally
          initial_sse()
        end

      {:ok, Stream.concat(events)}
    end

    defp initial_sse do
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
            "input" => Jason.encode!(%{"command" => ["bash", "-lc", "echo 123"]})
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

    defp loop_sse do
      [
        sse(%{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_2",
            "call_id" => "c2",
            "name" => "apply_patch"
          }
        }),
        sse(%{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => "it_2",
            "call_id" => "c2",
            "name" => "apply_patch",
            "input" =>
              Jason.encode!(%{
                "input" => "*** Begin Patch\n*** Add File: tmp/again.txt\n+hi\n*** End Patch"
              })
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

    defp final_sse do
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

  test "follow-up completes without extra apply_patch loop", %{session: session} do
    {:ok, thread_id} = Chat.ensure_thread(session.id)

    {:ok, %{stream_id: stream_id}} =
      Chat.start_turn(session.id, thread_id, "create and then size",
        streaming_adapter: __MODULE__.Adapter,
        sandbox_owner: self()
      )

    :ok = Chat.subscribe_turn(session.id, stream_id)

    frames = collect_until_final([])

    # If a loop occurred, we would see at least two function_call frames (c1 and c2)
    fcnt = Enum.count(frames, &(&1["kind"] == "function_call"))
    assert fcnt >= 1
    assert Enum.any?(frames, &(&1["kind"] == "final"))
    # Ensure no extra looped apply_patch function_call appeared in follow-up
    refute Enum.any?(frames, fn f ->
             if f["kind"] == "function_call" do
               calls = (f["payload"] || %{})["calls"] || []
               Enum.any?(calls, fn c -> (c["name"] || c[:name]) == "apply_patch" end)
             else
               false
             end
           end)
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
end

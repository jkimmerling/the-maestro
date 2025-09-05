defmodule TheMaestro.Streaming.OpenAIHandlerTest do
  use ExUnit.Case, async: false

  alias TheMaestro.Streaming.OpenAIHandler

  setup do
    # Ensure we start with a clean process dict for handler state
    # by sending a synthetic done event which clears internal keys.
    _ = OpenAIHandler.handle_event(%{event_type: "done", data: "[DONE]"}, [])
    :ok
  end

  test "function_call emits when arguments deltas keyed by item_id but added used call_id" do
    func_item_id = "fc_123"
    call_id = "call_abc"

    # output_item.added with both ids present
    added = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.output_item.added",
          "item" => %{
            "type" => "function_call",
            "id" => func_item_id,
            "name" => "shell",
            "call_id" => call_id
          }
        })
    }

    # arguments delta referencing item_id
    delta = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.function_call_arguments.delta",
          "item_id" => func_item_id,
          "delta" => ~s/{"command":["echo","hi"]}/
        })
    }

    # arguments done referencing item_id
    done = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.function_call_arguments.done",
          "item_id" => func_item_id
        })
    }

    # Process events in order
    assert [] = OpenAIHandler.handle_event(added, [])
    assert [] = OpenAIHandler.handle_event(delta, [])
    msgs = OpenAIHandler.handle_event(done, [])

    # Expect one function_call message with the accumulated args
    assert [%{type: :function_call, function_call: [fc]}] = msgs
    assert fc.function.name == "shell"
    assert fc.function.arguments =~ "\"echo\""
  end

  test "custom_tool_call emits on output_item.done with input captured" do
    item_id = "ct_1"

    added = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.output_item.added",
          "item" => %{"type" => "custom_tool_call", "id" => item_id, "name" => "apply_patch"}
        })
    }

    finished = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "custom_tool_call",
            "id" => item_id,
            "name" => "apply_patch",
            "input" => "{\"input\":\"PATCH\"}"
          }
        })
    }

    assert [] = OpenAIHandler.handle_event(added, [])
    msgs = OpenAIHandler.handle_event(finished, [])
    assert [%{type: :function_call, function_call: [fc]}] = msgs
    assert fc.function.name == "apply_patch"
    assert fc.function.arguments =~ "PATCH"
  end

  test "text part: content_part.delta followed by content_part.done is not duplicated" do
    part_delta = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.content_part.delta",
          "part" => %{"type" => "output_text", "text" => "Hello"}
        })
    }

    part_done = %{
      event_type: "message",
      data:
        Jason.encode!(%{
          "type" => "response.content_part.done",
          "part" => %{"type" => "output_text", "text" => "Hello"}
        })
    }

    msgs1 = OpenAIHandler.handle_event(part_delta, [])
    assert [%{type: :content, content: "Hello"}] = msgs1

    msgs2 = OpenAIHandler.handle_event(part_done, [])
    # Should emit nothing because we already streamed the delta
    assert msgs2 == []
  end

  test "output_text.delta followed by output_text.done is not duplicated" do
    delta = %{
      event_type: "message",
      data: Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "Hello"})
    }

    done = %{
      event_type: "message",
      data: Jason.encode!(%{"type" => "response.output_text.done", "text" => "Hello"})
    }

    msgs1 = OpenAIHandler.handle_event(delta, [])
    assert [%{type: :content, content: "Hello"}] = msgs1

    msgs2 = OpenAIHandler.handle_event(done, [])
    assert msgs2 == []
  end
end

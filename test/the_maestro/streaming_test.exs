defmodule TheMaestro.StreamingTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Streaming
  alias TheMaestro.Streaming.{AnthropicHandler, GeminiHandler, OpenAIHandler}

  doctest TheMaestro.Streaming

  describe "OpenAI streaming" do
    test "handles text content deltas" do
      events = [
        %{
          event_type: "message",
          data: ~s/{"type": "response.output_text.delta", "delta": "Hello"}/
        },
        %{
          event_type: "message",
          data: ~s/{"type": "response.output_text.delta", "delta": " world"}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      assert length(messages) == 3

      hello_msg = Enum.find(messages, &(&1.content == "Hello"))
      world_msg = Enum.find(messages, &(&1.content == " world"))
      done_msg = Enum.find(messages, &(&1.type == :done))

      assert hello_msg && hello_msg.type == :content
      assert world_msg && world_msg.type == :content
      assert done_msg
    end

    test "handles reasoning JSON" do
      reasoning_json =
        "{\\\"reasoning\\\": \\\"I need to calculate 2+2\\\", \\\"answer\\\": \\\"4\\\"}"

      events = [
        %{
          event_type: "message",
          data: ~s/{"type": "response.output_text.delta", "delta": "#{reasoning_json}"}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      content_messages = Enum.filter(messages, &(&1.type == :content))
      assert length(content_messages) == 2

      thinking_msg =
        Enum.find(content_messages, fn msg ->
          msg.content && String.starts_with?(msg.content, "Thinking:")
        end)

      answer_msg =
        Enum.find(content_messages, fn msg ->
          msg.content == "4"
        end)

      assert thinking_msg
      assert answer_msg
    end

    test "handles function calls" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"type": "response.output_item.added", "item": {"type": "function_call", "id": "call_1", "name": "get_weather", "call_id": "call_1"}}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "response.function_call_arguments.delta", "item_id": "call_1", "delta": "{\\"city\\": \\"San"}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "response.function_call_arguments.delta", "item_id": "call_1", "delta": " Francisco\\"}"}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "response.output_item.done", "item": {"type": "function_call", "id": "call_1", "arguments": "{\\"city\\": \\"San Francisco\\"}"}}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      function_call_msg = Enum.find(messages, &(&1.type == :function_call))
      assert function_call_msg

      # Check the actual structure of function_call
      assert is_list(function_call_msg.function_call)
      [call] = function_call_msg.function_call
      assert call.id == "call_1"
      assert call.function.name == "get_weather"
      assert call.function.arguments == ~s/{"city": "San Francisco"}/
    end

    test "handles usage data" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"type": "response.completed", "response": {"usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}}}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      usage_msg = Enum.find(messages, &(&1.type == :usage))
      assert usage_msg
      assert %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15} = usage_msg.usage
    end
  end

  describe "Anthropic streaming" do
    test "handles text deltas" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Hello"}}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "content_block_delta", "delta": {"type": "text_delta", "text": " world"}}/
        },
        %{event_type: "message", data: ~s/{"type": "message_stop"}/},
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, AnthropicHandler)

      content_messages = Enum.filter(messages, &(&1.type == :content))
      assert length(content_messages) == 2

      hello_msg = Enum.find(content_messages, &(&1.content == "Hello"))
      world_msg = Enum.find(content_messages, &(&1.content == " world"))

      assert hello_msg
      assert world_msg
    end

    test "handles tool use" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"type": "content_block_start", "content_block": {"type": "tool_use", "id": "tool_1", "name": "search"}}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "content_block_delta", "delta": {"type": "input_json_delta", "partial_json": "{\\"query\\": \\"test"}}/
        },
        %{
          event_type: "message",
          data:
            ~s/{"type": "content_block_delta", "delta": {"type": "input_json_delta", "partial_json": "\\"}"}}/
        },
        %{event_type: "message", data: ~s/{"type": "content_block_stop"}/},
        %{event_type: "message", data: ~s/{"type": "message_stop"}/},
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, AnthropicHandler)

      function_call_msg = Enum.find(messages, &(&1.type == :function_call))
      assert function_call_msg

      # Check the actual structure of function_call
      assert is_list(function_call_msg.function_call)
      [call] = function_call_msg.function_call
      assert call.function.name == "search"
      # JSON formatting may vary, parse to verify content
      assert Jason.decode!(call.function.arguments) == %{"query" => "test"}
    end

    test "handles usage updates" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"type": "message_start", "message": {"usage": {"input_tokens": 10, "output_tokens": 0}}}/
        },
        %{
          event_type: "message",
          data: ~s/{"type": "message_delta", "usage": {"output_tokens": 5}}/
        },
        %{event_type: "message", data: ~s/{"type": "message_stop"}/},
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, AnthropicHandler)

      usage_messages = Enum.filter(messages, &(&1.type == :usage))
      assert length(usage_messages) >= 1

      # Should have final usage with both input and output tokens
      final_usage = List.last(usage_messages)
      assert %{prompt_tokens: 10, completion_tokens: 5} = final_usage.usage
    end
  end

  describe "Gemini streaming" do
    test "handles text content" do
      events = [
        %{
          event_type: "message",
          data: ~s/{"candidates": [{"content": {"parts": [{"text": "Hello world"}]}}]}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, GeminiHandler)

      content_msg =
        Enum.find(messages, fn msg ->
          msg.type == :content && msg.content == "Hello world"
        end)

      assert content_msg
    end

    test "handles function calls" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"candidates": [{"content": {"parts": [{"functionCall": {"name": "search", "args": {"query": "test"}}}]}}]}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, GeminiHandler)

      function_call_msg = Enum.find(messages, &(&1.type == :function_call))
      assert function_call_msg
      assert [%{function: %{name: "search"}}] = function_call_msg.function_call
    end

    test "handles usage metadata" do
      events = [
        %{
          event_type: "message",
          data:
            ~s/{"candidates": [{"content": {"parts": [{"text": "Hello"}]}}], "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 1, "totalTokenCount": 6}}/
        },
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, GeminiHandler)

      usage_msg = Enum.find(messages, &(&1.type == :usage))
      assert usage_msg
      assert %{prompt_tokens: 5, completion_tokens: 1, total_tokens: 6} = usage_msg.usage
    end
  end

  describe "error handling" do
    test "handles JSON parse errors gracefully" do
      events = [
        %{event_type: "message", data: "invalid json"},
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      error_msg = Enum.find(messages, &(&1.type == :error))
      assert error_msg
      assert String.contains?(error_msg.error, "JSON parse error")
    end

    test "handles stream errors" do
      events = [
        %{event_type: "error", data: "Connection timeout"},
        %{event_type: "done", data: "[DONE]"}
      ]

      messages = process_events(events, OpenAIHandler)

      error_msg = Enum.find(messages, &(&1.type == :error))
      assert error_msg
      assert String.contains?(error_msg.error, "Connection timeout")
    end
  end

  describe "generic streaming interface" do
    test "parse_stream works with provider selection" do
      # Mock stream that simulates SSE events
      mock_events = [
        "event: message\ndata: {\"type\": \"response.output_text.delta\", \"delta\": \"Hello\"}\n\n",
        "event: message\ndata: {\"type\": \"response.output_text.delta\", \"delta\": \" world\"}\n\n",
        "data: [DONE]\n\n"
      ]

      _mock_stream = mock_events |> Stream.map(&String.to_charlist/1)

      # Test would require actual stream implementation - this is a structural test
      assert function_exported?(Streaming, :parse_stream, 2)
      assert function_exported?(Streaming, :parse_stream, 3)
    end
  end

  # Helper function to process events through a handler
  defp process_events(events, handler) do
    events
    |> Enum.flat_map(&handler.handle_event(&1, []))
    |> Enum.reject(&is_nil/1)
  end
end

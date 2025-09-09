defmodule TheMaestro.Conversations.TranslatorTest do
  use ExUnit.Case, async: true
  alias TheMaestro.Conversations.Translator

  test "openai function_call and usage to canonical events" do
    evts = [
      %{
        type: :function_call,
        function_call: [%{id: "call_1", function: %{name: "foo", arguments: "{\"x\":1}"}}]
      },
      %{type: :usage, usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}},
      %{type: :content, content: "Hello"}
    ]

    assert {:ok, [fc, usage, content]} = Translator.events_to_canonical(:openai, evts)

    assert fc == %{
             type: "function_call",
             calls: [%{"id" => "call_1", "name" => "foo", "arguments" => "{\"x\":1}"}]
           }

    assert usage == %{
             type: "usage",
             usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
           }

    assert content == %{type: "content", delta: "Hello"}
  end

  test "anthropic tool_use and usage to canonical events" do
    evts = [
      %{"type" => "tool_use", "id" => "tool_1", "name" => "bar", "input" => %{"y" => 2}},
      %{"type" => "message_delta", "usage" => %{"input_tokens" => 7, "output_tokens" => 3}},
      %{"type" => "input_json_delta", "delta" => "abc"}
    ]

    assert {:ok, [fc, usage, content]} = Translator.events_to_canonical(:anthropic, evts)

    assert fc == %{
             type: "function_call",
             calls: [%{"id" => "tool_1", "name" => "bar", "arguments" => ~s({"y":2})}]
           }

    assert usage == %{
             type: "usage",
             usage: %{prompt_tokens: 7, completion_tokens: 3, total_tokens: 10}
           }

    assert content == %{type: "content", delta: "abc"}
  end

  test "gemini functionCall to canonical events" do
    evts = [%{"functionCall" => %{"name" => "baz", "args" => %{"z" => 3}}}, %{"text" => "hi"}]

    assert {:ok, [fc, content]} = Translator.events_to_canonical(:gemini, evts)
    assert fc.type == "function_call"
    [call] = fc.calls
    assert call["name"] == "baz"
    assert call["arguments"] == ~s({"z":3})
    assert content == %{type: "content", delta: "hi"}
  end
end

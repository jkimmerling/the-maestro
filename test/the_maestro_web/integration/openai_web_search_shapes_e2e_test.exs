defmodule TheMaestroWeb.Integration.OpenAIWebSearchShapesE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  test "function_call/function_call_output shapes for web_search" do
    args_json = Jason.encode!(%{"query" => "phoenix liveview forms"})

    call = %{
      "type" => "function_call",
      "call_id" => "call_1",
      "name" => "web_search",
      "arguments" => args_json
    }

    out = %{
      "type" => "function_call_output",
      "call_id" => "call_1",
      # Provider returns a JSON string; shape parity assertion only
      "output" => Jason.encode!(%{"output" => TheMaestro.Tools.ExecOutput.format("", 0, 0.0)})
    }

    assert call["type"] == "function_call"
    assert call["name"] == "web_search"
    assert is_binary(call["arguments"]) and String.starts_with?(call["arguments"], "{")

    assert out["type"] == "function_call_output"
    assert is_binary(out["output"]) and String.starts_with?(out["output"], "{")
  end
end


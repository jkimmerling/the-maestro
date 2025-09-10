defmodule TheMaestro.Domain.CombinedChatTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Domain.CombinedChat

  test "from_map adds default version and preserves messages" do
    cc =
      CombinedChat.from_map(%{
        "messages" => [%{"role" => "user", "content" => [%{"type" => "text", "text" => "hi"}]}]
      })

    assert cc.version == "v1"
    assert length(cc.messages) == 1
  end

  test "to_map round-trips" do
    map = %{
      "messages" => [%{"role" => "assistant", "content" => [%{"type" => "text", "text" => "ok"}]}],
      "events" => [%{"type" => "usage"}]
    }

    out = CombinedChat.new(map) |> CombinedChat.to_map()
    assert out["version"] == "v1"
    assert out["messages"] == map["messages"]
    assert out["events"] == map["events"]
  end
end

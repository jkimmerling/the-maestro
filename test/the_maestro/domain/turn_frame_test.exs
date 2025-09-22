defmodule TheMaestro.Domain.TurnFrameTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Domain.TurnFrame

  test "new!/1 and to_map/1 roundtrip" do
    f =
      TurnFrame.new!(%{
        id: "00000000-0000-0000-0000-000000000000",
        idx: 3,
        at_ms: 123,
        role: "assistant",
        kind: "assistant_text",
        payload: %{"delta" => "hi"},
        thought?: false,
        collapsed?: true
      })

    m = TurnFrame.to_map(f)
    assert m["id"] == "00000000-0000-0000-0000-000000000000"
    assert m["idx"] == 3
    assert m["at_ms"] == 123
    assert m["role"] == "assistant"
    assert m["kind"] == "assistant_text"
    assert m["payload"] == %{"delta" => "hi"}
    assert m["thought?"] == false
    assert m["collapsed?"] == true
  end
end

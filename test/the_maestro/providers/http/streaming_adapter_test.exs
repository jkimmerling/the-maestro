defmodule TheMaestro.Providers.Http.StreamingAdapterTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.Http.StreamingAdapter

  test "parse_sse_events splits multiple events and preserves event types and data" do
    chunk =
      [
        "event: message\n",
        "data: {\"id\":\"evt1\",\"delta\":{\"content\":\"Hel\"}}\n\n",
        "event: message\n",
        "data: {\"id\":\"evt2\",\"delta\":{\"content\":\"lo\"}}\n\n",
        "event: done\n",
        "data: [DONE]\n\n"
      ]
      |> IO.iodata_to_binary()

    events = StreamingAdapter.parse_sse_events([chunk]) |> Enum.to_list()

    assert length(events) == 3
    assert Enum.at(events, 0).event_type == "message"
    assert Enum.at(events, 1).event_type == "message"
    assert Enum.at(events, 2).event_type == "done"
    assert String.contains?(Enum.at(events, 0).data, "evt1")
    assert String.contains?(Enum.at(events, 1).data, "evt2")
    assert Enum.at(events, 2).data == "[DONE]"
  end

  test "parse_sse_events defaults to message when event not specified" do
    chunk = "data: {\"x\":1}\n\n"
    [event] = StreamingAdapter.parse_sse_events([chunk]) |> Enum.to_list()
    assert event.event_type == "message"
    assert event.data == "{\"x\":1}"
  end

  test "parse_sse_events handles malformed lines gracefully" do
    # Lines without data:/event: prefixes should be ignored without crashing
    chunk = ["foo bar\n", "baz qux\n\n"] |> IO.iodata_to_binary()
    [event] = StreamingAdapter.parse_sse_events([chunk]) |> Enum.to_list()

    assert event.event_type == "message"
    assert event.data == ""
  end

  test "parse_sse_events combines multi-line data and detects [DONE] without explicit event" do
    chunk1 =
      [
        "data: part1\n",
        "data: part2\n\n"
      ]
      |> IO.iodata_to_binary()

    [ev1] = StreamingAdapter.parse_sse_events([chunk1]) |> Enum.to_list()
    assert ev1.event_type == "message"
    assert ev1.data == "part1\npart2"

    done_chunk = "data: [DONE]\n\n"
    [done_ev] = StreamingAdapter.parse_sse_events([done_chunk]) |> Enum.to_list()
    assert done_ev.event_type == "message"
    assert done_ev.data == "[DONE]"
  end
end

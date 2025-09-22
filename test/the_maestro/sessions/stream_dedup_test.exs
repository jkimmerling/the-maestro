defmodule TheMaestro.Sessions.StreamDedupTest do
  use ExUnit.Case, async: true
  alias TheMaestro.Sessions.Manager

  test "merges overlapping content and drops duplicates" do
    session_id = "sid-#{System.unique_integer()}"
    stream_id = "x"

    base = %{
      text: "",
      tool_calls: [],
      usage: nil,
      events: [],
      meta: %{},
      frames: [],
      frame_idx: 0
    }

    st = %{session_id => %{stream_id: stream_id, acc: base}}

    {:noreply, st0} = Manager.handle_cast({:acc_content, session_id, stream_id, "- a\n"}, st)

    {:noreply, st1} =
      Manager.handle_cast({:frame_event, session_id, stream_id, :content, "- a\n"}, st0)

    chunk2 = "- a\n- b\n"
    {:noreply, st2} = Manager.handle_cast({:acc_content, session_id, stream_id, chunk2}, st1)

    {:noreply, st3} =
      Manager.handle_cast({:frame_event, session_id, stream_id, :content, chunk2}, st2)

    acc = get_in(st3, [session_id, :acc])
    assert acc.text == "- a\n- b\n"

    frames = acc.frames
    assert length(frames) == 2
    assert Enum.at(frames, 0)["payload"]["delta"] == "- a\n"
    assert Enum.at(frames, 1)["payload"]["delta"] == "- b\n"
  end
end

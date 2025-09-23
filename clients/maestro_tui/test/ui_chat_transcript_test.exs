defmodule MaestroTui.UITranscriptTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "assistant_text is visible in transcript even when log hidden" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{screen: :chat, log_visible: false, transcript: ["> hello"], log: []}
    s2 = MaestroTui.UI.update(s, {:ui, {:append_text, "world"}})

    view = :erlang.apply(MaestroTui.UI, :render, [s2])
    text = Ratatouille.Renderer.Text.render(view)

    assert text =~ "> hello"
    assert text =~ "world"
  end
end

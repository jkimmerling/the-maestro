defmodule MaestroTui.UIThinkingToggleTest do
  use ExUnit.Case, async: true

  test "Ctrl+Shift+T cycles thinking visibility" do
    s0 = %MaestroTui.UI.State{screen: :chat, thinking_visibility: :collapsed}
    s1 = MaestroTui.UI.update(s0, {:event, %{mod: :ctrl_shift, ch: ?T}})
    assert s1.thinking_visibility == :expanded
    s2 = MaestroTui.UI.update(s1, {:event, %{mod: :ctrl_shift, ch: ?T}})
    assert s2.thinking_visibility == :hidden
    s3 = MaestroTui.UI.update(s2, {:event, %{mod: :ctrl_shift, ch: ?T}})
    assert s3.thinking_visibility == :collapsed
  end

  test "slash /thinking sets explicit mode" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    import Ratatouille.Constants, only: [key: 1]

    s0 = %MaestroTui.UI.State{screen: :chat, thinking_visibility: :collapsed, input: "/thinking hidden"}
    s1 = MaestroTui.UI.update(s0, {:event, %{key: key(:enter)}})
    assert s1.thinking_visibility == :hidden

    s2 = %MaestroTui.UI.State{screen: :chat, thinking_visibility: :collapsed, input: "/thoughts expanded"}
    s3 = MaestroTui.UI.update(s2, {:event, %{key: key(:enter)}})
    assert s3.thinking_visibility == :expanded
  end
end


defmodule MaestroTui.UICtrlShiftFallbackTest do
  use ExUnit.Case, async: true

  test "update/2 handles events without modifiers (no crash)" do
    s = %MaestroTui.UI.State{screen: :chat, input: ""}
    # Empty event map exercises ctrl_shift?/2 fallback
    s2 = MaestroTui.UI.update(s, {:event, %{}})
    assert s2 == s
  end
end


defmodule MaestroTui.UIBackspaceTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "backspace and backspace2 keys delete one char" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    import Ratatouille.Constants, only: [key: 1]

    s = %MaestroTui.UI.State{screen: :chat, input: "abc"}

    s1 = MaestroTui.UI.update(s, {:event, %{key: key(:backspace)}})
    assert s1.input == "ab"

    s2 = MaestroTui.UI.update(%{s1 | input: "ab"}, {:event, %{key: key(:backspace2)}})
    assert s2.input == "a"
  end
end


defmodule MaestroTui.UISnapshotTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "wizard renders provider panel" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    state = %MaestroTui.UI.State{screen: :wizard, providers: ["openai", "anthropic"]}
    view = :erlang.apply(MaestroTui.UI, :render, [state])

    text = Ratatouille.Renderer.Text.render(view)
    assert text =~ "Provider / Auth / Model"
    assert text =~ "openai"
  end
end


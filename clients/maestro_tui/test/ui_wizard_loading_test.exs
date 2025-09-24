defmodule MaestroTui.UIWizardLoadingTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "wizard shows loading indicators for empty auths/models" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{
      screen: :wizard,
      providers: ["openai"],
      prov_idx: 0,
      provider: "openai",
      auths: [],
      auth_idx: 0,
      models: [],
      model_idx: 0,
      wizard_focus: :auth
    }

    view = :erlang.apply(MaestroTui.UI, :render, [s])
    text = Ratatouille.Renderer.Text.render(view)
    assert text =~ "loading…"
  end
end


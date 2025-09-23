defmodule MaestroTui.UIWizardTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "arrow keys move focus and selection" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{screen: :wizard, providers: ["openai", "anthropic", "gemini"], prov_idx: 0}

    s1 = MaestroTui.UI.update(s, {:event, %{key: :down}})
    assert s1.prov_idx == 1

    s2 = MaestroTui.UI.update(%{s1 | wizard_focus: :provider}, {:event, %{key: :right}})
    assert s2.wizard_focus == :auth

    s3 = MaestroTui.UI.update(%{s2 | auths: ["a1", "a2"], auth_idx: 0}, {:event, %{key: :down}})
    assert s3.auth_idx == 1

    s4 = MaestroTui.UI.update(%{s3 | wizard_focus: :model, models: ["m1", "m2"], model_idx: 0}, {:event, %{key: :down}})
    assert s4.model_idx == 1

    view = :erlang.apply(MaestroTui.UI, :render, [%{s4 | screen: :wizard}])
    txt = Ratatouille.Renderer.Text.render(view)
    assert txt =~ "> anthropic"
  end
end


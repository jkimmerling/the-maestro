defmodule MaestroTui.UIKeybindingsTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "cycle provider/auth/model and sessions without network" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{
      screen: :chat,
      providers: ["openai", "anthropic", "gemini"],
      provider: "openai",
      auths: ["a1", "a2"], auth_id: "a1",
      models: ["m1", "m2"], model: "m1",
      order: ["1"], active: "1"
    }

    s1 = MaestroTui.UI.cycle_provider(s)
    assert s1.provider == "anthropic"

    s2 = MaestroTui.UI.cycle_auth(s1)
    assert s2.auth_id == "a2"

    s3 = MaestroTui.UI.cycle_model(s2)
    assert s3.model == "m2"

    s4 = MaestroTui.UI.new_session(s3)
    assert length(s4.order) == 2

    s5 = MaestroTui.UI.next_session(%{s4 | active: hd(s4.order)})
    assert s5.active == Enum.at(s4.order, 1)

    s6 = MaestroTui.UI.prev_session(s5)
    assert s6.active == hd(s4.order)

    view = :erlang.apply(MaestroTui.UI, :render, [%{s6 | provider: "openai", auth_id: "a1", model: "m1"}])
    text = Ratatouille.Renderer.Text.render(view)
    assert text =~ "Provider: openai"
  end
end


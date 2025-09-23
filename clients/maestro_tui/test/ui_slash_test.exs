defmodule MaestroTui.UISlashTest do
  use ExUnit.Case, async: true

  @moduletag :ui

  test "/context logs context with usage" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{
      screen: :chat,
      provider: "openai",
      model: "gpt-4o",
      last_usage: %{input_tokens: 3, output_tokens: 5, total_tokens: 8},
      input: "/context",
      log: []
    }

    s2 = MaestroTui.UI.update(s, {:event, %{key: :enter}})
    assert Enum.any?(s2.log, &String.contains?(&1, "Context — provider=openai model=gpt-4o tokens{input: 3, output: 5, total: 8}"))
  end

  test "/model opens model picker and selection updates model" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{
      screen: :chat,
      provider: "openai",
      auth_id: "a1",
      models: ["m1", "m2"],
      input: "/model",
      log: []
    }

    s1 = MaestroTui.UI.update(s, {:event, %{key: :enter}})
    assert match?({:model_picker, _items, _idx}, s1.modal)

    s2 = MaestroTui.UI.update(s1, {:event, %{key: :down}})
    s3 = MaestroTui.UI.update(s2, {:event, %{key: :enter}})
    assert s3.model == "m2"
  end

  test "/help prints usage and /clear resets state" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{screen: :chat, input: "/help", log: ["foo"], provider: "openai", model: "gpt-4o"}
    s1 = MaestroTui.UI.update(s, {:event, %{key: :enter}})
    assert Enum.any?(s1.log, &String.contains?(&1, "/context"))

    s2 = %MaestroTui.UI.State{screen: :chat, input: "/clear", log: ["bar"], order: ["1"], active: "1"}
    s3 = MaestroTui.UI.update(s2, {:event, %{key: :enter}})
    assert s3.log == []
    assert s3.session_id == nil
    assert length(s3.order) == 2
  end

  test "slash suggestions appear in render" do
    unless Code.ensure_loaded?(Ratatouille) do
      skip("ratatouille not available; set TUI_ENABLE_TUI=1 for UI tests")
    end

    s = %MaestroTui.UI.State{screen: :chat, input: "/m", log: []}
    view = :erlang.apply(MaestroTui.UI, :render, [s])
    text = Ratatouille.Renderer.Text.render(view)
    assert text =~ "/model"
  end
end

from maestro_tui.app import MaestroTextual


def test_build_markdown_with_code_fence():
    app = MaestroTextual()
    msgs = [
        {"role": "user", "text": "show code"},
        {"role": "assistant", "text": "```js\nconsole.log('x')\n```"},
        {"role": "tool", "text": "ls -la"},
    ]
    md = app._build_markdown(msgs)
    assert "**You**" in md
    assert "**Assistant**" in md
    assert "**Tool**" in md
    assert "```" in md


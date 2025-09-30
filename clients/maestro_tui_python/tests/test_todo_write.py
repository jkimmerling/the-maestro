from maestro_tui.tools.todo import todo_write


def test_todo_write_normalizes_and_counts():
    out = todo_write([
        {"content": "Task A", "activeForm": "x", "status": "in_progress"},
        {"content": "Task B", "activeForm": "x", "status": "completed"},
    ])
    assert out.output.startswith("todos updated:")


import asyncio
import pytest

from maestro_tui.app import MaestroTextual


pytestmark = pytest.mark.asyncio


class _FakeAPI:
    def __init__(self, threads, snapshots):
        self._threads = threads
        self._snapshots = snapshots

    async def list_threads(self, session_id: str):
        return list(self._threads)

    async def thread_snapshot(self, thread_id: str):
        return list(self._snapshots.get(thread_id, []))


async def test_set_current_thread_loads_snapshot(monkeypatch):
    app = MaestroTextual()
    app.api = _FakeAPI(
        threads=[
            {"id": "t2", "label": "Later", "updated_at": "2025-09-28T12:00:00Z"},
            {"id": "t1", "label": "Earlier", "updated_at": "2025-09-27T12:00:00Z"},
        ],
        snapshots={
            "t1": [{"role": "user", "text": "hello"}],
            "t2": [
                {"role": "assistant", "text": "```python\nprint('ok')\n```"},
            ],
        },
    )
    app.current_session_id = "s1"

    await app.set_current_thread("t2")
    assert isinstance(app._transcript, list)
    assert any(m.get("role") == "assistant" for m in app._transcript)

    md = app._build_markdown(app._transcript)
    assert "```python" in md or "```" in md


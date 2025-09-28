import pytest

from maestro_tui.app import MaestroTextual


class _Dummy:
    def update(self, *_args, **_kwargs):
        return None


class _FakeAPI:
    def __init__(self):
        self.cleared = []

    async def clear_thread(self, tid: str):
        self.cleared.append(tid)


@pytest.mark.asyncio
async def test_slash_clear_clears_thread_and_updates_state(monkeypatch):
    app = MaestroTextual()
    app.api = _FakeAPI()
    app.current_thread_id = "t1"

    def _fake_query_one(_sel, _cls):
        return _Dummy()

    monkeypatch.setattr(app, "query_one", _fake_query_one)

    handled = await app.handle_slash_command("/clear")
    assert handled
    assert isinstance(app.api.cleared, list) and app.api.cleared == ["t1"]
    assert getattr(app, "_transcript", []) == []


@pytest.mark.asyncio
async def test_slash_help_sets_status(monkeypatch):
    app = MaestroTextual()
    app.api = _FakeAPI()

    updated = {"n": 0}

    class _Status:
        def update(self, _text):
            updated["n"] += 1

    def _fake_query_one(sel, cls):
        if sel == "#status":
            return _Status()
        return _Dummy()

    monkeypatch.setattr(app, "query_one", _fake_query_one)
    handled = await app.handle_slash_command("/help")
    assert handled and updated["n"] == 1


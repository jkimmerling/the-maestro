import pytest

from maestro_tui.app import MaestroTextual, ModelPickerScreen, ChatScreen


class _FakeAPI:
    def __init__(self):
        self.created_sessions = []
        self.updated = []

    async def create_session(self, *, auth_id: str, model_id: str, tool_runtime: str = "remote", **_extra):
        sid = "sess_new"
        self.created_sessions.append((auth_id, model_id, tool_runtime, sid))
        return sid

    async def update_session(self, session_id: str, *, auth_id: str | None = None, model_id: str | None = None):
        self.updated.append((session_id, auth_id, model_id))
        return {"id": session_id, "auth_id": auth_id, "model_id": model_id}

    async def list_threads(self, session_id: str):
        return []

    async def thread_snapshot(self, thread_id: str):
        return []


class _Dummy:
    def update(self, *_args, **_kwargs):
        return None


@pytest.mark.asyncio
async def test_new_session_sets_active_and_marks_reload(monkeypatch):
    app = MaestroTextual()
    app.api = _FakeAPI()
    app.current_session_id = "sess_old"
    app.current_thread_id = "thread_old"

    # No-op screen navigation
    monkeypatch.setattr(app, "pop_screen", lambda *a, **k: None)

    screen = ModelPickerScreen(for_new_session=True)
    screen.app = app  # attach app for direct invocation
    screen.selected_provider = "openai"
    screen.selected_auth_id = "auth1"
    screen.selected_model = "gpt-4o"

    await screen.confirm_selection()

    assert app.current_session_id == "sess_new"
    assert app.current_thread_id is None
    assert app._session_updated is True

    chat = ChatScreen()
    chat.app = app

    # Stub UI lookups used by ChatScreen
    def _fake_query_one(_sel, _cls):
        return _Dummy()

    monkeypatch.setattr(chat, "query_one", _fake_query_one)

    # Should attempt to reload when resumed due to _session_updated flag
    await chat.on_screen_resume()


@pytest.mark.asyncio
async def test_model_update_marks_reload_and_keeps_session(monkeypatch):
    app = MaestroTextual()
    api = _FakeAPI()
    app.api = api
    app.current_session_id = "sess_existing"

    monkeypatch.setattr(app, "pop_screen", lambda *a, **k: None)

    screen = ModelPickerScreen(for_new_session=False)
    screen.app = app
    screen.selected_provider = "anthropic"
    screen.selected_auth_id = "authA"
    screen.selected_model = "claude-3-5"

    await screen.confirm_selection()

    assert app.current_session_id == "sess_existing"
    assert app._session_updated is True
    assert api.updated and api.updated[-1] == ("sess_existing", "authA", "claude-3-5")

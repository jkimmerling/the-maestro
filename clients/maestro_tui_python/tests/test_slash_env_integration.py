import os
import pytest
import httpx

from maestro_tui.config import ApiConfig
from maestro_tui.api.client import MaestroAPI
from maestro_tui.app import MaestroTextual


class _Dummy:
    def update(self, *_args, **_kwargs):
        return None


pytestmark = pytest.mark.asyncio


@pytest.mark.integration
async def test_slash_clear_against_server(monkeypatch):
    host = os.environ.get("TUI_API_BASE_URL")
    token = os.environ.get("TUI_API_TOKEN")
    if not host or not token:
        pytest.skip("TUI_API_* env not set")

    cfg = ApiConfig(api_host=host, api_key=token)
    api = MaestroAPI(cfg, client=httpx.AsyncClient(base_url=f"{host}/api", timeout=None))
    app = MaestroTextual()
    app.api = api
    try:
        sessions = await api.list_remote_sessions()
        if not sessions:
            pytest.skip("no remote sessions available")
        sid = sessions[0]["id"]
        threads = await api.list_threads(sid)
        if not threads:
            created = await api.create_thread(sid, label="pytest-clear")
            tid = created["id"]
        else:
            tid = threads[0]["id"]
        app.current_thread_id = tid

        def _fake_query_one(_sel, _cls):
            return _Dummy()

        monkeypatch.setattr(app, "query_one", _fake_query_one)
        handled = await app.handle_slash_command("/clear")
        assert handled
    finally:
        await api.close()


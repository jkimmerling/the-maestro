import os
import pytest
import httpx

from maestro_tui.config import ApiConfig
from maestro_tui.api.client import MaestroAPI
from maestro_tui.app import MaestroTextual


pytestmark = pytest.mark.asyncio


@pytest.mark.integration
async def test_thread_picker_env_integration(monkeypatch):
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
        app.current_session_id = sid
        threads = await api.list_threads(sid)
        if len(threads) < 2:
            created = await api.create_thread(sid, label="pytest-thread")
            threads = await api.list_threads(sid)
            assert any(t["id"] == created["id"] for t in threads)

        threads.sort(key=lambda t: t.get("updated_at") or "", reverse=True)
        pick = threads[-1]["id"]
        await app.set_current_thread(pick)
        assert isinstance(app._transcript, list)
    finally:
        await api.close()


import os
import httpx
import pytest

from maestro_tui.config import ApiConfig
from maestro_tui.api.client import MaestroAPI
from maestro_tui.orchestrator import send_and_orchestrate


pytestmark = pytest.mark.asyncio


@pytest.mark.integration
async def test_e2e_turn_flow_env(tmp_path):
    host = os.environ.get("TUI_API_BASE_URL")
    token = os.environ.get("TUI_API_TOKEN")
    provider = os.environ.get("TUI_PROVIDER", "gemini")
    if not host or not token:
        pytest.skip("env not set")

    cfg = ApiConfig(api_host=host, api_key=token)
    api = MaestroAPI(cfg, client=httpx.AsyncClient(base_url=f"{host}/api", timeout=None))
    try:
        sessions = await api.list_remote_sessions()
        if not sessions:
            pytest.skip("no remote sessions")
        sid = sessions[0]["id"]
        msgs = await send_and_orchestrate(api, session_id=sid, message="Print 'hi' and if tools available, run a shell echo hi", provider=provider, base_dir=str(tmp_path))
        assert isinstance(msgs, list)
    finally:
        await api.close()


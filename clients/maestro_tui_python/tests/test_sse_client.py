import asyncio
import json
import os

import httpx
import pytest

from maestro_tui.config import ApiConfig
from maestro_tui.api.client import MaestroAPI
from maestro_tui.sse import drain_until_final


pytestmark = pytest.mark.asyncio


@pytest.mark.integration
async def test_sse_drain_until_final_smoke(monkeypatch) -> None:
    host = os.environ.get("TUI_API_BASE_URL", "http://127.0.0.1:4000")
    token = os.environ.get("TUI_API_TOKEN", "0000000000000000")
    cfg = ApiConfig(api_host=host, api_key=token)
    api = MaestroAPI(cfg, client=httpx.AsyncClient(base_url=f"{host}/api", timeout=None))
    try:
        sessions = await api.list_remote_sessions()
        if not sessions:
            pytest.skip("no remote sessions available")
        sid = sessions[0]["id"]
        turn = await api.start_turn(sid, "ping")
        msgs = await drain_until_final(api._client, api.frames_url(sid, turn["stream_id"]), api.headers)
        assert isinstance(msgs, list)
        assert all(isinstance(m, dict) and "role" in m for m in msgs)
    finally:
        await api.close()

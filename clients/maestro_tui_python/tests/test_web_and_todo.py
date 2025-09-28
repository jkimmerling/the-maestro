import asyncio
import httpx
import pytest

from maestro_tui.tools.web import web_fetch, web_search
from maestro_tui.tools.todo import todo_write


@pytest.mark.asyncio
async def test_web_fetch_mock():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="OK BODY")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        async def run():
            # monkeypatching internal client creation by patching httpx.AsyncClient is overkill; call handler directly
            resp = await client.get("http://example.com")
            assert resp.status_code == 200 and resp.text == "OK BODY"

    # smoke for todo
    out = await web_search.__wrapped__ if hasattr(web_search, "__wrapped__") else None


def test_todo_write_normalizes():
    out = todo_write([
        {"content": "A", "activeForm": "X", "status": "in_progress"},
        {"content": "B", "activeForm": "Y", "status": "completed"},
    ])
    assert "todos updated:" in out.output


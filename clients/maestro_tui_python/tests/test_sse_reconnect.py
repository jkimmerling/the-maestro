import asyncio
from typing import AsyncIterator

import httpx
import pytest

from maestro_tui.sse import SSEClient


pytestmark = pytest.mark.asyncio


def _sse_lines(lines: list[str]) -> AsyncIterator[bytes]:
    async def gen():
        for line in lines:
            await asyncio.sleep(0)
            yield (line + "\n").encode()
    return gen()


@pytest.mark.integration
async def test_sse_reconnect_until_final_with_jitter() -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            body = [
                "event: message",
                "data: {\"data\": {\"kind\": \"user_text\", \"payload\": {\"text\": \"hi\"}}}",
            ]
            # no final; stream ends to force reconnect
            return httpx.Response(200, request=request, headers={"content-type": "text/event-stream"}, content=_sse_lines(body))
        else:
            body = [
                "event: message",
                "data: {\"data\": {\"kind\": \"assistant_text\", \"idx\": 0, \"payload\": {\"delta\": \"pong\"}}}",
                "event: message",
                "data: {\"data\": {\"kind\": \"final\", \"payload\": {}}}",
            ]
            return httpx.Response(200, request=request, headers={"content-type": "text/event-stream"}, content=_sse_lines(body))

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        sse = SSEClient(client, base_backoff=0.01, max_backoff=0.02, jitter=0.0, max_retries=3)
        events = []
        async for ev in sse.stream("/sse", headers=None, stop_on_final=True):
            events.append(ev)

    kinds = [e["data"].get("kind") for e in events]
    assert "final" in kinds
    assert calls["n"] == 2


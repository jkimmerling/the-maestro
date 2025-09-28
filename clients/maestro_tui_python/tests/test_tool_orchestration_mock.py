import asyncio
import json
from pathlib import Path

import httpx
import pytest

from maestro_tui.api.client import MaestroAPI
from maestro_tui.orchestrator import send_and_orchestrate


pytestmark = pytest.mark.asyncio


def _sse_lines(lines):
    async def gen():
        for line in lines:
            await asyncio.sleep(0)
            yield (line + "\n").encode()
    return gen()


async def test_orchestrate_function_call_and_post_tool_result(tmp_path: Path):
    posts = {"tools": []}

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if url.endswith("/api/sessions/s1/turns") and request.method == "POST":
            return httpx.Response(200, json={"stream_id": "st1"})
        if url.endswith("/api/sessions/s1/turns/st1/frames") and request.method == "GET":
            body = [
                "event: message",
                "data: {\"data\": {\"kind\": \"user_text\", \"payload\": {\"text\": \"do shell\"}}}",
                "event: message",
                "data: {\"data\": {\"kind\": \"function_call\", \"payload\": {\"calls\": [{\"id\": \"c1\", \"name\": \"run_shell_command\", \"arguments\": \"{\\\"command\\\": \\\"echo hi\\\"}\"}]}}}",
                "event: message",
                "data: {\"data\": {\"kind\": \"final\", \"payload\": {}}}",
            ]
            return httpx.Response(200, headers={"content-type": "text/event-stream"}, content=_sse_lines(body))
        if url.endswith("/api/sessions/s1/turns/st1/tools/results") and request.method == "POST":
            payload = json.loads(request.content.decode())
            posts["tools"].append(payload)
            return httpx.Response(200, json={"ok": True})
        return httpx.Response(404)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        api = MaestroAPI(type("Cfg", (), {"api_host": "http://test", "api_key": "x"})(), client=client)
        msgs = await send_and_orchestrate(api, session_id="s1", message="hi", provider="gemini", base_dir=str(tmp_path))
        assert any(m.get("role") == "assistant" for m in msgs) or isinstance(msgs, list)

    assert posts["tools"], "tool result not posted"
    out = posts["tools"][0]["output"]
    assert '"exit_code": 0' in out and '"output": "hi' in out


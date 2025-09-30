from __future__ import annotations

import asyncio
import json
import random
from typing import AsyncGenerator, Dict, Any, Optional

import httpx


class SSEClient:
    def __init__(
        self,
        client: httpx.AsyncClient,
        *,
        base_backoff: float = 0.5,
        max_backoff: float = 10.0,
        jitter: float = 0.2,
        max_retries: Optional[int] = None,
    ) -> None:
        self._client = client
        self._base = base_backoff
        self._max = max_backoff
        self._j = jitter
        self._max_retries = max_retries

    async def _sleep_backoff(self, attempt: int) -> None:
        delay = min(self._base * (2 ** max(0, attempt - 1)), self._max)
        if self._j > 0:
            jitter_val = random.uniform(-self._j, self._j) * delay
            delay = max(0.0, delay + jitter_val)
        await asyncio.sleep(delay)

    async def stream(
        self,
        url: str,
        *,
        headers: Dict[str, str] | None = None,
        stop_on_final: bool = False,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        attempt = 0
        total_attempts = 0
        while True:
            try:
                async with self._client.stream("GET", url, headers=headers, timeout=None) as resp:
                    resp.raise_for_status()
                    event_name: str | None = None
                    async for line in resp.aiter_lines():
                        if not line:
                            continue
                        if line.startswith(":"):
                            # heartbeat/comment
                            continue
                        if line.startswith("event:"):
                            event_name = line.split(":", 1)[1].strip()
                            continue
                        if line.startswith("data:"):
                            data_str = line.split(":", 1)[1].strip()
                            try:
                                payload = json.loads(data_str)
                            except json.JSONDecodeError:
                                continue
                            frame = payload.get("data", payload)
                            yield {"event": event_name or "message", "data": frame}
                            if stop_on_final and frame.get("kind") == "final":
                                return
                # Clean close without final — treat as retryable unless stop_on_final is False
                if stop_on_final:
                    total_attempts += 1
                    if self._max_retries is not None and total_attempts > self._max_retries:
                        return
                    attempt += 1
                    await self._sleep_backoff(attempt)
                    continue
                else:
                    return
            except (httpx.TransportError, httpx.ReadTimeout, httpx.RemoteProtocolError):
                total_attempts += 1
                if self._max_retries is not None and total_attempts > self._max_retries:
                    return
                attempt += 1
                await self._sleep_backoff(attempt)
                continue


def _append_text_segment(buckets: dict[int, str], idx: int, delta: str) -> None:
    prev = buckets.get(idx, "")
    buckets[idx] = prev + delta


def collate_frames_to_messages(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    assistant_chunks: dict[int, str] = {}
    thinking_seen = False

    for f in frames:
        kind = f.get("kind")
        payload = f.get("payload", {})
        if kind == "user_text":
            messages.append({"role": "user", "text": payload.get("text", "")})
        elif kind == "assistant_thinking":
            if not thinking_seen:
                messages.append({"role": "assistant", "text": "…"})
                thinking_seen = True
        elif kind == "assistant_text":
            idx = int(f.get("idx", 0))
            delta = payload.get("delta", "")
            _append_text_segment(assistant_chunks, idx, delta)
        elif kind == "function_call":
            calls = payload.get("calls", [])
            for c in calls:
                messages.append({
                    "role": "assistant",
                    "text": f"[tool:{c.get('name')}] {c.get('arguments')}"
                })
        elif kind == "tool_result":
            preview = payload.get("preview") or payload.get("output") or "(tool result)"
            messages.append({"role": "tool", "text": str(preview)[:1000]})
        elif kind == "final":
            pass

    if assistant_chunks:
        ordered = "".join(v for _, v in sorted(assistant_chunks.items(), key=lambda kv: kv[0]))
        # Replace the placeholder thinking bubble if present
        for i in range(len(messages) - 1, -1, -1):
            if messages[i]["role"] == "assistant" and messages[i]["text"] == "…":
                messages[i] = {"role": "assistant", "text": ordered}
                break
        else:
            messages.append({"role": "assistant", "text": ordered})

    return messages


async def drain_until_final(
    client: httpx.AsyncClient,
    url: str,
    headers: Dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    sse = SSEClient(client)
    async for ev in sse.stream(url, headers=headers, stop_on_final=True):
        frame = ev["data"]
        kind = frame.get("kind")
        if kind == "done":
            continue
        frames.append(frame)
    return collate_frames_to_messages(frames)

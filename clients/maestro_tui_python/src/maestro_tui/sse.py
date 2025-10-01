from __future__ import annotations

import asyncio
import json
import logging
import random
from typing import AsyncGenerator, Dict, Any, Optional

import httpx

# Debug logging to file
logger = logging.getLogger("maestro_tui.sse")
logger.setLevel(logging.DEBUG)
fh = logging.FileHandler("/tmp/maestro_tui_sse_debug.log")
fh.setLevel(logging.DEBUG)
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh.setFormatter(formatter)
logger.addHandler(fh)


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
        logger.info(f"Starting SSE stream to {url}, stop_on_final={stop_on_final}")
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
                                logger.warning(f"Failed to parse JSON: {data_str[:100]}")
                                continue
                            frame = payload.get("data", payload)
                            kind = frame.get("kind")
                            logger.debug(f"Received frame: kind={kind}")
                            yield {"event": event_name or "message", "data": frame}
                            # Don't return immediately on final - let the caller handle it
                            # Just continue yielding until stream naturally closes
                # Clean close - if stop_on_final was set but we didn't get final, retry
                logger.info(f"Stream closed cleanly, stop_on_final={stop_on_final}")
                if stop_on_final:
                    total_attempts += 1
                    if self._max_retries is not None and total_attempts > self._max_retries:
                        logger.warning(f"Max retries ({self._max_retries}) reached without final frame")
                        return
                    attempt += 1
                    logger.info(f"Retrying stream (attempt {attempt})")
                    await self._sleep_backoff(attempt)
                    continue
                else:
                    return
            except (httpx.TransportError, httpx.ReadTimeout, httpx.RemoteProtocolError) as e:
                logger.error(f"SSE stream error: {e}")
                total_attempts += 1
                if self._max_retries is not None and total_attempts > self._max_retries:
                    logger.error(f"Max retries ({self._max_retries}) reached after errors")
                    return
                attempt += 1
                await self._sleep_backoff(attempt)
                continue


def _append_text_segment(buckets: dict[int, str], idx: int, delta: str) -> None:
    prev = buckets.get(idx, "")
    buckets[idx] = prev + delta


def collate_frames_to_messages(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    assistant_chunks: list[str] = []
    final_content: str | None = None
    # We don't keep the thinking placeholder; TUI shows final text after tools for parity

    logger.info(f"Collating {len(frames)} frames into messages")

    for f in frames:
        kind = f.get("kind")
        payload = f.get("payload", {})
        logger.debug(f"Processing frame: kind={kind}, payload_keys={list(payload.keys()) if payload else []}")

        if kind == "user_text":
            messages.append({"role": "user", "text": payload.get("text", "")})
        elif kind == "assistant_thinking":
            # Skip placeholder in transcript; keep UI simple
            continue
        elif kind == "assistant_text":
            delta = payload.get("delta", "")
            if delta:
                assistant_chunks.append(delta)
        elif kind == "function_call":
            calls = payload.get("calls", [])
            for c in calls:
                name = c.get("name") or "tool"
                args = c.get("arguments") or "{}"
                messages.append({"role": "assistant", "text": f"[tool:{name}] {args}"})
        elif kind == "tool_result":
            preview = payload.get("preview") or payload.get("output") or "(tool result)"
            messages.append({"role": "tool", "text": str(preview)[:4000]})
        elif kind == "final":
            # Extract final content - this is the authoritative assistant response
            final_content = payload.get("content")
            logger.info(f"Found final frame with content: {final_content[:100] if final_content else 'None'}")
            continue

    # Use final content if available, otherwise use accumulated deltas
    if final_content:
        logger.info(f"Using final content ({len(final_content)} chars) as assistant response")
        messages.append({"role": "assistant", "text": final_content})
    elif assistant_chunks:
        ordered = "".join(assistant_chunks)
        logger.info(f"Using accumulated deltas ({len(ordered)} chars) as assistant response")
        messages.append({"role": "assistant", "text": ordered})
    else:
        logger.warning("No assistant content found in frames")

    logger.info(f"Collated to {len(messages)} messages")
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

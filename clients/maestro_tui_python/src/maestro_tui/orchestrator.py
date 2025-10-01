from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Dict, List, Optional, Awaitable, Callable

from .api.client import MaestroAPI
from .sse import SSEClient, collate_frames_to_messages
from .providers.adapters import normalize, execute_normalized

logger = logging.getLogger("maestro_tui.orchestrator")


def _guess_provider_from_name(name: str) -> str:
    if not name:
        return "openai"
    if name in {"run_shell_command", "list_directory", "glob", "search_file_content", "read_many_files", "google_web_search"}:
        return "gemini"
    if name and name[0].isupper():
        return "anthropic"
    return "openai"


async def orchestrate_turn(
    api: MaestroAPI,
    *,
    session_id: str,
    stream_id: str,
    provider: str,
    base_dir: str,
    on_frame: Optional[Callable[[Dict[str, Any]], Awaitable[None]]] = None,
) -> List[Dict[str, Any]]:
    frames: List[Dict[str, Any]] = []
    sse = SSEClient(api._client)
    url = api.frames_url(session_id, stream_id)
    logger.info(f"Starting orchestration for session={session_id}, stream={stream_id}")

    # Don't use stop_on_final - we want to collect all frames including the final one
    async for ev in sse.stream(url, headers=api.headers, stop_on_final=False):
        frame = ev["data"]
        kind = frame.get("kind")
        logger.debug(f"Orchestrator received frame: kind={kind}")

        if kind == "done":
            # Server sent done marker but keep listening for final frame
            logger.debug("Received 'done' marker, continuing to listen for final")
            continue

        if kind == "function_call":
            calls = (frame.get("payload") or {}).get("calls") or []
            logger.info(f"Processing {len(calls)} function calls")
            for call in calls:
                call_id = call.get("id") or ""
                name = call.get("name") or ""
                args_json = call.get("arguments") or "{}"
                logger.debug(f"Executing tool: {name}")
                try:
                    raw_args = json.loads(args_json)
                except Exception:
                    raw_args = {}
                prov = provider or _guess_provider_from_name(name)
                tool, norm_args = normalize(prov, name, raw_args)
                output = await execute_normalized(tool, norm_args, base_dir)
                await api.post_tool_result(session_id, stream_id, call_id=call_id, name=name, output=output)
                if on_frame is not None:
                    preview = output if isinstance(output, str) else json.dumps(output) if output is not None else ""
                    await on_frame({"role": "tool", "text": preview})

        # Collect ALL frames including final
        frames.append(frame)

        # Only break AFTER collecting the final frame
        if kind == "final":
            logger.info("Received final frame, breaking out of stream loop")
            break

    logger.info(f"Orchestration complete, collected {len(frames)} frames")
    return collate_frames_to_messages(frames)


async def send_and_orchestrate(
    api: MaestroAPI,
    *,
    session_id: str,
    message: str,
    provider: str,
    base_dir: str,
    on_frame: Optional[Callable[[Dict[str, Any]], Awaitable[None]]] = None,
) -> List[Dict[str, Any]]:
    turn = await api.start_turn(session_id, message)
    stream_id = turn["stream_id"]
    return await orchestrate_turn(
        api,
        session_id=session_id,
        stream_id=stream_id,
        provider=provider,
        base_dir=base_dir,
        on_frame=on_frame,
    )

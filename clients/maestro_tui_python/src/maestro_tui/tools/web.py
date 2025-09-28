from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import httpx

from .exec import ExecOutput


async def web_fetch(url: str, timeout: float = 15.0) -> ExecOutput:
    if not isinstance(url, str) or not url.startswith("http"):
        raise ValueError("invalid url")
    async with httpx.AsyncClient(timeout=timeout, headers={"user-agent": "TheMaestro/1.0 tool-runtime"}) as client:
        resp = await client.get(url)
        body = resp.text
        out = f"{resp.status_code}\n\n" + body[:60000]
        return ExecOutput(output=out, stderr="", exit_code=0, duration_seconds=0.0)


async def web_search(
    query: str,
    *,
    backend: str = "tavily",
    allowed_domains: Optional[List[str]] = None,
    blocked_domains: Optional[List[str]] = None,
    search_depth: str = "basic",
    api_key: Optional[str] = None,
    timeout: float = 20.0,
) -> ExecOutput:
    backend = backend.lower()
    if backend == "tavily":
        key = api_key or os.getenv("TAVILY_API_KEY")
        if not key:
            raise ValueError("tavily api key missing")
        payload: Dict[str, Any] = {"api_key": key, "query": query, "search_depth": search_depth}
        if allowed_domains:
            payload["include_domains"] = [s.strip() for s in allowed_domains if isinstance(s, str) and s.strip()]
        if blocked_domains:
            payload["exclude_domains"] = [s.strip() for s in blocked_domains if isinstance(s, str) and s.strip()]
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post("https://api.tavily.com/search", json=payload)
            return ExecOutput(output=resp.text, stderr="", exit_code=0, duration_seconds=0.0)
    elif backend == "google":
        key = api_key or os.getenv("GOOGLE_API_KEY") or os.getenv("GOOGLE_CSE_API_KEY")
        cx = os.getenv("GOOGLE_CSE_ID") or os.getenv("GOOGLE_CX")
        if not key or not cx:
            raise ValueError("google custom search env GOOGLE_CSE_ID and API key required")
        params = {"key": key, "cx": cx, "q": query}
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.get("https://www.googleapis.com/customsearch/v1", params=params)
            return ExecOutput(output=resp.text, stderr="", exit_code=0, duration_seconds=0.0)
    else:
        raise ValueError(f"unsupported web_search backend: {backend}")


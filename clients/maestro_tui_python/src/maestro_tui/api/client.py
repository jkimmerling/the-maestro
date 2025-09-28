from __future__ import annotations

from typing import Any, Dict, Optional

import httpx

from ..config import ApiConfig


class MaestroAPI:
    def __init__(self, cfg: ApiConfig, client: Optional[httpx.AsyncClient] = None) -> None:
        self.cfg = cfg
        self._client = client or httpx.AsyncClient(base_url=f"{cfg.api_host}/api")

    @property
    def headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self.cfg.api_key}"}

    async def close(self) -> None:
        await self._client.aclose()

    # Providers
    async def list_providers(self) -> list[str]:
        r = await self._client.get("/providers", headers=self.headers)
        r.raise_for_status()
        return r.json().get("providers", [])

    async def list_saved_auths(self, provider: str) -> list[dict[str, Any]]:
        r = await self._client.get(f"/providers/{provider}/saved_auths", headers=self.headers)
        r.raise_for_status()
        return r.json().get("auths", [])

    async def list_models(self, provider: str, auth_id: str) -> list[str]:
        r = await self._client.get(
            f"/providers/{provider}/saved_auths/{auth_id}/models", headers=self.headers
        )
        r.raise_for_status()
        return r.json().get("models", [])

    # Sessions
    async def create_session(self, *, auth_id: str, model: str, working_dir: Optional[str] = None,
                             tool_runtime: str = "remote") -> str:
        payload = {
            "auth_id": auth_id,
            "model": model,
            "working_dir": working_dir,
            "tool_runtime": tool_runtime,
        }
        r = await self._client.post("/sessions", json=payload, headers=self.headers)
        r.raise_for_status()
        return r.json()["session_id"]

    async def list_remote_sessions(self) -> list[dict[str, Any]]:
        r = await self._client.get("/sessions", params={"tool_runtime": "remote"}, headers=self.headers)
        r.raise_for_status()
        return r.json().get("sessions", [])

    # Turns
    async def start_turn(self, session_id: str, message: str, thread_id: Optional[str] = None) -> dict[str, Any]:
        payload: dict[str, Any] = {"message": message}
        if thread_id:
            payload["thread_id"] = thread_id
        r = await self._client.post(f"/sessions/{session_id}/turns", json=payload, headers=self.headers)
        r.raise_for_status()
        return r.json()

    # Frames
    def frames_url(self, session_id: str, stream_id: str) -> str:
        return f"{self.cfg.api_host}/api/sessions/{session_id}/turns/{stream_id}/frames"

    async def latest_frames(self, thread_id: str) -> list[dict[str, Any]]:
        r = await self._client.get(f"/threads/{thread_id}/turns/latest/frames", headers=self.headers)
        r.raise_for_status()
        return r.json().get("frames", [])

    async def thread_snapshot(self, thread_id: str) -> list[dict[str, Any]]:
        r = await self._client.get(f"/threads/{thread_id}/snapshot", headers=self.headers)
        r.raise_for_status()
        return r.json().get("messages", [])

    # Tool results
    async def post_tool_result(self, session_id: str, stream_id: str, *, call_id: str, name: str, output: str) -> None:
        payload = {"call_id": call_id, "name": name, "output": output}
        r = await self._client.post(
            f"/sessions/{session_id}/turns/{stream_id}/tools/results", json=payload, headers=self.headers
        )
        r.raise_for_status()

    # Threads
    async def list_threads(self, session_id: str) -> list[dict[str, Any]]:
        r = await self._client.get(f"/sessions/{session_id}/threads", headers=self.headers)
        r.raise_for_status()
        return r.json().get("threads", [])

    async def create_thread(self, session_id: str, label: str | None = None) -> dict[str, Any]:
        payload: dict[str, Any] = {}
        if label:
            payload["label"] = label
        r = await self._client.post(f"/sessions/{session_id}/threads", json=payload, headers=self.headers)
        r.raise_for_status()
        return r.json()

    async def rename_thread(self, thread_id: str, label: str) -> None:
        r = await self._client.patch(f"/threads/{thread_id}", json={"label": label}, headers=self.headers)
        r.raise_for_status()

    async def clear_thread(self, thread_id: str) -> None:
        r = await self._client.post(f"/threads/{thread_id}/clear", headers=self.headers)
        r.raise_for_status()

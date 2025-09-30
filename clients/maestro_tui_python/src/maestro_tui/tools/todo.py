from __future__ import annotations

from dataclasses import dataclass
from typing import List, Dict

from .exec import ExecOutput


VALID = {"pending", "in_progress", "completed"}


def _norm_status(s):
    if s in ("pending", "in_progress", "completed"):
        return s
    if s in ("pending",):
        return "pending"
    return "pending"


def todo_write(todos: List[Dict]) -> ExecOutput:
    items = []
    for t in todos:
        content = str(t.get("content") or t.get("Content") or "").strip()
        active = str(t.get("activeForm") or t.get("active_form") or "").strip()
        status = _norm_status(t.get("status"))
        if not content or not active:
            continue
        if status not in VALID:
            status = "pending"
        items.append({"content": content, "activeForm": active, "status": status})
    n = 0 if all(i["status"] == "completed" for i in items) else len(items)
    return ExecOutput(output=f"todos updated: {n} items", stderr="", exit_code=0, duration_seconds=0.0)


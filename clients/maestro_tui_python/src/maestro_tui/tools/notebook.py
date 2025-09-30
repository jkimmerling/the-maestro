from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional

from .fs import resolve_path
from .exec import ExecOutput


def notebook_edit(
    base_dir: str | Path,
    *,
    notebook_path: str,
    new_source: Optional[str] = None,
    cell_id: Optional[str | int] = None,
    cell_type: str = "code",
    edit_mode: str = "replace",
) -> ExecOutput:
    p = resolve_path(base_dir, notebook_path)
    if p.suffix != ".ipynb":
        raise ValueError("file must be .ipynb")
    if not p.exists():
        raise FileNotFoundError("notebook not found")
    nb = json.loads(p.read_text())
    if not isinstance(nb, dict) or "cells" not in nb:
        raise ValueError("invalid notebook json")
    cells = list(nb.get("cells") or [])

    mode = edit_mode or "replace"
    if mode not in ("replace", "insert", "delete"):
        raise ValueError("invalid edit_mode")

    if cell_id in (None, ""):
        if mode == "insert":
            idx = 0
        else:
            raise ValueError("cell_id required unless inserting")
    elif isinstance(cell_id, int):
        idx = max(0, min(cell_id, len(cells)))
    else:
        try:
            idx = int(cell_id)
            idx = max(0, min(idx, len(cells)))
        except Exception:
            # try by matching id
            idx = next((i for i, c in enumerate(cells) if c.get("id") == cell_id), -1)
            if idx < 0:
                raise ValueError("cell id not found")

    def new_cell(src: str, t: str, cid=None):
        if t == "markdown":
            return {"cell_type": "markdown", "id": cid, "source": src, "metadata": {}}
        return {
            "cell_type": "code",
            "id": cid,
            "source": src,
            "metadata": {},
            "execution_count": None,
            "outputs": [],
        }

    if mode == "delete":
        if 0 <= idx < len(cells):
            cells.pop(idx)
    elif mode == "insert":
        if new_source is None:
            raise ValueError("missing new_source")
        cells.insert(idx, new_cell(new_source, cell_type, None))
    else:
        if new_source is None:
            raise ValueError("missing new_source")
        if idx >= len(cells) or idx < 0:
            cells.insert(idx if idx >= 0 else 0, new_cell(new_source, cell_type, None))
        else:
            cell = dict(cells[idx])
            cell["source"] = new_source
            if cell.get("cell_type") == "code":
                cell["execution_count"] = None
                cell["outputs"] = []
            cells[idx] = cell

    nb["cells"] = cells
    p.write_text(json.dumps(nb, indent=2))
    return ExecOutput(output=f"notebook edited: {p.name}@{idx}", stderr="", exit_code=0, duration_seconds=0.0)


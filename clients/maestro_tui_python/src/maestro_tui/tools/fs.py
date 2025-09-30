from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Iterable, List, Tuple


class PathTraversalError(ValueError):
    pass


def _ensure_within(base: Path, target: Path) -> None:
    base_r = base.resolve()
    tgt_r = target.resolve()
    try:
        tgt_r.relative_to(base_r)
    except ValueError:
        raise PathTraversalError(f"path escapes base: {tgt_r} not under {base_r}")


def resolve_path(base_dir: str | Path, *parts: str) -> Path:
    base = Path(base_dir).resolve()
    p = base.joinpath(*parts)
    _ensure_within(base, p)
    return p


def write_file(base_dir: str | Path, rel_path: str, content: str, create_parents: bool = True) -> Path:
    p = resolve_path(base_dir, rel_path)
    if create_parents:
        p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return p


def read_file(base_dir: str | Path, rel_path: str) -> str:
    p = resolve_path(base_dir, rel_path)
    return p.read_text()


def read_many(base_dir: str | Path, rel_paths: Iterable[str]) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    for rp in rel_paths:
        out.append((rp, read_file(base_dir, rp)))
    return out


def edit_file(base_dir: str | Path, rel_path: str, find: str, replace: str, count: int | None = None) -> int:
    p = resolve_path(base_dir, rel_path)
    text = p.read_text()
    if count is None:
        new_text = text.replace(find, replace)
        n = text.count(find)
    else:
        new_text = replace.join(text.split(find, count))
        n = min(count, text.count(find))
    if new_text != text:
        p.write_text(new_text)
    return n


def multi_edit(base_dir: str | Path, ops: Iterable[dict]) -> List[Tuple[str, int]]:
    results: List[Tuple[str, int]] = []
    for op in ops:
        path = op.get("path")
        find = op.get("find", "")
        replace = op.get("replace", "")
        count = op.get("count")
        if not isinstance(path, str):
            raise ValueError("op.path required")
        n = edit_file(base_dir, path, find, replace, count)
        results.append((path, n))
    return results


def list_directory(base_dir: str | Path, rel_path: str = ".", recursive: bool = False) -> List[str]:
    root = resolve_path(base_dir, rel_path)
    items: List[str] = []
    if recursive:
        for p in root.rglob("*"):
            if p.is_file():
                items.append(str(p.relative_to(Path(base_dir).resolve())))
    else:
        for p in root.iterdir():
            items.append(str(p.relative_to(Path(base_dir).resolve())))
    return sorted(items)


def glob_paths(base_dir: str | Path, pattern: str) -> List[str]:
    base = Path(base_dir).resolve()
    matches = [str(p.relative_to(base)) for p in base.glob(pattern)]
    return sorted(matches)


def grep(base_dir: str | Path, pattern: str, files: Iterable[str] | None = None, flags: int = 0) -> List[Tuple[str, int, str]]:
    rx = re.compile(pattern, flags)
    results: List[Tuple[str, int, str]] = []
    if files is None:
        files = [str(p.relative_to(base_dir)) for p in Path(base_dir).resolve().rglob("*") if p.is_file()]
    for rel in files:
        text = read_file(base_dir, rel)
        for idx, line in enumerate(text.splitlines(), start=1):
            if rx.search(line):
                results.append((rel, idx, line))
    return results


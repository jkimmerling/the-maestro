from __future__ import annotations

from typing import List, Optional


def _norm_char(ch: str) -> str:
    if ch in {"–", "—", "−", "‑"}:
        return "-"
    if ch in {"‘", "’"}:
        return "'"
    if ch in {"“", "”"}:
        return '"'
    if ord(ch) == 0xA0:
        return " "
    return ch


def _normalize_line(s: str) -> str:
    s = s.strip()
    return "".join(_norm_char(c) for c in s)


def _find_exact(lines: List[str], pattern: List[str], start: int) -> Optional[int]:
    last = len(lines) - len(pattern)
    for off in range(max(last - start, 0) + 1):
        if lines[start + off : start + off + len(pattern)] == pattern:
            return start + off
    return None


def _find_rstrip(lines: List[str], pattern: List[str], start: int) -> Optional[int]:
    last = len(lines) - len(pattern)
    for off in range(max(last - start, 0) + 1):
        ok = True
        for a, b in zip(lines[start + off : start + off + len(pattern)], pattern):
            if a.rstrip() != b.rstrip():
                ok = False
                break
        if ok:
            return start + off
    return None


def _find_trim(lines: List[str], pattern: List[str], start: int) -> Optional[int]:
    last = len(lines) - len(pattern)
    for off in range(max(last - start, 0) + 1):
        ok = True
        for a, b in zip(lines[start + off : start + off + len(pattern)], pattern):
            if a.strip() != b.strip():
                ok = False
                break
        if ok:
            return start + off
    return None


def _find_normalized(lines: List[str], pattern: List[str], start: int) -> Optional[int]:
    last = len(lines) - len(pattern)
    pat = [_normalize_line(p) for p in pattern]
    for off in range(max(last - start, 0) + 1):
        seg = [_normalize_line(a) for a in lines[start + off : start + off + len(pattern)]]
        if seg == pat:
            return start + off
    return None


def seek_sequence(lines: List[str], pattern: List[str], start: int, eof: bool) -> Optional[int]:
    if pattern == []:
        return start
    if len(pattern) > len(lines):
        return None
    search_start = len(lines) - len(pattern) if eof and len(lines) >= len(pattern) else start
    return (
        _find_exact(lines, pattern, search_start)
        or _find_rstrip(lines, pattern, search_start)
        or _find_trim(lines, pattern, search_start)
        or _find_normalized(lines, pattern, search_start)
    )


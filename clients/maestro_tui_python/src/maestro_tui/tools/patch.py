from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple, Union

from .seek_sequence import seek_sequence


@dataclass
class Chunk:
    change_context: Optional[str]
    old_lines: List[str]
    new_lines: List[str]
    is_end_of_file: bool


Hunk = Union[Tuple[str, str, str], Tuple[str, str], Tuple[str, str, Optional[str], List[Chunk]]]


def _safe_join(base: Path, rel: str) -> Path:
    abs_p = (base / rel).resolve()
    if not str(abs_p).startswith(str(base.resolve())):
        raise ValueError("path escapes base")
    return abs_p


def parse_apply_patch(text: str) -> List[Hunk]:
    lines = text.splitlines()
    # allow heredoc wrappers
    if lines and lines[0] in ("<<EOF", "<<'EOF'", "<<\"EOF\"") and lines[-1] == "EOF":
        lines = lines[1:-1]
    if not lines or lines[0].strip() != "*** Begin Patch" or lines[-1].strip() != "*** End Patch":
        raise ValueError("invalid patch envelope")
    body = lines[1:-1]
    i = 0
    hunks: List[Hunk] = []
    while i < len(body):
        line = body[i].strip()
        if line == "":
            i += 1
            continue
        if line.startswith("*** Add File: "):
            path = line[len("*** Add File: ") :].strip()
            i += 1
            content_lines: List[str] = []
            while i < len(body) and not body[i].startswith("*** "):
                content_lines.append(body[i])
                i += 1
            hunks.append(("add", path, "\n".join(content_lines)))
            continue
        if line.startswith("*** Delete File: "):
            path = line[len("*** Delete File: ") :].strip()
            hunks.append(("delete", path))
            i += 1
            continue
        if line.startswith("*** Update File: "):
            path = line[len("*** Update File: ") :].strip()
            i += 1
            move_to: Optional[str] = None
            if i < len(body) and body[i].startswith("*** Move to: "):
                move_to = body[i][len("*** Move to: ") :].strip()
                i += 1
            chunks: List[Chunk] = []
            while i < len(body):
                if body[i].strip() == "":
                    i += 1
                    continue
                if body[i].startswith("*** "):
                    break
                # parse chunk
                change_context: Optional[str] = None
                if body[i].strip().startswith("@@"):
                    header = body[i].strip()
                    if header == "@@":
                        change_context = None
                    elif header.startswith("@@ "):
                        change_context = header[3:]
                    i += 1
                old_lines: List[str] = []
                new_lines: List[str] = []
                is_eof = False
                while i < len(body):
                    ln = body[i]
                    if ln.strip().startswith("*** ") or ln.strip().startswith("@@"):
                        break
                    if ln.strip() == "*** End of File":
                        is_eof = True
                        i += 1
                        break
                    if ln.startswith(" "):
                        val = ln[1:]
                        old_lines.append(val)
                        new_lines.append(val)
                    elif ln.startswith("-"):
                        old_lines.append(ln[1:])
                    elif ln.startswith("+"):
                        new_lines.append(ln[1:])
                    else:
                        # treat as context when no prefix
                        old_lines.append(ln)
                        new_lines.append(ln)
                    i += 1
                chunks.append(Chunk(change_context, old_lines, new_lines, is_eof))
            hunks.append(("update", path, move_to, chunks))
            continue
        # unknown line; skip
        i += 1
    return hunks


def apply_patch(text: str, base_dir: str | Path) -> List[str]:
    base = Path(base_dir).resolve()
    hunks = parse_apply_patch(text)
    changed: List[str] = []
    for h in hunks:
        tag = h[0]
        if tag == "add":
            _t, rel_path, contents = h  # type: ignore
            abs_p = _safe_join(base, rel_path)
            abs_p.parent.mkdir(parents=True, exist_ok=True)
            abs_p.write_text(contents)
            changed.append(str(abs_p))
        elif tag == "delete":
            _t, rel_path = h  # type: ignore
            abs_p = _safe_join(base, rel_path)
            if abs_p.exists():
                abs_p.unlink()
            changed.append(str(abs_p))
        elif tag == "update":
            _t, rel_path, move_to, chunks = h  # type: ignore
            src = _safe_join(base, rel_path)
            dst = _safe_join(base, move_to) if move_to else src
            if src != dst:
                dst.parent.mkdir(parents=True, exist_ok=True)
                if src.exists():
                    src.rename(dst)
            original = dst.read_text() if dst.exists() else ""
            new_content = _apply_chunks(original, chunks)
            dst.write_text(new_content)
            changed.append(str(dst))
        else:
            raise ValueError("unknown hunk type")
    return changed


def _apply_chunks(original: str, chunks: List[Chunk]) -> str:
    lines = original.split("\n")
    if lines == []:
        lines = [""]
    for ch in chunks:
        start_pos = 0
        if ch.change_context:
            idx = seek_sequence(lines, [ch.change_context], 0, False)
            start_pos = idx if idx is not None else 0
        pos = seek_sequence(lines[start_pos:], ch.old_lines, 0, ch.is_end_of_file)
        if pos is None:
            raise ValueError("context mismatch")
        i = start_pos + pos
        head = lines[:i]
        tail = lines[i + len(ch.old_lines) :]
        lines = head + ch.new_lines + tail
    return "\n".join(lines)


from __future__ import annotations

from typing import Iterable, List, Tuple
from .fs import read_file


def read(base_dir: str, rel_path: str) -> str:
    return read_file(base_dir, rel_path)


def read_many(base_dir: str, rel_paths: Iterable[str]) -> List[Tuple[str, str]]:
    return [(p, read_file(base_dir, p)) for p in rel_paths]


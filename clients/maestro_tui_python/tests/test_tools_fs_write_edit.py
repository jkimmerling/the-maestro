from pathlib import Path
import pytest

from maestro_tui.tools import (
    resolve_path,
    write_file,
    read_file,
    read_many,
    edit_file,
    multi_edit,
    list_directory,
    glob_paths,
    grep,
)
from maestro_tui.tools.fs import PathTraversalError


def test_write_read_edit_and_multi(tmp_path: Path):
    base = tmp_path
    p = write_file(base, "a/b.txt", "hello world")
    assert p.exists()
    assert read_file(base, "a/b.txt") == "hello world"

    n = edit_file(base, "a/b.txt", "world", "there")
    assert n == 1
    assert read_file(base, "a/b.txt") == "hello there"

    ops = [
        {"path": "a/b.txt", "find": "hello", "replace": "hi"},
        {"path": "a/c.txt", "find": "zzz", "replace": "yyy"},
    ]
    write_file(base, "a/c.txt", "zzz-1\nzzz-2\n")
    res = dict(multi_edit(base, ops))
    assert res["a/b.txt"] == 1
    assert res["a/c.txt"] == 2
    assert read_file(base, "a/b.txt").startswith("hi ")


def test_list_glob_grep(tmp_path: Path):
    base = tmp_path
    write_file(base, "x/one.txt", "alpha\nbeta\n")
    write_file(base, "x/two.md", "beta\ngamma\n")
    write_file(base, "x/sub/three.txt", "delta\n")

    top = list_directory(base, "x")
    assert any(s.endswith("one.txt") for s in top)

    rec = list_directory(base, "x", recursive=True)
    assert any(s.endswith("sub/three.txt") for s in rec)

    gl = glob_paths(base, "x/*.txt")
    assert any(s.endswith("one.txt") for s in gl)

    hits = grep(base, r"^beta$", ["x/one.txt", "x/two.md"])
    files = {f for f, _ln, _line in hits}
    assert files == {"x/one.txt", "x/two.md"}


def test_resolve_blocks_traversal(tmp_path: Path):
    base = tmp_path
    (base / "safe").mkdir()
    with pytest.raises(PathTraversalError):
        resolve_path(base / "safe", "../evil.txt")


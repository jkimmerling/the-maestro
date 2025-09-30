from pathlib import Path

from maestro_tui.tools.seek_sequence import seek_sequence
from maestro_tui.tools.patch import apply_patch


def test_seek_sequence_normalizations():
    lines = ["A—B", "smart ‘quotes’ here", "end"]
    pat1 = ["A-B"]
    pat2 = ["smart 'quotes' here"]
    assert seek_sequence(lines, pat1, 0, False) == 0
    assert seek_sequence(lines, pat2, 0, False) == 1


def test_apply_patch_add_update_delete(tmp_path: Path):
    base = tmp_path
    patch = """
*** Begin Patch
*** Add File: a.txt
hello
*** Update File: a.txt
@@
 hello
-world
+there
*** End of File
*** Delete File: missing.txt
*** End Patch
"""
    changed = apply_patch(patch, base)
    assert any(s.endswith("a.txt") for s in changed)
    assert (base / "a.txt").read_text().strip().endswith("there")


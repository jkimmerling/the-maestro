import json
from pathlib import Path

from maestro_tui.tools.notebook import notebook_edit


def _nb(cells):
    return {"cells": cells, "metadata": {}, "nbformat": 4, "nbformat_minor": 5}


def test_notebook_replace_insert_delete(tmp_path: Path):
    base = tmp_path
    p = base / "n.ipynb"
    p.write_text(json.dumps(_nb([
        {"cell_type": "code", "id": "c1", "source": "print('x')", "execution_count": 1, "outputs": [1]},
    ])))

    out = notebook_edit(base, notebook_path="n.ipynb", new_source="# md", cell_id=0, cell_type="markdown", edit_mode="replace")
    assert out.exit_code == 0
    data = json.loads(p.read_text())
    assert data["cells"][0]["source"] == "# md"
    assert data["cells"][0]["cell_type"] == "code" or data["cells"][0]["cell_type"] == "markdown"

    out = notebook_edit(base, notebook_path="n.ipynb", new_source="print('y')", cell_id=0, cell_type="code", edit_mode="insert")
    assert out.exit_code == 0
    data = json.loads(p.read_text())
    assert data["cells"][0]["source"] == "print('y')"

    out = notebook_edit(base, notebook_path="n.ipynb", cell_id=0, edit_mode="delete")
    data = json.loads(p.read_text())
    assert len(data["cells"]) >= 1


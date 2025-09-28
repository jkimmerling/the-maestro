from pathlib import Path
import json

from maestro_tui.config import load_config, ApiConfig


def test_load_config_ok(tmp_path: Path) -> None:
    cfg_dir = tmp_path / ".the_maestro"
    cfg_dir.mkdir()
    p = cfg_dir / "config.json"
    p.write_text(json.dumps({"api_host": "http://localhost:4000/", "api_key": "test"}))
    cfg = load_config(p)
    assert isinstance(cfg, ApiConfig)
    assert cfg.api_host == "http://localhost:4000"
    assert cfg.api_key == "test"


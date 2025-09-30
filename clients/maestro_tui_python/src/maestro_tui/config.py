from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json


CONFIG_PATH = Path.home() / ".the_maestro" / "config.json"


@dataclass
class ApiConfig:
    api_host: str
    api_key: str


def load_config(path: Path = CONFIG_PATH) -> ApiConfig:
    data = json.loads(path.read_text())
    host = data.get("api_host")
    key = data.get("api_key")
    if not host or not key:
        raise ValueError("api_host and api_key are required in config.json")
    return ApiConfig(api_host=host.rstrip("/"), api_key=key)


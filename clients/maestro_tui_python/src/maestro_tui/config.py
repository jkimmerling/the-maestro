from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
from typing import Optional


CONFIG_PATH = Path.home() / ".the_maestro" / "config.json"
SETTINGS_PATH = Path.home() / ".the_maestro" / "settings.json"


@dataclass
class ApiConfig:
    api_host: str
    api_key: str


@dataclass
class Settings:
    last_provider: Optional[str] = None
    last_auth_id: Optional[str] = None
    last_model: Optional[str] = None


def load_config(path: Path = CONFIG_PATH) -> ApiConfig:
    data = json.loads(path.read_text())
    host = data.get("api_host")
    key = data.get("api_key")
    if not host or not key:
        raise ValueError("api_host and api_key are required in config.json")
    return ApiConfig(api_host=host.rstrip("/"), api_key=key)


def load_settings(path: Path = SETTINGS_PATH) -> Settings:
    if not path.exists():
        return Settings()
    data = json.loads(path.read_text())
    return Settings(
        last_provider=data.get("last_provider"),
        last_auth_id=data.get("last_auth_id"),
        last_model=data.get("last_model"),
    )


def save_settings(settings: Settings, path: Path = SETTINGS_PATH) -> None:
    data = {
        "last_provider": settings.last_provider,
        "last_auth_id": settings.last_auth_id,
        "last_model": settings.last_model,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))


"""Application settings — secrets from .env, runtime prefs from config.json."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


# ---------------------------------------------------------------------------
# Env-based secrets (loaded from .env next to main.py or from real env vars)
# ---------------------------------------------------------------------------


class EnvSettings(BaseSettings):
    """Values that come exclusively from environment / .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    ha_url: str = "ws://homeassistant.local:8123/api/websocket"
    ha_token: str = ""
    lamp_entity_id: str = "light.iskarna"
    cors_origins: str = "http://192.168.88.130:5173"
    backend_host: str = "0.0.0.0"
    backend_port: int = 8765


# ---------------------------------------------------------------------------
# Persistent config.json (non-secret, user-adjustable from the frontend)
# ---------------------------------------------------------------------------


def _config_path() -> Path:
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        return Path(appdata) / "AmbIskarna" / "config.json"
    return Path.home() / ".amb-iskarna" / "config.json"


class CaptureConfig(BaseModel):
    display_id: int = 0
    full_screen: bool = True
    crop_x: int = 0
    crop_y: int = 0
    crop_w: int = 0
    crop_h: int = 0
    capture_fps: int = 15
    preview_fps: int = 5
    output_fps: int = 6
    smoothing: float = 0.3
    brightness_floor: int = 15
    min_color_change: int = 10


class AppSettings:
    """Composite settings object used throughout the app."""

    def __init__(self) -> None:
        self.env = EnvSettings()
        self.capture = self._load_capture()

    # -- persistence --------------------------------------------------------

    @staticmethod
    def _load_capture() -> CaptureConfig:
        path = _config_path()
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                return CaptureConfig.model_validate(data)
            except Exception:
                pass
        return CaptureConfig()

    def save_capture(self) -> None:
        path = _config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            self.capture.model_dump_json(indent=2),
            encoding="utf-8",
        )

    def update_capture(self, patch: dict) -> CaptureConfig:
        updated = self.capture.model_copy(update=patch)
        self.capture = updated
        self.save_capture()
        return updated


# Module-level singleton
settings = AppSettings()

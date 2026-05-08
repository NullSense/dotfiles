"""Application configuration. Frozen dataclass + env-var loading."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))


def _config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))


@dataclass(frozen=True, slots=True)
class AppConfig:
    """Runtime configuration. All fields settable via env vars (HYPRWHSPR_AI_*)."""

    # Daemon Unix socket — clients connect here.
    socket_path: Path

    # LM Studio HTTP base URL + the model id we route requests to.
    lmstudio_base_url: str
    lmstudio_model: str

    # NLLB Unix socket path — daemon talks to nllb-server here.
    nllb_socket_path: Path

    # User config files (vocab + favorite languages).
    vocabulary_path: Path
    languages_path: Path

    # Behavioral knobs.
    window_cache_ttl_s: float            # how long to trust hyprctl output
    lmstudio_state_cache_ttl_s: float    # how long to trust /api/v0/models state
    keepalive_threshold_s: float         # ping LM Studio only if idle longer than this
    keepalive_check_interval_s: float    # how often the keepalive task wakes

    # Hard timeout for any single LM Studio request (seconds).
    lmstudio_timeout_s: float

    # Hard timeout for any single NLLB request.
    nllb_timeout_s: float

    @classmethod
    def from_env(cls) -> "AppConfig":
        run = _runtime_dir()
        cfg = _config_dir()
        return cls(
            socket_path=Path(_env(
                "HYPRWHSPR_AI_SOCKET",
                str(run / "hyprwhspr-ai.sock"),
            )),
            lmstudio_base_url=_env("HYPRWHSPR_LMS_URL_BASE", "http://127.0.0.1:1234"),
            lmstudio_model=_env("HYPRWHSPR_LMS_MODEL", "google_gemma-4-e4b-it"),
            nllb_socket_path=Path(_env(
                "HYPRWHSPR_NLLB_SOCKET",
                str(run / "hyprwhspr-nllb.sock"),
            )),
            vocabulary_path=cfg / "hyprwhspr" / "vocabulary.txt",
            languages_path=cfg / "hyprwhspr" / "languages.txt",
            window_cache_ttl_s=float(_env("HYPRWHSPR_AI_WINDOW_TTL", "2.0")),
            lmstudio_state_cache_ttl_s=float(_env("HYPRWHSPR_AI_LMS_STATE_TTL", "30.0")),
            keepalive_threshold_s=float(_env("HYPRWHSPR_AI_KEEPALIVE_THRESHOLD", "3000")),  # 50min
            keepalive_check_interval_s=float(_env("HYPRWHSPR_AI_KEEPALIVE_INTERVAL", "300")),  # 5min
            lmstudio_timeout_s=float(_env("HYPRWHSPR_AI_LMS_TIMEOUT", "30.0")),
            nllb_timeout_s=float(_env("HYPRWHSPR_AI_NLLB_TIMEOUT", "30.0")),
        )

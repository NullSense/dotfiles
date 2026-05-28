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


def _state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))


def _envbool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() not in ("0", "false", "no", "off", "")


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

    # Surya OCR — optional engine for verbatim text extraction. Lives in
    # its own venv (~/.local/share/surya-ocr) because PyTorch ROCm pulls
    # ~5 GB of deps we don't want in the daemon's venv. Talked to via the
    # surya_ocr CLI binary.
    surya_bin: Path
    surya_gfx_override: str

    # Chandra OCR 2 — optional engine for high-quality OCR. Loaded into
    # LM Studio alongside Gemma; we just route the OCR request to its
    # model id instead of Gemma's. No separate venv, no subprocess.
    chandra_model_id: str

    # Qwen 3.6 35B-A3B — optional power-user OCR engine. Won our 14-case
    # bench on quality (0.974 recall) but requires a manual model swap
    # in LM Studio (won't coexist with Gemma+Chandra in 12 GB VRAM).
    # ~50-70 s per call due to MoE expert-CPU offload. The daemon
    # surfaces a clear error if the configured Qwen model isn't loaded.
    qwen_model_id: str

    # IBM Granite Vision 3.3-2b — small (1.55 GB Q4_K_M + 0.7 GB mmproj),
    # Apache 2.0, specialized for enterprise document understanding (tables,
    # charts, infographics, forms). Different model lineage from Chandra/Qwen
    # (LlavaNext + SigLIP2 + Granite 3.1) so likely fails on different
    # inputs — a useful complement. Coexists with Gemma+Chandra in 12 GB VRAM.
    # JIT-loaded by LM Studio (no manual model swap needed).
    granite_model_id: str

    # Transcript+rewrite logging (append-only JSONL, SHA-256 hash chain).
    transcript_log_enabled: bool
    transcript_log_path: Path
    transcript_log_hash_chain: bool
    transcript_log_full_prompt: bool

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
            lmstudio_timeout_s=float(_env("HYPRWHSPR_AI_LMS_TIMEOUT", "90.0")),
            nllb_timeout_s=float(_env("HYPRWHSPR_AI_NLLB_TIMEOUT", "30.0")),
            surya_bin=Path(_env(
                "HYPRWHSPR_AI_SURYA_BIN",
                str(Path.home() / ".local/share/surya-ocr/.venv/bin/surya_ocr"),
            )),
            surya_gfx_override=_env("HYPRWHSPR_AI_SURYA_GFX", "10.3.0"),
            chandra_model_id=_env("HYPRWHSPR_AI_CHANDRA_MODEL", "chandra-ocr-2"),
            qwen_model_id=_env("HYPRWHSPR_AI_QWEN_MODEL", "qwen_qwen3.6-35b-a3b"),
            granite_model_id=_env("HYPRWHSPR_AI_GRANITE_MODEL", "granite-vision-3.3-2b"),
            transcript_log_enabled=_envbool("HYPRWHSPR_AI_LOG", True),
            transcript_log_path=Path(_env(
                "HYPRWHSPR_AI_LOG_PATH",
                str(_state_dir() / "hyprwhspr-ai" / "transcripts.jsonl"),
            )),
            transcript_log_hash_chain=_envbool("HYPRWHSPR_AI_LOG_HASHCHAIN", True),
            transcript_log_full_prompt=_envbool("HYPRWHSPR_AI_LOG_FULL_PROMPT", False),
        )

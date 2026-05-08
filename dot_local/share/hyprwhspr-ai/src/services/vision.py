"""Vision service — Gemma 4 multimodal calls for screen Q&A.

Image capture (grim/slurp) is the daemon's responsibility too — keeps
the CLI client simple. The CLI just says "summarize_screen" and the
daemon handles screenshot + base64 + LM Studio call.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import os
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from ..lmstudio import LMStudioClient
from ..prompts import (
    VISION_EXPLAIN_REGION,
    VISION_OCR,
    VISION_SUMMARIZE_SCREEN,
)


log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class VisionResult:
    text: str
    took_ms: int


class VisionError(Exception):
    pass


class VisionService:
    def __init__(self, lms: LMStudioClient):
        self._lms = lms

    async def summarize_screen(self) -> VisionResult:
        """Capture the focused monitor only (multi-monitor stitching blows
        up vision token count) and ask Gemma to summarize."""
        img_path = await _capture_focused_monitor()
        try:
            return await self._call_with_image(img_path, VISION_SUMMARIZE_SCREEN)
        finally:
            _cleanup(img_path)

    async def explain_region(self) -> VisionResult:
        img_path = await _capture_region()
        if img_path is None:
            raise VisionError("region capture cancelled")
        try:
            return await self._call_with_image(img_path, VISION_EXPLAIN_REGION)
        finally:
            _cleanup(img_path)

    async def ask_region(self, question: str) -> VisionResult:
        if not question.strip():
            raise VisionError("empty question")
        img_path = await _capture_region()
        if img_path is None:
            raise VisionError("region capture cancelled")
        try:
            return await self._call_with_image(img_path, question)
        finally:
            _cleanup(img_path)

    async def ocr(self, image_path: Path) -> VisionResult:
        """Extract text from an arbitrary image file (used by translate-region)."""
        return await self._call_with_image(image_path, VISION_OCR)

    async def _call_with_image(self, image_path: Path, prompt: str) -> VisionResult:
        t0 = time.perf_counter()
        with image_path.open("rb") as f:
            data = f.read()
        b64 = base64.b64encode(data).decode("ascii")
        data_uri = f"data:image/png;base64,{b64}"
        text = await self._lms.chat_completion_with_image(
            system_prompt=None,
            user_text=prompt,
            image_b64_data_uri=data_uri,
        )
        return VisionResult(text=text.strip(), took_ms=int((time.perf_counter() - t0) * 1000))


# --- capture helpers --------------------------------------------------

async def _capture_focused_monitor() -> Path:
    """Run grim against the focused monitor only. Avoids the multi-monitor
    stitch that produces a 4K-ish image and slow vision inference."""
    if shutil.which("grim") is None:
        raise VisionError("grim not installed")
    monitor = await _focused_monitor_name()
    img = Path(_mktemp_png())
    args = ["grim"]
    if monitor:
        args.extend(["-o", monitor])
    args.append(str(img))
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    rc = await proc.wait()
    if rc != 0 or not img.exists() or img.stat().st_size == 0:
        raise VisionError("grim failed")
    return img


async def _capture_region() -> Optional[Path]:
    """slurp + grim. Returns None if user cancels (Esc in slurp)."""
    if shutil.which("grim") is None or shutil.which("slurp") is None:
        raise VisionError("grim or slurp not installed")
    proc = await asyncio.create_subprocess_exec(
        "slurp", "-d", "-b", "28282880", "-c", "fabd2fee", "-w", "2",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    out, _ = await proc.communicate()
    geom = (out or b"").decode("ascii").strip()
    if not geom:
        return None  # cancelled

    img = Path(_mktemp_png())
    proc = await asyncio.create_subprocess_exec(
        "grim", "-g", geom, str(img),
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
    )
    rc = await proc.wait()
    if rc != 0 or not img.exists() or img.stat().st_size == 0:
        raise VisionError("grim region capture failed")
    return img


async def _focused_monitor_name() -> str:
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return ""
    proc = await asyncio.create_subprocess_exec(
        "hyprctl", "monitors", "-j",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    out, _ = await proc.communicate()
    if proc.returncode != 0 or not out:
        return ""
    import json
    try:
        monitors = json.loads(out)
    except json.JSONDecodeError:
        return ""
    for m in monitors:
        if m.get("focused"):
            return m.get("name") or ""
    return monitors[0].get("name") if monitors else ""


def _mktemp_png() -> str:
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".png", prefix="hyprwhspr-vision-")
    os.close(fd)
    return path


def _cleanup(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass

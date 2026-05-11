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
    OCR_CHANDRA_FALLBACK,
    OCR_CHANDRA_PRIMARY,
    OCR_GRANITE,
    OCR_HYBRID_CLEANUP,
    OCR_QWEN,
    VISION_EXPLAIN_REGION,
    VISION_SUMMARIZE_SCREEN,
    ocr_prompt_for,
    vision_prompt_for,
)
from .surya import SuryaError, SuryaService


log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class VisionResult:
    text: str
    took_ms: int


class VisionError(Exception):
    pass


class VisionService:
    def __init__(
        self,
        lms: LMStudioClient,
        surya: Optional[SuryaService] = None,
        chandra_model_id: Optional[str] = None,
        qwen_model_id: Optional[str] = None,
        granite_model_id: Optional[str] = None,
    ):
        self._lms = lms
        self._surya = surya
        self._chandra_model_id = chandra_model_id
        self._qwen_model_id = qwen_model_id
        self._granite_model_id = granite_model_id

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

    async def ocr(
        self,
        image_path: Path,
        mode: str = "faithful",
        engine: str = "gemma",
    ) -> VisionResult:
        """Extract text from an image file.

        engine ∈ {gemma, surya, hybrid}:
          gemma  — pure Gemma vision. Fast (~1-2 s warm), good structural
                   interpretation, can confuse table rows on dense layouts.
          surya  — pure Surya. Slower (~10-15 s), word-perfect text, no
                   structure (lines flattened to reading order). Output
                   is plain joined text.
          hybrid — Surya extracts verbatim text + bbox positions, Gemma
                   reformats into proper markdown. Slowest (~15-25 s),
                   best on tables / multi-column.

        mode ∈ {faithful, plain}:
          Only applies to gemma/hybrid (surya output is always plain
          joined text). 'faithful' preserves markdown structure;
          'plain' strips formatting for translation pipelines.

        Uses temperature=0 for the LLM stages (greedy decoding) — higher
        temperatures invite pattern-completion hallucination.
        """
        if engine == "gemma":
            return await self._call_with_image(
                image_path, ocr_prompt_for(mode),
                temperature=0.0, max_tokens=4096,
            )
        if engine == "surya":
            return await self._ocr_surya(image_path)
        if engine == "hybrid":
            return await self._ocr_hybrid(image_path, mode=mode)
        if engine == "chandra":
            return await self._ocr_chandra(image_path)
        if engine == "qwen":
            return await self._ocr_qwen(image_path)
        if engine == "granite":
            return await self._ocr_granite(image_path)
        raise VisionError(f"unknown OCR engine: {engine!r}; valid: gemma, surya, hybrid, chandra, qwen, granite")

    async def ocr_region(
        self,
        mode: str = "faithful",
        engine: str = "gemma",
    ) -> VisionResult:
        """Capture a screen region (slurp + grim) then OCR.

        Same engine/mode semantics as ocr(). The capture is shared —
        we drag once and feed the same PNG to whichever pipeline.
        """
        # Validate args before slurp prompt so a typo doesn't waste a drag.
        if engine not in ("gemma", "surya", "hybrid", "chandra", "qwen", "granite"):
            raise VisionError(f"unknown OCR engine: {engine!r}")
        if engine in ("gemma", "hybrid"):
            ocr_prompt_for(mode)  # raises ValueError if bad
        if engine in ("surya", "hybrid") and self._surya is None:
            raise VisionError(
                "Surya is not configured (surya_bin missing); "
                "install at ~/.local/share/surya-ocr or use --engine gemma"
            )
        if engine == "chandra" and not self._chandra_model_id:
            raise VisionError(
                "Chandra is not configured (chandra_model_id empty); "
                "set HYPRWHSPR_AI_CHANDRA_MODEL or use a different engine"
            )
        if engine == "qwen" and not self._qwen_model_id:
            raise VisionError(
                "Qwen is not configured (qwen_model_id empty); "
                "set HYPRWHSPR_AI_QWEN_MODEL or use a different engine"
            )
        if engine == "granite" and not self._granite_model_id:
            raise VisionError(
                "Granite is not configured (granite_model_id empty); "
                "set HYPRWHSPR_AI_GRANITE_MODEL or use a different engine"
            )

        img = await _capture_region()
        if img is None:
            raise VisionError("region capture cancelled")
        try:
            return await self.ocr(img, mode=mode, engine=engine)
        finally:
            _cleanup(img)

    async def _ocr_surya(self, image_path: Path) -> VisionResult:
        """Surya-only OCR. Joined text in reading order, no structure."""
        if self._surya is None:
            raise VisionError("Surya is not configured")
        try:
            r = await self._surya.run(image_path)
        except SuryaError as e:
            raise VisionError(f"Surya failed: {e}") from e
        return VisionResult(text=SuryaService.joined_text(r.lines), took_ms=r.took_ms)

    async def _ocr_granite(self, image_path: Path) -> VisionResult:
        """OCR via IBM Granite Vision 3.3-2b — small (~1.55 GB Q4_K_M),
        Apache 2.0, specialized for enterprise document understanding.

        Coexists with Gemma + Chandra in 12 GB VRAM. LM Studio's JIT
        loading auto-loads it on first use; subsequent calls are warm.
        """
        if not self._granite_model_id:
            raise VisionError("Granite not configured")
        return await self._call_with_image(
            image_path, OCR_GRANITE,
            temperature=0.0, max_tokens=4096,
            model=self._granite_model_id,
        )

    async def _ocr_qwen(self, image_path: Path) -> VisionResult:
        """OCR via Qwen 3.6 35B-A3B — large general VLM, slowest engine
        (~50-70 s per call due to MoE expert-CPU offload) but highest
        quality on our 14-case bench (0.974 recall, never empty).

        Requires manual model swap in LM Studio: Qwen 35B Q5_K_M doesn't
        coexist with Gemma + Chandra in 12 GB VRAM. The daemon surfaces
        a clear error from LM Studio if the configured Qwen model isn't
        currently loaded.
        """
        if not self._qwen_model_id:
            raise VisionError("Qwen not configured")
        return await self._call_with_image(
            image_path, OCR_QWEN,
            temperature=0.0, max_tokens=4096,
            model=self._qwen_model_id,
        )

    async def _ocr_chandra(self, image_path: Path) -> VisionResult:
        """OCR via Chandra OCR 2 — purpose-built document OCR model loaded
        in LM Studio alongside Gemma. Same HTTP path as Gemma vision; we
        just override the model id so LM Studio routes to Chandra's
        weights instead.

        Chandra's GGUF is fine-tuned on Qwen 3.5 4B which retains the
        Qwen reasoning/thinking template. On certain inputs the model
        goes into thinking mode and dumps its actual response into a
        reasoning channel that LM Studio doesn't surface, leaving the
        main `content` field empty. The Qwen-canonical fix is the
        `/no_think` prompt prefix.

        BUT: empirically `/no_think` *breaks* other inputs where the
        model was using thinking productively (it produces coherent
        OCR output through the thinking process). There's no single
        prompt that works on all input types.

        Mitigation: try `/no_think OCR markdown` first (fast, deterministic).
        If the output is empty after parsing, retry with bare `OCR markdown`
        which lets the model think. Inputs that fail both modes are a
        genuine GGUF capability ceiling (e.g. heavily multi-script
        images — pick a different engine for those).
        """
        if not self._chandra_model_id:
            raise VisionError("Chandra not configured")
        from .chandra_parse import parse_chandra_to_markdown

        # Two-pass with empty-fallback: try the short /no_think prompt
        # first; if (and only if) it produces empty parsed output, retry
        # with the verbose markdown prompt. Bench-validated as the best
        # quality/latency tradeoff across our 14-case suite — same recall
        # as always-running-both (0.793 vs 0.794) at half the wall time.
        #
        # Why two prompts at all: Chandra GGUF is fine-tuned on Qwen 3.5
        # which retains thinking-mode behavior. /no_think disables that
        # reasoning step (works well on most inputs); the verbose prompt
        # works for the inputs where the model needed thinking to produce
        # output. Their coverage is partly disjoint — neither alone
        # works on everything. See:
        #   https://huggingface.co/prithivMLmods/chandra-ocr-2-GGUF/discussions/3
        raw1 = await self._call_with_image(
            image_path, OCR_CHANDRA_PRIMARY,
            temperature=0.0, max_tokens=4096,
            model=self._chandra_model_id,
        )
        parsed1 = parse_chandra_to_markdown(raw1.text)
        if parsed1:
            return VisionResult(text=parsed1, took_ms=raw1.took_ms)

        log.info("chandra: primary prompt produced empty; retrying with verbose fallback")
        raw2 = await self._call_with_image(
            image_path, OCR_CHANDRA_FALLBACK,
            temperature=0.0, max_tokens=4096,
            model=self._chandra_model_id,
        )
        parsed2 = parse_chandra_to_markdown(raw2.text)
        return VisionResult(
            text=parsed2,
            took_ms=raw1.took_ms + raw2.took_ms,
        )

    async def _ocr_hybrid(self, image_path: Path, mode: str = "faithful") -> VisionResult:
        """Surya verbatim text + Gemma layout cleanup → markdown."""
        if self._surya is None:
            raise VisionError("Surya is not configured")
        t0 = time.perf_counter()
        try:
            surya_result = await self._surya.run(image_path)
        except SuryaError as e:
            raise VisionError(f"Surya failed: {e}") from e
        positioned = SuryaService.positioned_text(surya_result.lines)
        # Gemma sees the image AND the OCR'd lines+positions. Its only job
        # is layout — it does NOT need to do character recognition since
        # Surya already nailed the text.
        user_text = (
            f"{OCR_HYBRID_CLEANUP}\n\n"
            f"OCR'd lines (verbatim text + pixel positions):\n\n{positioned}"
        )
        gemma_result = await self._call_with_image(
            image_path, user_text,
            temperature=0.0, max_tokens=4096,
        )
        # gemma_result.took_ms is just the Gemma stage; report the full
        # pipeline time for honesty.
        took_ms = int((time.perf_counter() - t0) * 1000)
        return VisionResult(text=gemma_result.text, took_ms=took_ms)

    async def analyze_file(self, image_path: Path, prompt: str) -> VisionResult:
        """Run an arbitrary prompt against an existing image file.

        Used by the post-capture menu flow: omarchy already saved a
        screenshot to disk, the user picks "Analyze: explain" or asks
        a custom question, and we send (file, prompt) to Gemma.
        """
        if not prompt.strip():
            raise VisionError("empty prompt")
        return await self._call_with_image(image_path, prompt)

    async def run_task(
        self,
        task: str,
        source: str,
        question: str = "",
        image_path: Optional[Path] = None,
    ) -> VisionResult:
        """Unified vision entry: task × source.

        task   ∈ {summarize, explain, ask}
        source ∈ {monitor, region, file}

        For source=file, image_path must be provided. For source=region,
        the user's slurp selection is captured here. For source=monitor,
        the focused monitor is captured. The daemon serializes via the
        usual asyncio lock inside LMStudioClient.
        """
        prompt = vision_prompt_for(task, question)
        if source == "monitor":
            img = await _capture_focused_monitor()
            try:
                return await self._call_with_image(img, prompt)
            finally:
                _cleanup(img)
        if source == "region":
            img = await _capture_region()
            if img is None:
                raise VisionError("region capture cancelled")
            try:
                return await self._call_with_image(img, prompt)
            finally:
                _cleanup(img)
        if source == "file":
            if image_path is None:
                raise VisionError("image_path required for file source")
            if not image_path.is_file():
                raise VisionError(f"image not found: {image_path}")
            return await self._call_with_image(image_path, prompt)
        raise VisionError(f"unknown source: {source!r}")

    async def _call_with_image(
        self,
        image_path: Path,
        prompt: str,
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
        model: str | None = None,
    ) -> VisionResult:
        """Send image + prompt to LM Studio.

        We read the PNG bytes verbatim — no resizing, no quality loss.
        Anything grim produced (full native resolution of monitor or
        slurp region) is what the VLM sees.

        model overrides the default LM Studio model id, used for routing
        OCR to Chandra while Gemma serves rewrite/summarize.
        """
        t0 = time.perf_counter()
        with image_path.open("rb") as f:
            data = f.read()
        b64 = base64.b64encode(data).decode("ascii")
        data_uri = f"data:image/png;base64,{b64}"
        kwargs: dict = {}
        if temperature is not None:
            kwargs["temperature"] = temperature
        if max_tokens is not None:
            kwargs["max_tokens"] = max_tokens
        if model is not None:
            kwargs["model"] = model
        text = await self._lms.chat_completion_with_image(
            system_prompt=None,
            user_text=prompt,
            image_b64_data_uri=data_uri,
            **kwargs,
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

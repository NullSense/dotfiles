"""Surya OCR — subprocess wrapper to the surya-ocr venv.

Surya runs in its own Python venv at ~/.local/share/surya-ocr because
PyTorch ROCm is ~5 GB of dependencies we don't want polluting the
daemon's venv. Talk to it via the surya_ocr CLI; read the JSON it writes.

Two integration points are useful:
  - SURYA-only mode: word-perfect text but no 2D structure (lines flattened
    into reading order). Best when you want raw text for piping into other
    tools.
  - HYBRID mode: Surya extracts verbatim text + bbox positions, then Gemma
    reformats into proper markdown (tables aligned, headings hierarchical,
    code fenced). Best for tables / multi-column / structured docs where
    Gemma alone confuses row alignment.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class SuryaLine:
    text: str
    x: float
    y: float
    x_max: float
    y_max: float
    confidence: float


@dataclass(frozen=True, slots=True)
class SuryaResult:
    lines: list[SuryaLine]
    took_ms: int


class SuryaError(Exception):
    pass


class SuryaService:
    """Async subprocess wrapper around the surya_ocr CLI.

    Each call spawns a fresh process which reloads models from cache —
    that's where the ~10–15 s warm cost comes from. A long-running Surya
    daemon would amortize this; out of scope for now.
    """

    def __init__(
        self,
        surya_bin: Path,
        gfx_override: str = "10.3.0",
        recognition_batch_size: int = 32,
    ):
        self._bin = surya_bin
        self._gfx = gfx_override
        self._batch = recognition_batch_size
        # Serialize Surya invocations — two concurrent surya_ocr processes
        # contend for GPU memory (Gemma is also resident) and end up
        # thrashing instead of finishing. Application-layer queueing.
        self._lock = asyncio.Lock()

    async def is_available(self) -> bool:
        """Cheap check — returns True if the surya_ocr binary exists and
        is executable. Doesn't actually run inference."""
        return self._bin.is_file() and os.access(self._bin, os.X_OK)

    async def run(self, image_path: Path) -> SuryaResult:
        """Run Surya text-detection + recognition on an image.

        Returns text lines sorted in reading order (top-to-bottom,
        left-to-right within a row).
        """
        if not await self.is_available():
            raise SuryaError(f"surya_ocr binary not found at {self._bin}")
        if not image_path.is_file():
            raise SuryaError(f"image not found: {image_path}")

        env = {
            **os.environ,
            "HSA_OVERRIDE_GFX_VERSION": self._gfx,
            "TORCH_DEVICE": "cuda",  # ROCm exposes itself as cuda in PyTorch
            "RECOGNITION_BATCH_SIZE": str(self._batch),
        }

        async with self._lock:
          with tempfile.TemporaryDirectory(prefix="surya-") as tmp:
            tmp_path = Path(tmp)
            stderr_log = tmp_path / "stderr.log"
            t0 = time.perf_counter()
            # We use a thread + plain subprocess.run instead of
            # asyncio.create_subprocess_exec. The asyncio version,
            # when called from inside a long-running event loop with
            # background tasks (httpx pool, keepalive, Unix socket
            # server), hangs unpredictably — the subprocess starts but
            # proc.wait() never resolves even though the child is
            # actively running. Switching to a worker thread sidesteps
            # asyncio subprocess plumbing entirely.
            try:
                rc, stderr_text = await asyncio.to_thread(
                    self._run_blocking,
                    str(image_path), str(tmp_path), env, stderr_log,
                )
            except Exception as e:
                raise SuryaError(f"surya subprocess failed to launch: {e}") from e
            took_ms = int((time.perf_counter() - t0) * 1000)
            if rc != 0:
                detail = stderr_text[:500] if stderr_text else "(no stderr)"
                raise SuryaError(f"surya_ocr exited {rc}: {detail}")

            # Surya writes <output_dir>/<image-stem>/results.json
            results_path = tmp_path / image_path.stem / "results.json"
            if not results_path.is_file():
                raise SuryaError(f"surya_ocr produced no results.json (looked in {results_path})")
            try:
                data = json.loads(results_path.read_text())
            except json.JSONDecodeError as e:
                raise SuryaError(f"surya_ocr produced malformed JSON: {e}") from e

            lines: list[SuryaLine] = []
            for _page_name, pages in data.items():
                for page in pages:
                    for line in page.get("text_lines", []):
                        poly = line.get("polygon", [])
                        if not poly:
                            continue
                        xs = [p[0] for p in poly]
                        ys = [p[1] for p in poly]
                        lines.append(SuryaLine(
                            text=line.get("text", ""),
                            x=min(xs),
                            y=min(ys),
                            x_max=max(xs),
                            y_max=max(ys),
                            confidence=float(line.get("confidence", 0.0)),
                        ))
            # Reading order: top-to-bottom primary, left-to-right secondary.
            lines.sort(key=lambda l: (l.y, l.x))
            return SuryaResult(lines=lines, took_ms=took_ms)

    def _run_blocking(
        self,
        image_path: str,
        output_dir: str,
        env: dict,
        stderr_log: Path,
    ) -> tuple[int, str]:
        """Synchronous subprocess invocation, runs in a worker thread.

        Returns (returncode, stderr_text). Stderr is captured because
        surya's tqdm output is small enough that pipe buffering isn't
        an issue in the synchronous case (the thread drains it via
        subprocess.run's communicate).
        """
        try:
            result = subprocess.run(
                [str(self._bin), image_path, "--output_dir", output_dir],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                check=False,
            )
        except FileNotFoundError as e:
            return 127, f"surya_ocr binary not found: {e}"
        return result.returncode, result.stderr.decode("utf-8", errors="replace")

    @staticmethod
    def joined_text(lines: list[SuryaLine]) -> str:
        """Cheap stitch: one line per detection in reading order, no formatting."""
        return "\n".join(l.text for l in lines)

    @staticmethod
    def positioned_text(lines: list[SuryaLine]) -> str:
        """Lines with bbox positions, suitable for feeding to a layout LLM.

        Format: `[y=<int> x=<int>-<int>]  <text>`
        Used by hybrid mode so Gemma has both the verbatim words AND the
        positions, and only has to do layout reasoning.
        """
        return "\n".join(
            f"[y={int(l.y)} x={int(l.x)}-{int(l.x_max)}]  {l.text}"
            for l in lines
        )

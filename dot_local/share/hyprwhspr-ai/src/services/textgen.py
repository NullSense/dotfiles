"""Text generation service — task-keyed LLM calls on raw text.

Used by the omarchy AI submenu's clipboard/file-text variants of
Summarize/Explain/Ask. Companion to VisionService (which handles the
image-based variants). Both share the same LMStudioClient instance,
so the daemon's serialization lock applies to both.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from ..lmstudio import LMStudioClient
from ..prompts import text_prompt_for


log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class TextGenResult:
    text: str
    took_ms: int


class TextGenError(Exception):
    pass


class TextGenService:
    """summarize / explain / ask on a chunk of plain text."""

    def __init__(self, lms: LMStudioClient):
        self._lms = lms

    async def run_task(self, task: str, text: str, question: str = "") -> TextGenResult:
        if not text.strip():
            raise TextGenError("empty text")
        try:
            system = text_prompt_for(task)
        except ValueError as e:
            raise TextGenError(str(e)) from e
        if task == "ask":
            if not question.strip():
                raise TextGenError("ask requires a question")
            user = f"Question: {question.strip()}\n\nText:\n{text}"
        else:
            user = text
        t0 = time.perf_counter()
        out = await self._lms.chat_completion(system_prompt=system, user_text=user)
        return TextGenResult(
            text=out.strip(),
            took_ms=int((time.perf_counter() - t0) * 1000),
        )

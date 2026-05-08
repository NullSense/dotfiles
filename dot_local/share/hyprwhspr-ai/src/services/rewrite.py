"""Rewrite service — orchestrates the dictation post-processing flow.

  raw text ──► detect window ──► classify context ──► load vocab
            ──► build prompt ──► LM Studio chat completion
            ──► strip residual <think> + code fences ──► output text
"""

from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass

from ..lmstudio import LMStudioClient
from ..prompts import build_rewrite_prompt, wrap_rewrite_input
from ..vocab import VocabRepository
from ..window import Window, WindowProvider, classify, markdown_dialect


log = logging.getLogger(__name__)


_THINK_BLOCK = re.compile(r"<think>.*?</think>", flags=re.DOTALL)
_CODE_FENCE_OPEN = re.compile(r"\A```[a-zA-Z]*\n?")
_CODE_FENCE_CLOSE = re.compile(r"\n?```\Z")


@dataclass(frozen=True, slots=True)
class RewriteResult:
    text: str
    context: str
    took_ms: int
    fell_back: bool      # True if LM Studio failed and we returned raw input


class RewriteService:
    def __init__(
        self,
        lms: LMStudioClient,
        vocab: VocabRepository,
        window_provider: WindowProvider,
    ):
        self._lms = lms
        self._vocab = vocab
        self._windows = window_provider

    async def rewrite(self, raw_text: str) -> RewriteResult:
        text = raw_text.strip()
        if not text:
            return RewriteResult(text="", context="generic", took_ms=0, fell_back=False)

        t0 = time.perf_counter()
        window = await self._windows.current()
        ctx = classify(window)
        dialect = markdown_dialect(window, ctx)
        vocab_block = self._vocab.block()
        sys_prompt = build_rewrite_prompt(window, ctx, dialect, vocab_block)
        user_block = wrap_rewrite_input(text)

        try:
            out = await self._lms.chat_completion(
                system_prompt=sys_prompt,
                user_text=user_block,
                max_tokens=512,
                temperature=0.7,
                top_p=0.95,
                presence_penalty=None,
            )
        except Exception as e:
            log.warning("LM Studio rewrite failed; passing through raw: %s", e)
            return RewriteResult(
                text=raw_text, context=ctx.value,
                took_ms=int((time.perf_counter() - t0) * 1000),
                fell_back=True,
            )

        cleaned = _clean_output(out)
        if not cleaned.strip():
            return RewriteResult(
                text=raw_text, context=ctx.value,
                took_ms=int((time.perf_counter() - t0) * 1000),
                fell_back=True,
            )
        return RewriteResult(
            text=cleaned,
            context=ctx.value,
            took_ms=int((time.perf_counter() - t0) * 1000),
            fell_back=False,
        )


def _clean_output(text: str) -> str:
    """Strip residual <think> blocks (Qwen prefill leakage), surrounding
    code fences, surrounding ASCII or smart quotes, and leading/trailing
    whitespace."""
    text = _THINK_BLOCK.sub("", text)
    text = _CODE_FENCE_OPEN.sub("", text)
    text = _CODE_FENCE_CLOSE.sub("", text)
    text = text.strip()
    # Strip surrounding quotes if present.
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ('"', "'", "`"):
        text = text[1:-1]
    return text.strip()

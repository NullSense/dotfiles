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
from ..prompts import PROMPT_BUILDER_VERSION, build_rewrite_prompt, wrap_rewrite_input
from ..transcript_log import TranscriptLogger, edit_ratio, sha256_text
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
        logger: TranscriptLogger,
        *,
        log_full_prompt: bool = False,
    ):
        self._lms = lms
        self._vocab = vocab
        self._windows = window_provider
        self._log = logger
        self._log_full_prompt = log_full_prompt

    async def rewrite(
        self,
        raw_text: str,
        *,
        asr_model: str = "",
        asr_backend: str = "",
    ) -> RewriteResult:
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

        fell_back = False
        try:
            out = await self._lms.chat_completion(
                system_prompt=sys_prompt,
                user_text=user_block,
                max_tokens=512,
                temperature=0.7,
                top_p=0.95,
                presence_penalty=None,
            )
            cleaned = _clean_output(out)
            if cleaned.strip():
                final_text = cleaned
            else:
                final_text, fell_back = raw_text, True
        except Exception as e:
            log.warning("LM Studio rewrite failed; passing through raw: %s", e)
            final_text, fell_back = raw_text, True

        took_ms = int((time.perf_counter() - t0) * 1000)
        self._emit_log(
            raw=text, output=final_text, ctx=ctx, dialect=dialect, window=window,
            vocab_block=vocab_block, sys_prompt=sys_prompt, took_ms=took_ms,
            fell_back=fell_back, asr_model=asr_model, asr_backend=asr_backend,
        )
        return RewriteResult(
            text=final_text, context=ctx.value, took_ms=took_ms, fell_back=fell_back,
        )

    def _emit_log(
        self, *, raw, output, ctx, dialect, window, vocab_block, sys_prompt,
        took_ms, fell_back, asr_model, asr_backend,
    ) -> None:
        if not self._log.enabled:
            return
        try:
            model = self._lms.model_id
            family = "qwen" if any(p in model.lower() for p in ("qwen", "qwq")) else "other"
            vocab_sha = self._log.store_vocab(vocab_block)
            payload = {
                "input": raw,
                "output": output,
                "changed": output.strip() != raw.strip(),
                "fell_back": fell_back,
                "took_ms": took_ms,
                "context": ctx.value,
                "window": {"class": window.cls, "title": window.title},
                "md_dialect": dialect.value,
                "asr": {"model": asr_model, "backend": asr_backend},
                "llm": {
                    "model": model, "family": family,
                    "temperature": 0.7, "top_p": 0.95, "max_tokens": 512,
                },
                "prompt_builder_version": PROMPT_BUILDER_VERSION,
                "prompt_sha256": sha256_text(sys_prompt),
                "vocab_sha256": vocab_sha,
                "metrics": {
                    "in_chars": len(raw), "in_words": len(raw.split()),
                    "out_chars": len(output), "out_words": len(output.split()),
                    "edit_ratio": edit_ratio(raw, output),
                },
            }
            if self._log_full_prompt:
                payload["prompt"] = sys_prompt
            self._log.log(payload)
        except Exception as e:  # logging must never break dictation
            log.warning("transcript log failed: %s", e)


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

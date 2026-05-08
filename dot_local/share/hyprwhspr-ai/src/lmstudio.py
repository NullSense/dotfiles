"""LM Studio HTTP client.

Wraps the OpenAI-compatible endpoint at /v1/chat/completions plus the
LM-Studio-specific /api/v0/models for state introspection. One
httpx.AsyncClient per daemon lifetime — TCP keep-alive across requests.

Handles two model families:

  - Qwen 3.x (with embedded thinking template) → /v1/completions
    with a hand-built ChatML prompt that prefills `<think></think>` to
    bypass thinking. (LM Studio drops chat_template_kwargs, so we close
    thinking ourselves.)
  - Everything else (Gemma, Llama, Mistral, Phi, Granite, Qwen3.6 instruct)
    → /v1/chat/completions with native system role.

The legacy bash hooks performed this same family-detection. We carry
the logic forward verbatim so behavior matches.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass
from typing import Any

import httpx


log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class LMStudioState:
    state: str       # "loaded" | "not-loaded" | "loading" | "unavailable"
    model_id: str    # the resolved model id
    cached_at: float


class LMStudioClient:
    """Async HTTP client for LM Studio.

    Holds:
      - One pooled httpx.AsyncClient (HTTP/2 + keep-alive).
      - One asyncio.Lock that ALL outbound /v1/chat/completions requests
        acquire before posting. Application-layer serialization that
        doesn't depend on the LM Studio backend's numParallelSessions
        setting (defense-in-depth).
      - State cache (unix-time-keyed, TTL configurable) so concurrent
        callers don't all hammer /api/v0/models.

    Two main entry points:
      chat_completion(...)  → text from /v1/chat/completions
      chat_completion_with_image(...)  → vision-enabled call
      ping_keepalive()      → tiny inference to refresh LM Studio's TTL counter
    """

    def __init__(
        self,
        base_url: str,
        model_id: str,
        timeout_s: float,
        state_cache_ttl_s: float,
    ):
        self._base_url = base_url.rstrip("/")
        self._model_id = model_id
        self._timeout = httpx.Timeout(timeout_s, connect=2.0)
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout,
            limits=httpx.Limits(max_keepalive_connections=4, max_connections=8),
        )
        self._lock = asyncio.Lock()
        self._state_cache: LMStudioState | None = None
        self._state_cache_ttl_s = state_cache_ttl_s
        # Tracks last successful chat_completion / ping_keepalive — used by
        # the keepalive scheduler to decide when to fire a touch.
        self._last_activity: float = 0.0

    @property
    def model_id(self) -> str:
        return self._model_id

    @property
    def last_activity(self) -> float:
        """Unix-time of the last successful LM Studio call, or 0 if never."""
        return self._last_activity

    async def aclose(self) -> None:
        await self._client.aclose()

    # --- state -----------------------------------------------------------

    async def state(self, force_refresh: bool = False) -> LMStudioState:
        """Return current model state, possibly cached.

        ``state`` is one of:
          "loaded"      — model is in memory and serving
          "not-loaded"  — model registered but not loaded
          "loading"     — currently loading
          "unavailable" — LM Studio unreachable or model not registered
        """
        now = time.time()
        if not force_refresh and self._state_cache is not None:
            age = now - self._state_cache.cached_at
            if age < self._state_cache_ttl_s and self._state_cache.state == "loaded":
                return self._state_cache

        try:
            r = await self._client.get("/api/v0/models", timeout=2.0)
            r.raise_for_status()
            data = r.json()
            entry = next(
                (m for m in data.get("data", []) if m.get("id") == self._model_id),
                None,
            )
            if entry is None:
                state = "unavailable"
            else:
                state = entry.get("state", "unavailable")
        except (httpx.RequestError, httpx.HTTPStatusError, ValueError) as e:
            log.warning("state() failed: %s", e)
            state = "unavailable"

        st = LMStudioState(state=state, model_id=self._model_id, cached_at=now)
        self._state_cache = st
        return st

    def _invalidate_state_cache(self) -> None:
        """Drop the cached state — call after operations that change it."""
        self._state_cache = None

    # --- chat completions ------------------------------------------------

    def _is_qwen_family(self) -> bool:
        return any(p in self._model_id.lower() for p in ("qwen", "qwq"))

    async def chat_completion(
        self,
        system_prompt: str,
        user_text: str,
        *,
        max_tokens: int = 512,
        temperature: float = 0.7,
        top_p: float = 0.95,
        presence_penalty: float | None = None,
    ) -> str:
        """Send a text-only chat completion. Routes to /v1/completions for
        Qwen (with thinking-prefill) or /v1/chat/completions otherwise.
        """
        async with self._lock:
            if self._is_qwen_family():
                text = await self._qwen_completion(
                    system_prompt, user_text,
                    max_tokens=max_tokens, temperature=temperature,
                    top_p=0.8, presence_penalty=1.5,
                )
            else:
                text = await self._chat_completion(
                    system_prompt, user_text,
                    max_tokens=max_tokens, temperature=temperature,
                    top_p=top_p, presence_penalty=presence_penalty,
                )
            self._last_activity = time.time()
            return text

    async def chat_completion_with_image(
        self,
        system_prompt: str | None,
        user_text: str,
        image_b64_data_uri: str,
        *,
        max_tokens: int = 768,
        temperature: float = 0.5,
    ) -> str:
        """Vision-enabled chat completion (Gemma 4 multimodal). Image must be
        a base64 data URI like 'data:image/png;base64,...'.
        """
        messages: list[dict[str, Any]] = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": image_b64_data_uri}},
                {"type": "text", "text": user_text},
            ],
        })
        body = {
            "model": self._model_id,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
        }
        async with self._lock:
            r = await self._client.post("/v1/chat/completions", json=body)
            r.raise_for_status()
            text = r.json()["choices"][0]["message"]["content"] or ""
            self._last_activity = time.time()
            return text

    async def _chat_completion(
        self,
        system_prompt: str,
        user_text: str,
        *,
        max_tokens: int,
        temperature: float,
        top_p: float,
        presence_penalty: float | None,
    ) -> str:
        body: dict[str, Any] = {
            "model": self._model_id,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_text},
            ],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "top_p": top_p,
            "stream": False,
        }
        if presence_penalty is not None:
            body["presence_penalty"] = presence_penalty
        r = await self._client.post("/v1/chat/completions", json=body)
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"] or ""

    async def _qwen_completion(
        self,
        system_prompt: str,
        user_text: str,
        *,
        max_tokens: int,
        temperature: float,
        top_p: float,
        presence_penalty: float,
    ) -> str:
        prompt = (
            f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
            f"<|im_start|>user\n{user_text}<|im_end|>\n"
            f"<|im_start|>assistant\n<think>\n\n</think>\n\n"
        )
        body = {
            "model": self._model_id,
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "top_p": top_p,
            "presence_penalty": presence_penalty,
            "stop": ["<|im_end|>", "<|im_start|>"],
            "stream": False,
        }
        r = await self._client.post("/v1/completions", json=body)
        r.raise_for_status()
        return r.json()["choices"][0]["text"] or ""

    # --- keepalive --------------------------------------------------------

    async def ping_keepalive(self) -> bool:
        """Tiny 1-token chat completion to refresh LM Studio's JIT TTL.

        Returns True if it succeeded (model is loaded + responsive).
        Cheap: ~50ms warm. Skipped at the caller layer if last_activity
        is recent enough.
        """
        body = {
            "model": self._model_id,
            "messages": [{"role": "user", "content": "hi"}],
            "max_tokens": 1,
            "stream": False,
        }
        try:
            async with self._lock:
                r = await self._client.post("/v1/chat/completions", json=body)
                r.raise_for_status()
                self._last_activity = time.time()
                return True
        except (httpx.RequestError, httpx.HTTPStatusError):
            return False

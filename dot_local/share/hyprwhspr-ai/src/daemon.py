"""hyprwhspr-ai daemon — asyncio Unix socket server.

Owns long-lived state (HTTP client, vocab cache, window cache) and
serves rewrite/vision/translate/ping requests as line-delimited JSON.

Lifecycle:
  systemd starts daemon → daemon binds Unix socket
  client connects → sends one JSON line → reads one JSON line → disconnects
  daemon idles between requests, internal keepalive task pings LM Studio
  if no activity for ~50min (well under LM Studio's 60min TTL)

Failure modes are graceful: any exception inside a handler is caught
and returned as {"ok": false, "error": "...", "detail": "..."} so the
CLI client has structured information to report. The daemon never
crashes on a bad request — only on initialization errors.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
from pathlib import Path
from typing import Any

from .config import AppConfig
from .lmstudio import LMStudioClient
from .nllb import NLLBClient
from .services.rewrite import RewriteService
from .services.translate import TranslateError, TranslateService
from .services.vision import VisionError, VisionService
from .vocab import VocabRepository
from .window import WindowProvider


log = logging.getLogger("hyprwhspr-ai")


class Daemon:
    """Wires services together and serves on a Unix socket."""

    def __init__(self, config: AppConfig):
        self._config = config
        self._lms = LMStudioClient(
            base_url=config.lmstudio_base_url,
            model_id=config.lmstudio_model,
            timeout_s=config.lmstudio_timeout_s,
            state_cache_ttl_s=config.lmstudio_state_cache_ttl_s,
        )
        self._nllb = NLLBClient(
            socket_path=config.nllb_socket_path,
            timeout_s=config.nllb_timeout_s,
        )
        self._vocab = VocabRepository(path=config.vocabulary_path)
        self._windows = WindowProvider(cache_ttl_s=config.window_cache_ttl_s)
        self._rewrite = RewriteService(self._lms, self._vocab, self._windows)
        self._vision = VisionService(self._lms)
        self._translate = TranslateService(self._nllb, self._vision)
        self._server: asyncio.base_events.Server | None = None
        self._keepalive_task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()

    async def serve(self) -> None:
        sock = self._config.socket_path
        # Cleanly remove a stale socket from a prior crash.
        try:
            sock.unlink()
        except FileNotFoundError:
            pass
        sock.parent.mkdir(parents=True, exist_ok=True)
        self._server = await asyncio.start_unix_server(
            self._handle_client, path=str(sock),
        )
        os.chmod(sock, 0o600)
        log.info("listening on %s", sock)

        # Background keepalive task — pings LM Studio if idle long enough
        # to refresh its JIT TTL (60min). We use 50min as the threshold
        # so there's always a 10min safety margin.
        self._keepalive_task = asyncio.create_task(self._keepalive_loop())

        # Run until SIGTERM/SIGINT.
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self._stop_event.set)
        try:
            await self._stop_event.wait()
        finally:
            log.info("shutting down")
            if self._keepalive_task:
                self._keepalive_task.cancel()
                try:
                    await self._keepalive_task
                except asyncio.CancelledError:
                    pass
            self._server.close()
            await self._server.wait_closed()
            await self._lms.aclose()
            try:
                sock.unlink()
            except FileNotFoundError:
                pass

    async def _keepalive_loop(self) -> None:
        """Ping LM Studio when activity has been idle longer than the
        threshold. Skips when activity is recent (the user is dictating
        often enough to keep TTL warm naturally)."""
        import time as _time
        while True:
            await asyncio.sleep(self._config.keepalive_check_interval_s)
            now = _time.time()
            last = self._lms.last_activity
            if last == 0.0 or (now - last) > self._config.keepalive_threshold_s:
                ok = await self._lms.ping_keepalive()
                log.info("keepalive ping ok=%s", ok)

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        try:
            line = await reader.readline()
            if not line:
                return
            try:
                req = json.loads(line.decode("utf-8"))
            except json.JSONDecodeError as e:
                resp = {"ok": False, "error": "bad_json", "detail": str(e)}
            else:
                resp = await self._dispatch(req)
            writer.write((json.dumps(resp) + "\n").encode("utf-8"))
            await writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            pass
        except Exception as e:  # last-ditch — never crash the server
            log.exception("handler crashed: %s", e)
            try:
                writer.write((json.dumps({
                    "ok": False, "error": "handler_crash", "detail": str(e),
                }) + "\n").encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    async def _dispatch(self, req: dict[str, Any]) -> dict[str, Any]:
        op = req.get("op")
        try:
            if op == "ping":
                return await self._op_ping()
            if op == "rewrite":
                return await self._op_rewrite(req)
            if op == "vision":
                return await self._op_vision(req)
            if op == "translate":
                return await self._op_translate(req)
            if op == "translate-region":
                return await self._op_translate_region(req)
            if op == "ocr":
                return await self._op_ocr(req)
            return {"ok": False, "error": "unknown_op", "detail": f"op={op!r}"}
        except Exception as e:
            log.exception("op=%s failed", op)
            return {"ok": False, "error": "op_failed", "detail": str(e)}

    # --- handlers ---------------------------------------------------------

    async def _op_ping(self) -> dict[str, Any]:
        st = await self._lms.state()
        return {
            "ok": True,
            "lmstudio": st.state,
            "model": st.model_id,
            "nllb_resident": self._config.nllb_socket_path.exists(),
        }

    async def _op_rewrite(self, req: dict[str, Any]) -> dict[str, Any]:
        text = req.get("text", "")
        result = await self._rewrite.rewrite(text)
        return {
            "ok": not result.fell_back,
            "text": result.text,
            "context": result.context,
            "took_ms": result.took_ms,
            "fell_back": result.fell_back,
        }

    async def _op_vision(self, req: dict[str, Any]) -> dict[str, Any]:
        subop = req.get("subop")
        try:
            if subop == "summarize_screen":
                r = await self._vision.summarize_screen()
            elif subop == "explain_region":
                r = await self._vision.explain_region()
            elif subop == "ask_region":
                r = await self._vision.ask_region(req.get("question", ""))
            else:
                return {"ok": False, "error": "unknown_subop", "detail": f"subop={subop!r}"}
        except VisionError as e:
            return {"ok": False, "error": "vision_failed", "detail": str(e)}
        return {"ok": True, "text": r.text, "took_ms": r.took_ms}

    async def _op_translate(self, req: dict[str, Any]) -> dict[str, Any]:
        text = req.get("text", "")
        target = req.get("target", "")
        source = req.get("source", "eng_Latn")
        try:
            r = await self._translate.translate(text, target, source)
        except TranslateError as e:
            return {"ok": False, "error": "translate_failed", "detail": str(e)}
        return {
            "ok": True, "text": r.text, "via": r.via,
            "target_code": r.target_code, "took_ms": r.took_ms,
        }

    async def _op_translate_region(self, req: dict[str, Any]) -> dict[str, Any]:
        target = req.get("target", "")
        source = req.get("source", "eng_Latn")
        try:
            r = await self._translate.translate_region(target, source)
        except TranslateError as e:
            return {"ok": False, "error": "translate_failed", "detail": str(e)}
        return {
            "ok": True, "text": r.text, "via": r.via,
            "target_code": r.target_code, "took_ms": r.took_ms,
        }

    async def _op_ocr(self, req: dict[str, Any]) -> dict[str, Any]:
        path = Path(req.get("image_path", ""))
        if not path.is_file():
            return {"ok": False, "error": "image_not_found", "detail": str(path)}
        try:
            r = await self._vision.ocr(path)
        except VisionError as e:
            return {"ok": False, "error": "vision_failed", "detail": str(e)}
        return {"ok": True, "text": r.text, "took_ms": r.took_ms}


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )
    config = AppConfig.from_env()
    asyncio.run(Daemon(config).serve())


if __name__ == "__main__":
    main()

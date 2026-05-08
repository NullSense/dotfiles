"""NLLB translation client.

Talks to the existing nllb-server.py over its Unix socket. Protocol:
one JSON line per request, one JSON line per response.

Auto-starts the systemd user unit (`hyprwhspr-nllb.service`) if the
socket isn't there. Server idle-exits after 3 minutes; next call
restarts it transparently.
"""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
import subprocess
from pathlib import Path


log = logging.getLogger(__name__)


class NLLBUnavailable(Exception):
    """Raised when the NLLB server cannot be reached."""


class NLLBClient:
    """Async client for the local NLLB translation server."""

    def __init__(self, socket_path: Path, timeout_s: float):
        self._socket_path = socket_path
        self._timeout_s = timeout_s

    async def translate(self, text: str, src: str, tgt: str) -> str:
        """Translate ``text`` from ``src`` to ``tgt`` (NLLB BCP-47 codes)."""
        if not text.strip():
            return ""
        # First attempt: connect to existing server.
        # On any connection failure (server idle-exited, stale socket,
        # never started) — start the server and retry once. The NLLB
        # server's idle-exit (3min) leaves the socket file on disk; we
        # can't tell "missing" from "stale" without trying to connect.
        try:
            return await self._translate_once(text, src, tgt)
        except NLLBUnavailable:
            await self._start_server_and_wait()
            return await self._translate_once(text, src, tgt)

    async def _translate_once(self, text: str, src: str, tgt: str) -> str:
        req = json.dumps({"text": text, "src": src, "tgt": tgt}) + "\n"
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_unix_connection(str(self._socket_path)),
                timeout=2.0,
            )
        except (FileNotFoundError, ConnectionRefusedError, OSError,
                asyncio.TimeoutError) as e:
            raise NLLBUnavailable(f"connect failed: {e}") from e

        try:
            writer.write(req.encode())
            await writer.drain()
            writer.write_eof()
            buf = await asyncio.wait_for(reader.read(), timeout=self._timeout_s)
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

        if not buf:
            raise NLLBUnavailable("empty response from NLLB server")
        resp = json.loads(buf.decode("utf-8").strip())
        if "error" in resp:
            raise NLLBUnavailable(f"server error: {resp['error']}")
        return resp.get("translation", "")

    async def _start_server_and_wait(self) -> None:
        """Start the systemd NLLB unit and wait for it to be ready
        (i.e. listening on the socket)."""
        await self._start_server()
        # Poll for "actually listening" — try connecting every 500ms
        # for up to 30s. We can't trust socket-exists; idle-exit leaves
        # a stale file. We probe by attempting a connection.
        for _ in range(60):
            try:
                _, w = await asyncio.wait_for(
                    asyncio.open_unix_connection(str(self._socket_path)),
                    timeout=0.5,
                )
                w.close()
                try:
                    await w.wait_closed()
                except Exception:
                    pass
                return  # connected — server is up
            except (FileNotFoundError, ConnectionRefusedError, OSError,
                    asyncio.TimeoutError):
                await asyncio.sleep(0.5)
        raise NLLBUnavailable("NLLB server did not start within 30s")

    @staticmethod
    async def _start_server() -> None:
        """Fire-and-forget systemctl start; don't wait for completion."""
        if shutil.which("systemctl") is None:
            log.error("systemctl not found — cannot start NLLB server")
            return
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "--user", "start", "hyprwhspr-nllb.service",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        await proc.wait()

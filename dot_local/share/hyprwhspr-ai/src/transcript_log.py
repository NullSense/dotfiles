"""Append-only JSONL transcript+rewrite logger with a SHA-256 hash chain.

One record per dictation rewrite. Designed to never break dictation: the
daemon wraps the call in try/except. The daemon is single-process asyncio
and `log()` performs no awaits, so it runs atomically within the event loop —
appends cannot interleave, so no lock and no fsync are needed (NDJSON
tolerates a lost trailing line on crash).
"""

from __future__ import annotations

import hashlib
import json
import os
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any


GENESIS_HASH = "0" * 64
SCHEMA_VERSION = 1
_RECOVERY_TAIL_BYTES = 64 * 1024


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def edit_ratio(a: str, b: str) -> float:
    """1 - similarity ratio. 0.0 == identical, ~1.0 == completely different."""
    return round(1.0 - SequenceMatcher(None, a, b).ratio(), 4)


def _canonical(d: dict[str, Any]) -> str:
    return json.dumps(d, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _now_iso() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _recover_tail(path: Path) -> tuple[int, str]:
    """Return (last_seq, last_hash) from an existing log, or (0, GENESIS).

    Reads only the trailing chunk and walks backward to the last valid JSON
    record, tolerating a corrupt trailing partial line from a crash.
    """
    try:
        size = path.stat().st_size
    except FileNotFoundError:
        return 0, GENESIS_HASH
    if size == 0:
        return 0, GENESIS_HASH
    start = max(0, size - _RECOVERY_TAIL_BYTES)
    with open(path, "rb") as f:
        f.seek(start)
        chunk = f.read()
    for raw in reversed(chunk.split(b"\n")):
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError:
            continue
        seq = rec.get("seq")
        if isinstance(seq, int):
            return seq, rec.get("hash", GENESIS_HASH)
    return 0, GENESIS_HASH


def _missing_trailing_newline(path: Path) -> bool:
    """True if the file exists, is non-empty, and does not end with a newline.

    A crash mid-write leaves a partial line with no trailing newline. We must
    start the next record on a fresh line so O_APPEND can't fuse a new record
    onto the corrupt fragment.
    """
    try:
        with open(path, "rb") as f:
            try:
                f.seek(-1, os.SEEK_END)
            except OSError:
                return False  # empty file
            return f.read(1) != b"\n"
    except FileNotFoundError:
        return False


@dataclass
class VerifyResult:
    ok: bool
    count: int
    error: str | None = None
    bad_seq: int | None = None


def verify_chain(path: Path) -> VerifyResult:
    """Recompute the hash chain end-to-end. Reports the first break.

    A missing file is OK (0 records). Records without a `hash` field
    (hash chain disabled when written) are counted but not integrity-checked.
    """
    prev = GENESIS_HASH
    count = 0
    try:
        f = open(path, "r", encoding="utf-8")
    except FileNotFoundError:
        return VerifyResult(ok=True, count=0)
    with f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                return VerifyResult(ok=False, count=count,
                                    error=f"malformed JSON at line {lineno}")
            stored = rec.pop("hash", None)
            if stored is None:
                count += 1
                continue
            if rec.get("prev_hash") != prev:
                return VerifyResult(ok=False, count=count,
                                    error=f"prev_hash break at seq {rec.get('seq')}",
                                    bad_seq=rec.get("seq"))
            if sha256_text(_canonical(rec)) != stored:
                return VerifyResult(ok=False, count=count,
                                    error=f"hash mismatch at seq {rec.get('seq')}",
                                    bad_seq=rec.get("seq"))
            prev = stored
            count += 1
    return VerifyResult(ok=True, count=count)


def reconstruct_prompt(record: dict[str, Any], vocab_dir: Path) -> str:
    """Rebuild the exact system prompt for a record from its stored fields.

    Reconstructs via the current `prompts.build_rewrite_prompt`. Compare
    `sha256_text(result)` against `record['prompt_sha256']` to confirm
    byte-identity (matches only when `prompt_builder_version` equals the
    current builder).
    """
    from .prompts import build_rewrite_prompt
    from .window import Context, MarkdownDialect, Window

    win = Window(cls=record["window"]["class"], title=record["window"]["title"])
    ctx = Context(record["context"])
    dialect = MarkdownDialect(record["md_dialect"])
    vocab_sha = record.get("vocab_sha256", "")
    vocab_block = ""
    if vocab_sha:
        p = vocab_dir / f"{vocab_sha}.txt"
        if p.exists():
            vocab_block = p.read_text(encoding="utf-8")
    return build_rewrite_prompt(win, ctx, dialect, vocab_block)


class TranscriptLogger:
    """Append-only chained-JSONL logger + content-addressed vocab store."""

    def __init__(
        self,
        *,
        path: Path,
        enabled: bool,
        hash_chain: bool,
        session_id: str | None = None,
    ):
        self._path = Path(path)
        self._enabled = enabled
        self._hash_chain = hash_chain
        self._session_id = session_id or uuid.uuid4().hex
        self._vocab_dir = self._path.parent / "vocab"
        self._seq = 0
        self._prev_hash = GENESIS_HASH
        self._recovered = False
        self._needs_newline = False

    @property
    def enabled(self) -> bool:
        return self._enabled

    @property
    def vocab_dir(self) -> Path:
        return self._vocab_dir

    def _ensure_recovered(self) -> None:
        if self._recovered:
            return
        self._seq, self._prev_hash = _recover_tail(self._path)
        self._needs_newline = _missing_trailing_newline(self._path)
        self._recovered = True

    def store_vocab(self, vocab_block: str) -> str:
        """Write the vocab block once under vocab/<sha256>.txt; return the sha."""
        h = sha256_text(vocab_block)
        if not self._enabled:
            return h
        self._vocab_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        dest = self._vocab_dir / f"{h}.txt"
        if not dest.exists():
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                os.write(fd, vocab_block.encode("utf-8"))
            finally:
                os.close(fd)
        return h

    def log(self, payload: dict[str, Any]) -> None:
        """Append one record. No-op when disabled. Never awaits."""
        if not self._enabled:
            return
        self._ensure_recovered()
        self._path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        next_seq = self._seq + 1
        record: dict[str, Any] = {
            "schema": SCHEMA_VERSION,
            "seq": next_seq,
            "id": uuid.uuid4().hex,
            "ts": _now_iso(),
            "session_id": self._session_id,
            **payload,
        }
        next_hash = self._prev_hash
        if self._hash_chain:
            record["prev_hash"] = self._prev_hash
            next_hash = sha256_text(_canonical(record))
            record["hash"] = next_hash
        line = json.dumps(record, ensure_ascii=False) + "\n"
        if self._needs_newline:
            line = "\n" + line
        fd = os.open(self._path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
        # Commit in-memory chain state only after a successful append, so a
        # failed write can't desync seq/prev_hash from the file.
        self._seq = next_seq
        self._prev_hash = next_hash
        self._needs_newline = False

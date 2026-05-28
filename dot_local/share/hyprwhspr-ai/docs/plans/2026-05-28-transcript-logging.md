# Transcript + Rewrite Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every dictation→rewrite as a fine-tune-grade, hash-chained JSONL record in the `hyprwhspr-ai` daemon, without ever breaking dictation.

**Architecture:** A new stdlib-only module `src/transcript_log.py` provides a generic append-only chained-JSONL logger plus a content-addressed vocab store, chain verifier, and prompt reconstructor. `RewriteService` gains the logger as a dependency and emits one record per rewrite (fail-soft). `daemon.py`/`client.py` forward ASR provenance from upstream. Config is env-driven, on by default.

**Tech Stack:** Python 3.12, stdlib (`hashlib`, `json`, `os`, `uuid`, `datetime`, `difflib`), pytest + pytest-asyncio. Working directory: `~/.local/share/chezmoi/dot_local/share/hyprwhspr-ai/`. Tests: `uv run pytest`.

**IMPORTANT — do not commit.** Per the user's global instructions, do NOT run `git commit`. Leave changes staged/unstaged for the user to review. (The plan omits commit steps deliberately.) Also do NOT run `chezmoi apply`; deployment is handled separately.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `src/transcript_log.py` | Create | Generic chained-JSONL appender, vocab CAS, `verify_chain`, `reconstruct_prompt`, public helpers (`sha256_text`, `edit_ratio`). Stdlib only. |
| `tests/test_transcript_log.py` | Create | Unit tests for the logger, chain, recovery, CAS, verify, reconstruct. |
| `src/config.py` | Modify | Add 4 transcript-log config fields + `_state_dir`/`_envbool` helpers. |
| `src/prompts.py` | Modify | Add `PROMPT_BUILDER_VERSION` constant. |
| `src/services/rewrite.py` | Modify | Accept logger + `log_full_prompt`; `rewrite()` gains `asr_model`/`asr_backend` kwargs; emit one record (fail-soft). |
| `src/daemon.py` | Modify | Construct `TranscriptLogger`, inject into `RewriteService`, forward ASR fields in `_op_rewrite`. |
| `src/client.py` | Modify | `cmd_rewrite` forwards `HYPRWHSPR_MODEL`/`HYPRWHSPR_BACKEND`; add `log verify` subcommand. |
| `tests/test_rewrite_log.py` | Create | RewriteService logging behavior with fakes. |

**Task dependency:** Task 1 (module) and Task 2 (config + version) are independent and can run in parallel. Task 3 (wiring + tests) depends on both.

---

## Task 1: `transcript_log.py` module + tests

**Files:**
- Create: `src/transcript_log.py`
- Test: `tests/test_transcript_log.py`

- [ ] **Step 1: Write the module**

Create `src/transcript_log.py` with exactly this content:

```python
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
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._seq += 1
        record: dict[str, Any] = {
            "schema": SCHEMA_VERSION,
            "seq": self._seq,
            "id": uuid.uuid4().hex,
            "ts": _now_iso(),
            "session_id": self._session_id,
            **payload,
        }
        if self._hash_chain:
            record["prev_hash"] = self._prev_hash
            h = sha256_text(_canonical(record))
            record["hash"] = h
            self._prev_hash = h
        line = json.dumps(record, ensure_ascii=False) + "\n"
        fd = os.open(self._path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
```

- [ ] **Step 2: Write the failing tests**

Create `tests/test_transcript_log.py` with exactly this content:

```python
import json
import os
import stat

import pytest

from src.transcript_log import (
    GENESIS_HASH,
    TranscriptLogger,
    edit_ratio,
    reconstruct_prompt,
    sha256_text,
    verify_chain,
)


def _read_records(path):
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]


def _logger(tmp_path, **kw):
    kw.setdefault("enabled", True)
    kw.setdefault("hash_chain", True)
    return TranscriptLogger(path=tmp_path / "transcripts.jsonl", **kw)


def test_disabled_logger_writes_nothing(tmp_path):
    lg = _logger(tmp_path, enabled=False)
    lg.log({"input": "hi", "output": "Hi."})
    assert not (tmp_path / "transcripts.jsonl").exists()


def test_log_appends_one_valid_line_with_core_fields(tmp_path):
    lg = _logger(tmp_path)
    lg.log({"input": "hi", "output": "Hi."})
    recs = _read_records(tmp_path / "transcripts.jsonl")
    assert len(recs) == 1
    r = recs[0]
    for k in ("schema", "seq", "id", "ts", "session_id", "prev_hash", "hash"):
        assert k in r
    assert r["input"] == "hi" and r["output"] == "Hi."


def test_seq_increments_monotonically(tmp_path):
    lg = _logger(tmp_path)
    for i in range(3):
        lg.log({"input": str(i), "output": str(i)})
    seqs = [r["seq"] for r in _read_records(tmp_path / "transcripts.jsonl")]
    assert seqs == [1, 2, 3]


def test_hash_chain_links_and_verifies(tmp_path):
    lg = _logger(tmp_path)
    lg.log({"input": "a", "output": "A"})
    lg.log({"input": "b", "output": "B"})
    recs = _read_records(tmp_path / "transcripts.jsonl")
    assert recs[0]["prev_hash"] == GENESIS_HASH
    assert recs[1]["prev_hash"] == recs[0]["hash"]
    res = verify_chain(tmp_path / "transcripts.jsonl")
    assert res.ok and res.count == 2


def test_verify_detects_tampering(tmp_path):
    lg = _logger(tmp_path)
    lg.log({"input": "a", "output": "A"})
    lg.log({"input": "b", "output": "B"})
    p = tmp_path / "transcripts.jsonl"
    lines = p.read_text().splitlines()
    rec = json.loads(lines[0])
    rec["output"] = "TAMPERED"
    lines[0] = json.dumps(rec)
    p.write_text("\n".join(lines) + "\n")
    res = verify_chain(p)
    assert not res.ok
    assert res.bad_seq == 1


def test_recovery_continues_seq_and_chain(tmp_path):
    lg1 = _logger(tmp_path)
    lg1.log({"input": "a", "output": "A"})
    lg1.log({"input": "b", "output": "B"})
    lg2 = _logger(tmp_path)  # fresh instance, same file
    lg2.log({"input": "c", "output": "C"})
    recs = _read_records(tmp_path / "transcripts.jsonl")
    assert [r["seq"] for r in recs] == [1, 2, 3]
    assert recs[2]["prev_hash"] == recs[1]["hash"]
    assert verify_chain(tmp_path / "transcripts.jsonl").ok


def test_recovery_tolerates_corrupt_trailing_line(tmp_path):
    lg1 = _logger(tmp_path)
    lg1.log({"input": "a", "output": "A"})
    p = tmp_path / "transcripts.jsonl"
    with open(p, "a") as f:
        f.write('{"seq": 2, "input": "partial')  # truncated, no newline
    lg2 = _logger(tmp_path)
    lg2.log({"input": "b", "output": "B"})
    # The good record after the corrupt line continues from seq 1.
    good = [json.loads(l) for l in p.read_text().splitlines()
            if l.strip() and l.strip().endswith("}")]
    seqs = [r["seq"] for r in good if "hash" in r]
    assert seqs[-1] == 2  # resumed from last valid (seq 1) -> 2


def test_file_perms_are_0600(tmp_path):
    lg = _logger(tmp_path)
    lg.log({"input": "a", "output": "A"})
    mode = stat.S_IMODE(os.stat(tmp_path / "transcripts.jsonl").st_mode)
    assert mode == 0o600


def test_vocab_cas_writes_once(tmp_path):
    lg = _logger(tmp_path)
    block = "[Known vocabulary]\nFoo, Bar."
    h1 = lg.store_vocab(block)
    h2 = lg.store_vocab(block)
    assert h1 == h2 == sha256_text(block)
    dest = lg.vocab_dir / f"{h1}.txt"
    assert dest.read_text() == block
    assert sum(1 for _ in lg.vocab_dir.iterdir()) == 1


def test_edit_ratio_bounds():
    assert edit_ratio("same", "same") == 0.0
    assert edit_ratio("abc", "xyz") == 1.0


def test_reconstruct_prompt_roundtrips(tmp_path):
    # build_rewrite_prompt is deterministic; storing the vocab block + fields
    # must reproduce a prompt whose sha matches what we record.
    from src.prompts import build_rewrite_prompt
    from src.window import Context, MarkdownDialect, Window

    lg = _logger(tmp_path)
    win = Window(cls="org.wezfurlong.wezterm", title="claude")
    ctx = Context.AGENT_CLI
    dialect = MarkdownDialect.NONE
    vocab_block = "[Known vocabulary]\nCortiq, kubectl."
    sys_prompt = build_rewrite_prompt(win, ctx, dialect, vocab_block)
    vocab_sha = lg.store_vocab(vocab_block)
    record = {
        "window": {"class": win.cls, "title": win.title},
        "context": ctx.value,
        "md_dialect": dialect.value,
        "vocab_sha256": vocab_sha,
        "prompt_sha256": sha256_text(sys_prompt),
    }
    rebuilt = reconstruct_prompt(record, lg.vocab_dir)
    assert sha256_text(rebuilt) == record["prompt_sha256"]
```

- [ ] **Step 3: Run the tests, expect PASS**

Run: `cd ~/.local/share/chezmoi/dot_local/share/hyprwhspr-ai && uv run pytest tests/test_transcript_log.py -v`
Expected: all tests PASS. (The module in Step 1 is written to satisfy them.)

If `test_reconstruct_prompt_roundtrips` fails because `build_rewrite_prompt`'s signature differs from `(window, ctx, dialect, vocab_block)`, STOP and report — do not guess. Read `src/prompts.py` and `src/services/rewrite.py:54-59` to confirm the call signature, then align.

---

## Task 2: Config fields + prompt builder version (parallel with Task 1)

**Files:**
- Modify: `src/config.py`
- Modify: `src/prompts.py`

- [ ] **Step 1: Add the version constant to `prompts.py`**

Near the top of `src/prompts.py` (after imports, before the first function), add:

```python
# Bump whenever the rewrite prompt-building logic changes. Recorded per log
# record so a historical prompt can be reconstructed with the right builder.
PROMPT_BUILDER_VERSION = 1
```

- [ ] **Step 2: Add helpers + fields to `config.py`**

In `src/config.py`, add these module-level helpers after the existing `_config_dir` function (around line 20):

```python
def _state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))


def _envbool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() not in ("0", "false", "no", "off", "")
```

Add these fields to the `AppConfig` dataclass (after the existing `granite_model_id` field, before `from_env`):

```python
    # Transcript+rewrite logging (append-only JSONL, SHA-256 hash chain).
    transcript_log_enabled: bool
    transcript_log_path: Path
    transcript_log_hash_chain: bool
    transcript_log_full_prompt: bool
```

In `from_env`, add these to the `cls(...)` constructor call (after `granite_model_id=...`):

```python
            transcript_log_enabled=_envbool("HYPRWHSPR_AI_LOG", True),
            transcript_log_path=Path(_env(
                "HYPRWHSPR_AI_LOG_PATH",
                str(_state_dir() / "hyprwhspr-ai" / "transcripts.jsonl"),
            )),
            transcript_log_hash_chain=_envbool("HYPRWHSPR_AI_LOG_HASHCHAIN", True),
            transcript_log_full_prompt=_envbool("HYPRWHSPR_AI_LOG_FULL_PROMPT", False),
```

- [ ] **Step 3: Smoke-test config loads**

Run: `cd ~/.local/share/chezmoi/dot_local/share/hyprwhspr-ai && uv run python -c "from src.config import AppConfig; c=AppConfig.from_env(); print(c.transcript_log_enabled, c.transcript_log_path)"`
Expected: prints `True <home>/.local/state/hyprwhspr-ai/transcripts.jsonl`

Run the existing config/full suite to confirm no regression:
Run: `uv run pytest -q`
Expected: existing tests still PASS (new logging not wired yet).

---

## Task 3: Wire logging into the rewrite path + CLI + tests (depends on 1 & 2)

**Files:**
- Modify: `src/services/rewrite.py`
- Modify: `src/daemon.py:65` (RewriteService construction) and `src/daemon.py:210-219` (`_op_rewrite`)
- Modify: `src/client.py` (`cmd_rewrite` + new `log` subcommand)
- Test: `tests/test_rewrite_log.py`

- [ ] **Step 1: Update `RewriteService` (`src/services/rewrite.py`)**

Update the imports block to add the logger + helpers + version:

```python
from ..prompts import PROMPT_BUILDER_VERSION, build_rewrite_prompt, wrap_rewrite_input
from ..transcript_log import TranscriptLogger, edit_ratio, sha256_text
from ..vocab import VocabRepository
from ..window import Window, WindowProvider, classify, markdown_dialect
```

Replace the `__init__` to accept the logger:

```python
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
```

Replace the `rewrite` method body with a single-return form that logs once:

```python
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
```

Note: `Window` is imported only for type clarity; keep the existing `Window` import if already present, otherwise this import line covers it.

- [ ] **Step 2: Wire the daemon (`src/daemon.py`)**

Add the import near the other service imports (top of file):

```python
from .transcript_log import TranscriptLogger
```

In `Daemon.__init__`, immediately before the `self._rewrite = RewriteService(...)` line (currently `daemon.py:65`), construct the logger and pass it in:

```python
        self._transcript_log = TranscriptLogger(
            path=config.transcript_log_path,
            enabled=config.transcript_log_enabled,
            hash_chain=config.transcript_log_hash_chain,
        )
        self._rewrite = RewriteService(
            self._lms, self._vocab, self._windows,
            self._transcript_log,
            log_full_prompt=config.transcript_log_full_prompt,
        )
```

Replace `_op_rewrite` (currently `daemon.py:210-219`) so it forwards ASR provenance:

```python
    async def _op_rewrite(self, req: dict[str, Any]) -> dict[str, Any]:
        text = req.get("text", "")
        result = await self._rewrite.rewrite(
            text,
            asr_model=req.get("asr_model", ""),
            asr_backend=req.get("asr_backend", ""),
        )
        return {
            "ok": not result.fell_back,
            "text": result.text,
            "context": result.context,
            "took_ms": result.took_ms,
            "fell_back": result.fell_back,
        }
```

- [ ] **Step 3: Update the client (`src/client.py`)**

Replace `cmd_rewrite` (currently `client.py:69-77`) to forward the ASR env vars:

```python
def cmd_rewrite(args: argparse.Namespace) -> int:
    text = args.text if args.text else sys.stdin.read()
    req: dict[str, Any] = {"op": "rewrite", "text": text}
    asr_model = os.environ.get("HYPRWHSPR_MODEL")
    asr_backend = os.environ.get("HYPRWHSPR_BACKEND")
    if asr_model:
        req["asr_model"] = asr_model
    if asr_backend:
        req["asr_backend"] = asr_backend
    resp = _send(req)
    out = resp.get("text", "")
    if out:
        sys.stdout.write(out)
    return 0 if resp.get("ok") else 1
```

Add a `cmd_log` handler (runs locally, no daemon socket needed) after `cmd_text_task`:

```python
def cmd_log(args: argparse.Namespace) -> int:
    from .config import AppConfig
    from .transcript_log import verify_chain

    cfg = AppConfig.from_env()
    if args.log_cmd == "verify":
        res = verify_chain(cfg.transcript_log_path)
        if res.ok:
            print(f"OK: {res.count} records, chain intact")
            return 0
        print(f"FAIL: {res.error} (after {res.count} good records)", file=sys.stderr)
        return 1
    print(f"unknown log subcommand: {args.log_cmd}", file=sys.stderr)
    return 2
```

Register the subparser in `main()` (after the `text-task` parser block, before `args = p.parse_args(argv)`):

```python
    sp = sub.add_parser("log", help="inspect the transcript log")
    log_sub = sp.add_subparsers(dest="log_cmd", required=True)
    log_sub.add_parser("verify", help="verify the hash chain integrity")
    sp.set_defaults(fn=cmd_log)
```

- [ ] **Step 4: Write the RewriteService logging tests**

Create `tests/test_rewrite_log.py` with exactly this content:

```python
import json

import pytest

from src.services.rewrite import RewriteResult, RewriteService
from src.transcript_log import TranscriptLogger
from src.window import Window


class FakeLMS:
    def __init__(self, reply="Rewritten.", boom=False):
        self._reply = reply
        self._boom = boom
        self.model_id = "google_gemma-4-e4b-it"

    async def chat_completion(self, **kwargs):
        if self._boom:
            raise RuntimeError("LM Studio down")
        return self._reply


class FakeVocab:
    def block(self):
        return ""


class FakeWindows:
    def __init__(self, win):
        self._win = win

    async def current(self, force_refresh=False):
        return self._win


def _service(tmp_path, lms, *, enabled=True):
    logger = TranscriptLogger(
        path=tmp_path / "transcripts.jsonl", enabled=enabled, hash_chain=True,
    )
    win = Window(cls="org.wezfurlong.wezterm", title="claude")
    return RewriteService(lms, FakeVocab(), FakeWindows(win), logger), tmp_path / "transcripts.jsonl"


def _records(path):
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]


@pytest.mark.asyncio
async def test_logs_one_record_with_io_and_context(tmp_path):
    svc, path = _service(tmp_path, FakeLMS(reply="Let's refactor."))
    res = await svc.rewrite("lets refactor", asr_model="parakeet", asr_backend="onnx-asr")
    assert res.text == "Let's refactor."
    recs = _records(path)
    assert len(recs) == 1
    r = recs[0]
    assert r["input"] == "lets refactor"
    assert r["output"] == "Let's refactor."
    assert r["context"] == "agent-cli"
    assert r["asr"] == {"model": "parakeet", "backend": "onnx-asr"}
    assert r["changed"] is True


@pytest.mark.asyncio
async def test_logs_fell_back_on_lms_failure(tmp_path):
    svc, path = _service(tmp_path, FakeLMS(boom=True))
    res = await svc.rewrite("hello there")
    assert res.fell_back is True
    recs = _records(path)
    assert len(recs) == 1
    assert recs[0]["fell_back"] is True


@pytest.mark.asyncio
async def test_empty_input_logs_nothing(tmp_path):
    svc, path = _service(tmp_path, FakeLMS())
    res = await svc.rewrite("   ")
    assert res.text == ""
    assert not path.exists()


@pytest.mark.asyncio
async def test_disabled_logger_skips_logging(tmp_path):
    svc, path = _service(tmp_path, FakeLMS(), enabled=False)
    await svc.rewrite("hello")
    assert not path.exists()
```

- [ ] **Step 5: Run the full suite**

Run: `cd ~/.local/share/chezmoi/dot_local/share/hyprwhspr-ai && uv run pytest -v`
Expected: ALL tests pass (existing + `test_transcript_log.py` + `test_rewrite_log.py`).

If an existing test constructs `RewriteService(...)` with the old 3-arg signature, it will now fail. Search for such call sites (`grep -rn "RewriteService(" src tests`) and update them to pass a `TranscriptLogger` (use a disabled one in tests: `TranscriptLogger(path=tmp_path/'x.jsonl', enabled=False, hash_chain=False)`). Report any you change.

- [ ] **Step 6: Manual smoke test (no daemon required)**

Run:
```bash
cd ~/.local/share/chezmoi/dot_local/share/hyprwhspr-ai
HYPRWHSPR_AI_LOG_PATH=/tmp/claude/tlog.jsonl uv run python -c "
import asyncio
from src.transcript_log import TranscriptLogger, verify_chain
from pathlib import Path
p = Path('/tmp/claude/tlog.jsonl')
lg = TranscriptLogger(path=p, enabled=True, hash_chain=True)
lg.log({'input':'a','output':'A','context':'generic'})
lg.log({'input':'b','output':'B','context':'generic'})
print(verify_chain(p))
print(p.read_text())
"
```
Expected: `VerifyResult(ok=True, count=2, ...)` and two JSON lines with linked `prev_hash`/`hash`.

---

## Self-Review (completed by plan author)

**Spec coverage:** JSONL append-only (Task 1) ✓; rewrites-only chokepoint (Task 3) ✓; on-by-default + env toggle (Task 2 `_envbool` default True) ✓; SHA-256 hash chain + verify (Task 1) ✓; 0600 + local (Task 1 `os.open` mode) ✓; window title included (Task 3 payload) ✓; ASR provenance forwarding (Task 3 client/daemon) ✓; full schema fields (Task 3 payload) ✓; prompt reconstruction + vocab CAS + builder version (Tasks 1 & 2) ✓; full-prompt escape hatch (Task 3 `log_full_prompt`) ✓; config fields (Task 2) ✓; tests (Tasks 1 & 3) ✓. Retention + non-rewrite ops correctly excluded.

**Type consistency:** `TranscriptLogger(path=, enabled=, hash_chain=, session_id=)`, `.log(payload)`, `.store_vocab(block)->str`, `.enabled`, `.vocab_dir`; `verify_chain(path)->VerifyResult(ok,count,error,bad_seq)`; `reconstruct_prompt(record, vocab_dir)->str`; `sha256_text`, `edit_ratio` — all used consistently across tasks. `RewriteService.__init__(lms, vocab, window_provider, logger, *, log_full_prompt=False)` matches the daemon construction in Task 3 Step 2.

**Placeholder scan:** none — all steps contain literal code/commands.

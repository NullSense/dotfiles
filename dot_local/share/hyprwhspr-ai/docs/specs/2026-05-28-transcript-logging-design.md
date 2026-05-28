# Transcript + Rewrite Logging — Design

- **Date:** 2026-05-28
- **Component:** `hyprwhspr-ai` daemon
- **Status:** Approved (pending spec review)
- **Scope:** Rewrites only (dictation transcript → LLM rewrite). Vision/OCR/translate/textgen are out of scope.

## Motivation

Neither upstream `hyprwhspr` nor the `hyprwhspr-ai` daemon persists any transcript
data. We want a durable, analyzable, fine-tune-grade record of every dictation
rewrite so we can:

- improve the system prompt / processing by inspecting real input→output pairs,
- build a dataset for fine-tuning a rewrite model,
- analyze behavior over time (fallback rate, how much rewrites change text, per-context patterns).

The data is personal and never leaves the machine. It must be private, integrity-checked,
and never able to break dictation.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Storage format | JSONL (NDJSON), append-only, one record per dictation |
| Scope | Rewrite path only (`RewriteService.rewrite`) |
| Default state | **On by default**; `HYPRWHSPR_AI_LOG=0/false/no` disables |
| Integrity | SHA-256 hash chain (`prev_hash` + record → `hash`) |
| Hash algo | SHA-256 (stdlib, audit-standard; speed is a non-factor at <1 KB/record) |
| Permissions | File `0600`, local-only |
| Window title | Included (can contain sensitive strings; acceptable given local + 0600) |
| Prompt recovery | Full prompt **reconstructable** (not stored inline by default); vocab snapshot in content-addressed sidecar; `HYPRWHSPR_AI_LOG_FULL_PROMPT=1` to inline |
| Retention | Out of scope for v1 (future `log prune`) |

## Format rationale (NDJSON)

- **Crash-resilient:** a mid-write crash corrupts only the trailing partial line;
  all prior records stay valid. A DB partial write can corrupt a WAL segment or lock a table.
- **Streamable:** works with `tail -f | jq`, `grep`, `awk` for ad-hoc analysis.
- **Fine-tune-native:** `{input, output, metadata}` is a standard SFT dataset shape; the
  remaining fields are metadata to filter on.

## Architecture & data flow

```
hyprwhspr ──env(HYPRWHSPR_MODEL, HYPRWHSPR_BACKEND)+stdin──► hyprwhspr-ai-rewrite-hook
   └─► hyprwhspr-ai rewrite (client.py)
        ──socket {op:"rewrite", text, asr_model, asr_backend}──►
        daemon._op_rewrite
          └─► RewriteService.rewrite(text, *, asr_model, asr_backend)
                ├─ (existing) window detect → classify → build prompt → LM Studio → clean
                └─ TranscriptLogger.log(record)   ← NEW, wrapped in try/except
```

- New module `src/transcript_log.py` holds `TranscriptLogger`.
- The logger is injected into `RewriteService` (which already holds all rich context:
  window, context, dialect, prompt, model). Logging happens at the tail of `rewrite()`.
- **Fail-soft:** any logging error is caught and emitted as a `log.warning`; the rewrite
  result is returned regardless. Logging never breaks dictation.

### ASR provenance forwarding (data-quality improvement)

`HYPRWHSPR_MODEL` / `HYPRWHSPR_BACKEND` are passed by upstream to the hook but currently
discarded. Changes:

- `client.py cmd_rewrite`: read both from env, add `asr_model` / `asr_backend` to the request.
- `daemon._op_rewrite`: forward them into `RewriteService.rewrite(...)`.

Every record then records which transcriber produced its input.

## Record schema (JSONL, schema v1)

```json
{
  "schema": 1,
  "seq": 417,
  "id": "f3c2…(uuid4)",
  "ts": "2026-05-28T14:02:11.123Z",
  "session_id": "<daemon-start uuid>",
  "input": "lets refactor the auth module",
  "output": "Let's refactor the auth module.",
  "changed": true,
  "fell_back": false,
  "took_ms": 380,
  "context": "agent-cli",
  "window": { "class": "org.wezfurlong.wezterm", "title": "claude" },
  "md_dialect": "plain",
  "asr": { "model": "parakeet-tdt-0.6b-v3", "backend": "onnx-asr" },
  "llm": {
    "model": "google_gemma-4-e4b-it",
    "family": "gemma",
    "temperature": 0.7,
    "top_p": 0.95,
    "max_tokens": 512
  },
  "prompt_builder_version": 1,
  "prompt_sha256": "…",
  "vocab_sha256": "…",
  "metrics": {
    "in_chars": 30, "in_words": 5,
    "out_chars": 31, "out_words": 5,
    "edit_ratio": 0.10
  },
  "prev_hash": "…",
  "hash": "…"
}
```

Field notes:

- `changed`: `output.strip() != input.strip()`. `edit_ratio`: `1 - difflib.SequenceMatcher(None, input, output).ratio()`. Together these let us filter no-op rewrites out of training data and quantify how much the model alters text.
- `fell_back` rows (LM Studio down → raw returned) are still logged (`changed:false`) — valuable signal.
- Empty-input dictations are skipped (no record).
- `llm.family`: `qwen` vs other, mirroring `LMStudioClient._is_qwen_family()` (different endpoint/sampling).
- Sampling params are the values `RewriteService` requests (temp 0.7, top_p 0.95, max_tokens 512).

## Prompt full-recovery (the optimization)

The prompt embeds the window **title** in its dynamic tail, so prompts are nearly unique
per dictation — inline storage would not dedup. Instead we store everything needed to
**reconstruct** the exact prompt:

- Deterministic inputs already in the row reconstruct the dynamic tail: `context`,
  `md_dialect`, `window.class`, `window.title`.
- `prompt_builder_version`: an integer constant added to `prompts.py`, bumped whenever the
  prompt-building logic changes. Identifies which builder produced a historical row.
- `vocab_sha256`: the vocab block depends on `vocabulary.txt`. The **actual vocab terms are
  written once** to a content-addressed sidecar `vocab/<sha256>.txt` next to the log
  (write-if-absent). Vocab changes rarely, so this is tiny and dedups perfectly.
- `prompt_sha256`: SHA-256 of the exact system prompt used, for verification.

A `reconstruct_prompt(record)` helper rebuilds the prompt from these fields + the vocab
sidecar; a verify step recomputes `prompt_sha256` and confirms byte-identity (for rows whose
`prompt_builder_version` matches the current builder). Historical builder versions are
recoverable from the project's git history.

Escape hatch: `HYPRWHSPR_AI_LOG_FULL_PROMPT=1` additionally stores the literal prompt inline
(`"prompt": "…"`) for zero-effort recovery.

## Integrity, privacy, lifecycle

- **Hash chain:** `hash = sha256(prev_hash + canonical_json(record_without_hash))`, where
  canonical JSON is `json.dumps(..., sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
  Genesis `prev_hash = "0" * 64`. `verify_chain(path)` recomputes the chain and reports the
  first break (tamper-evidence). Exposed as `hyprwhspr-ai log verify`.
- **Permissions:** file created `0600` under `$XDG_STATE_HOME/hyprwhspr-ai/transcripts.jsonl`
  (override via `HYPRWHSPR_AI_LOG_PATH`). The `vocab/` sidecar dir is created `0700`.
- **Toggle:** `HYPRWHSPR_AI_LOG` — on by default; `0`/`false`/`no` disables. A disabled logger
  is a no-op (no file created, no work done).
- **Concurrency:** the daemon is single-process asyncio and `log()` contains no `await`, so it
  runs atomically within the event loop — appends cannot interleave. Open with
  `O_APPEND | O_CREAT`, one `os.write` per record, no lock, no `fsync` (NDJSON tolerates a lost
  trailing line on crash).
- **Seq/chain recovery on startup:** read the last ~64 KB of the file, find the last valid JSON
  record, resume `seq` and `prev_hash` from it. A corrupt trailing partial line is skipped.
  Empty/missing file → `seq` starts at 1, `prev_hash` = genesis.

## Config additions (`config.py` → `AppConfig`)

All env-driven, matching existing knobs (`HYPRWHSPR_AI_*`):

| Field | Env | Default |
|---|---|---|
| `transcript_log_enabled` | `HYPRWHSPR_AI_LOG` | `true` |
| `transcript_log_path` | `HYPRWHSPR_AI_LOG_PATH` | `$XDG_STATE_HOME/hyprwhspr-ai/transcripts.jsonl` |
| `transcript_log_hash_chain` | `HYPRWHSPR_AI_LOG_HASHCHAIN` | `true` |
| `transcript_log_full_prompt` | `HYPRWHSPR_AI_LOG_FULL_PROMPT` | `false` |

(`XDG_STATE_HOME` defaults to `$HOME/.local/state`.)

## Module boundaries

- `transcript_log.py` — owns serialization, hashing, file I/O, seq/chain state, recovery,
  vocab CAS, `verify_chain`, `reconstruct_prompt`. Pure of any rewrite logic. Depends only on
  stdlib (`hashlib`, `json`, `os`, `uuid`, `datetime`, `difflib`).
- `RewriteService` — gains a `TranscriptLogger` dependency and an `asr_model`/`asr_backend`
  kwarg on `rewrite()`. Builds the record from data already in scope and calls `log()` inside
  a try/except. Otherwise unchanged.
- `daemon.py` — constructs the `TranscriptLogger` from config, passes it to `RewriteService`,
  forwards `asr_model`/`asr_backend` from the request.
- `client.py` — `cmd_rewrite` forwards ASR env vars; new `log` subcommand (`verify`) for integrity.
- `prompts.py` — add `PROMPT_BUILDER_VERSION` constant.

## Testing (TDD)

`tests/test_transcript_log.py`:

- disabled logger → no file created, `log()` is a no-op
- enabled logger → appends one valid JSON line containing all required fields
- `seq` increments monotonically across calls
- hash chain: each record's `prev_hash` equals the previous record's `hash`; recomputing
  verifies; `verify_chain` passes on a good file and pinpoints a tampered record
- recovery: a new logger instance continues `seq` and chain from an existing file
- corrupt trailing line is tolerated on recovery (resumes from last valid record)
- file perms are `0600` on creation
- `changed` / `edit_ratio` / char+word metrics are correct
- vocab CAS: sidecar written once per unique vocab; row references the right `vocab_sha256`
- `reconstruct_prompt` round-trips to the original `prompt_sha256`

`tests/test_rewrite.py` (or extend existing): with a fake logger,

- logs exactly once with expected `input`/`output`/`context`
- on LM failure path, logs with `fell_back:true`
- empty input → no log call

## Out of scope (v1)

- Retention/rotation (future `log prune` by age or size cap)
- Logging vision/OCR/translate/textgen ops
- Derived SQLite/DuckDB analytics index (can be generated from JSONL later without schema change)
- Shipping logs off-machine

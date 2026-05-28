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


def test_hash_chain_disabled_omits_hash_fields(tmp_path):
    lg = _logger(tmp_path, hash_chain=False)
    lg.log({"input": "a", "output": "A"})
    lg.log({"input": "b", "output": "B"})
    recs = _read_records(tmp_path / "transcripts.jsonl")
    assert all("hash" not in r and "prev_hash" not in r for r in recs)
    res = verify_chain(tmp_path / "transcripts.jsonl")
    assert res.ok and res.count == 2


def test_edit_ratio_bounds():
    assert edit_ratio("same", "same") == 0.0
    assert edit_ratio("abc", "xyz") == 1.0


def test_reconstruct_prompt_roundtrips(tmp_path):
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

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


@pytest.mark.asyncio
async def test_logging_failure_does_not_break_rewrite(tmp_path):
    # A logging error must never propagate into the rewrite result.
    svc, _ = _service(tmp_path, FakeLMS(reply="Clean."))
    svc._log.store_vocab = lambda _block: (_ for _ in ()).throw(OSError("disk full"))
    res = await svc.rewrite("something")
    assert res.text == "Clean."
    assert res.fell_back is False


@pytest.mark.asyncio
async def test_full_prompt_stored_when_enabled(tmp_path):
    logger = TranscriptLogger(
        path=tmp_path / "transcripts.jsonl", enabled=True, hash_chain=True,
    )
    win = Window(cls="org.wezfurlong.wezterm", title="claude")
    svc = RewriteService(
        FakeLMS(reply="Done."), FakeVocab(), FakeWindows(win), logger,
        log_full_prompt=True,
    )
    await svc.rewrite("hello")
    rec = _records(tmp_path / "transcripts.jsonl")[0]
    assert "prompt" in rec and rec["prompt"]
    from src.transcript_log import sha256_text
    assert sha256_text(rec["prompt"]) == rec["prompt_sha256"]

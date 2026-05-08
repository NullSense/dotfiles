#!/usr/bin/env python3
"""NLLB-200 translation server — Unix-socket REST.

Daemon that lazy-loads NLLB-200-distilled-1.3B (INT8 CTranslate2) on first
request, serves translation requests, and idle-exits after 10 minutes of
no activity. Designed to be launched by systemd user service on demand.

Protocol (Unix socket at $XDG_RUNTIME_DIR/hyprwhspr-nllb.sock):
  Request:  one JSON line with newline:  {"text": "...", "src": "eng_Latn", "tgt": "lit_Latn"}
  Response: one JSON line with newline:  {"translation": "..."}  or  {"error": "..."}

Multi-sentence input: split on sentence boundaries, translate each, rejoin.
NLLB-200 distilled tends to drop sentences on long input otherwise.
"""

import json
import os
import re
import socket
import sys
import threading
import time

MODEL_DIR = os.path.expanduser("~/.local/share/hyprwhspr-translate/nllb-1.3B-int8")
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "hyprwhspr-nllb.sock")
IDLE_TIMEOUT = 180  # seconds — exit after this much idle time

# Sentence boundary regex: split on .!? followed by space + capital, OR newline.
# Conservative — keeps abbreviations like "e.g." together.
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-ZÀ-ſЀ-ӿ])|\n+")


def load():
    """Load tokenizer + translator. Lazy — call once on first request."""
    import ctranslate2
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    translator = ctranslate2.Translator(
        MODEL_DIR, device="cpu", inter_threads=4, intra_threads=4
    )
    return tokenizer, translator


def translate(tokenizer, translator, text, src, tgt):
    """Translate text from src to tgt. Splits multi-sentence input."""
    tokenizer.src_lang = src
    sentences = [s.strip() for s in SENTENCE_SPLIT.split(text) if s.strip()]
    if not sentences:
        return ""
    # Tokenize all sentences in one batch.
    batch = [tokenizer.convert_ids_to_tokens(tokenizer.encode(s)) for s in sentences]
    results = translator.translate_batch(
        batch, target_prefix=[[tgt]] * len(batch), beam_size=4
    )
    out = []
    for r in results:
        target_tokens = r.hypotheses[0][1:]  # drop the language-code prefix
        out.append(tokenizer.decode(tokenizer.convert_tokens_to_ids(target_tokens)))
    return " ".join(out)


def main():
    state = {"last_use": time.time(), "tokenizer": None, "translator": None}

    def idle_watcher():
        while True:
            time.sleep(30)
            if time.time() - state["last_use"] > IDLE_TIMEOUT:
                print(f"idle timeout ({IDLE_TIMEOUT}s), exiting", flush=True)
                os._exit(0)

    threading.Thread(target=idle_watcher, daemon=True).start()

    # Clean up stale socket from a prior crash.
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass

    server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server_sock.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o600)
    server_sock.listen(8)
    print(f"listening on {SOCK_PATH}", flush=True)

    while True:
        conn, _ = server_sock.accept()
        # Each request is one short JSON line — handle synchronously,
        # no thread-pool needed (translation calls are 200-700ms each).
        try:
            with conn:
                buf = b""
                while b"\n" not in buf:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    buf += chunk
                if not buf.strip():
                    continue
                try:
                    req = json.loads(buf.decode("utf-8").strip())
                    text = req["text"]
                    src = req.get("src", "eng_Latn")
                    tgt = req["tgt"]
                except (json.JSONDecodeError, KeyError) as e:
                    conn.sendall(
                        (json.dumps({"error": f"bad request: {e}"}) + "\n").encode()
                    )
                    continue

                # Lazy-load on first request. Reports "loading…" first so the
                # client knows to wait — but since model load is ~1s we just
                # do it inline.
                if state["tokenizer"] is None:
                    print("loading model…", flush=True)
                    state["tokenizer"], state["translator"] = load()
                    print("ready", flush=True)

                try:
                    out = translate(
                        state["tokenizer"], state["translator"], text, src, tgt
                    )
                    state["last_use"] = time.time()
                    conn.sendall(
                        (json.dumps({"translation": out}) + "\n").encode()
                    )
                except Exception as e:
                    conn.sendall(
                        (json.dumps({"error": f"translate failed: {e}"}) + "\n").encode()
                    )
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    main()

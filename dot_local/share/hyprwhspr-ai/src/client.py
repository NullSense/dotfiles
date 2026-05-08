"""hyprwhspr-ai CLI client — talks to the daemon over its Unix socket.

Subcommands mirror the daemon's RPC protocol. Designed to be called
from bash (post_transcription_hook), the omarchy menu, or directly
by the user. Single-shot: connect, send one line, read one line, exit.

Exit codes:
   0   success
   1   request returned ok:false (graceful failure — daemon ran but op failed)
   2   protocol error (bad CLI args, daemon unreachable, malformed response)
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from pathlib import Path
from typing import Any


def _socket_path() -> Path:
    return Path(os.environ.get(
        "HYPRWHSPR_AI_SOCKET",
        f"{os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid()))}/hyprwhspr-ai.sock",
    ))


def _send(req: dict[str, Any], timeout: float = 60.0) -> dict[str, Any]:
    sock_path = _socket_path()
    if not sock_path.exists():
        print(f"hyprwhspr-ai daemon not running (no socket at {sock_path})", file=sys.stderr)
        sys.exit(2)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(str(sock_path))
        sock.sendall((json.dumps(req) + "\n").encode("utf-8"))
        sock.shutdown(socket.SHUT_WR)
        buf = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    except (FileNotFoundError, ConnectionRefusedError, OSError) as e:
        print(f"hyprwhspr-ai daemon unreachable: {e}", file=sys.stderr)
        sys.exit(2)
    finally:
        sock.close()
    if not buf:
        print("hyprwhspr-ai daemon returned empty response", file=sys.stderr)
        sys.exit(2)
    try:
        return json.loads(buf.decode("utf-8").strip())
    except json.JSONDecodeError as e:
        print(f"hyprwhspr-ai daemon returned malformed JSON: {e}", file=sys.stderr)
        sys.exit(2)


def cmd_ping(args: argparse.Namespace) -> int:
    resp = _send({"op": "ping"})
    print(json.dumps(resp, indent=2))
    return 0 if resp.get("ok") else 1


def cmd_rewrite(args: argparse.Namespace) -> int:
    text = args.text if args.text else sys.stdin.read()
    resp = _send({"op": "rewrite", "text": text})
    # Always print SOMETHING — the post_transcription_hook contract is:
    # non-empty stdout replaces the dictation, empty stdout = passthrough.
    out = resp.get("text", "")
    if out:
        sys.stdout.write(out)
    return 0 if resp.get("ok") else 1


def cmd_vision(args: argparse.Namespace) -> int:
    payload: dict[str, Any] = {"op": "vision", "subop": args.subop}
    if args.subop == "ask_region":
        if not args.question:
            print("--question is required for ask_region", file=sys.stderr)
            return 2
        payload["question"] = args.question
    resp = _send(payload)
    if not resp.get("ok"):
        print(f"vision failed: {resp.get('detail', resp.get('error'))}", file=sys.stderr)
        return 1
    sys.stdout.write(resp.get("text", ""))
    return 0


def cmd_translate(args: argparse.Namespace) -> int:
    text = args.text if args.text else sys.stdin.read()
    if args.region:
        resp = _send({"op": "translate-region", "target": args.target,
                      "source": args.source})
    else:
        resp = _send({"op": "translate", "text": text, "target": args.target,
                      "source": args.source})
    if not resp.get("ok"):
        print(f"translate failed: {resp.get('detail', resp.get('error'))}", file=sys.stderr)
        return 1
    sys.stdout.write(resp.get("text", ""))
    return 0


def cmd_ocr(args: argparse.Namespace) -> int:
    resp = _send({"op": "ocr", "image_path": args.image_path})
    if not resp.get("ok"):
        print(f"ocr failed: {resp.get('detail', resp.get('error'))}", file=sys.stderr)
        return 1
    sys.stdout.write(resp.get("text", ""))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hyprwhspr-ai",
                                description="CLI for the hyprwhspr-ai coordinator daemon.")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("ping", help="health check")
    sp.set_defaults(fn=cmd_ping)

    sp = sub.add_parser("rewrite", help="rewrite stdin or arg text")
    sp.add_argument("text", nargs="?", help="text to rewrite (default: stdin)")
    sp.set_defaults(fn=cmd_rewrite)

    sp = sub.add_parser("vision", help="run a vision op")
    sp.add_argument("subop", choices=("summarize_screen", "explain_region", "ask_region"))
    sp.add_argument("--question", help="for ask_region")
    sp.set_defaults(fn=cmd_vision)

    sp = sub.add_parser("translate", help="translate text or a region")
    sp.add_argument("text", nargs="?", help="text to translate (default: stdin or --region)")
    sp.add_argument("--target", required=True, help="target language (name or NLLB code)")
    sp.add_argument("--source", default="eng_Latn", help="source NLLB code (default eng_Latn)")
    sp.add_argument("--region", action="store_true",
                    help="capture a screen region instead of using stdin/text")
    sp.set_defaults(fn=cmd_translate)

    sp = sub.add_parser("ocr", help="OCR an image file via Gemma vision")
    sp.add_argument("image_path", help="path to a PNG/JPG image")
    sp.set_defaults(fn=cmd_ocr)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

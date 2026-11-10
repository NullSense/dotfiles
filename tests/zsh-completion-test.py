#!/usr/bin/env python3
"""Exercise live interactive startup and rebuild completion without its dump cache.

Run with: python3 tests/zsh-completion-test.py
Uses a real terminal because zinit's deferred plugins run after the first prompt.
"""

import errno
import os
import pty
import re
import select
import signal
import time


pid, terminal = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("zsh", ["zsh", "-il"])

output = bytearray()
sent = False
deadline = time.monotonic() + 12
started = time.monotonic()
probe = (
    "autoload -Uz compinit compaudit; compinit -D; "
    'print -r -- "COMPLETION-CHECK:$?:${_comps[mise]}:${_comps[pnpm]}:${_comps[rustup]}"; '
    'compaudit; print -r -- "AUDIT-CHECK:$?"; '
    'print -r -- "COMPLETION-PROBE-DONE"; exit\n'
)
try:
    while time.monotonic() < deadline:
        # Give the actual prompt/ZLE loop time to run the turbo plugin stage.
        if not sent and time.monotonic() - started >= 2:
            os.write(terminal, probe.encode())
            sent = True
        ready, _, _ = select.select([terminal], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(terminal, 65536)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
        if not chunk:
            break
        output.extend(chunk)
finally:
    os.close(terminal)
    ended, _ = os.waitpid(pid, os.WNOHANG)
    if not ended:
        # Interactive shells may ignore SIGTERM; enforce the test's deadline.
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)

text = output.decode(errors="replace")
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text).replace("\r", "")
errors = re.findall(
    r"(?:compinit:[^\n]*|[^\n]*initialization aborted[^\n]*|"
    r"[^\n]*command not found: compdef[^\n]*)", text
)
checks = (
    "\nCOMPLETION-CHECK:0:_mise:_pnpm_completion:_rustup\n",
    "\nAUDIT-CHECK:0\n",
    "\nCOMPLETION-PROBE-DONE\n",
)
if errors or any(check not in text for check in checks):
    raise SystemExit("zsh completion regression failed:\n" + text)
print("zsh completion: fresh compinit, tool registrations, security audit: ok")

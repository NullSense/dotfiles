"""Live Wayland regression: password copying survives clipboard watchers.

Run explicitly with python3 tests/postiz-local-clipboard-test.py.
This overwrites and clears the clipboard using dummy text only.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    cache = Path.home() / '.cache/agent-tmp'
    cache.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix='postiz-clipboard-test-', dir=cache))
    fixture = b'postiz-clipboard-regression-fixture'
    wrapper = Path(__file__).resolve().parents[1] / 'home/.local/bin/postiz-local'
    try:
        (scratch / 'postiz').mkdir()
        (scratch / 'postiz/password').write_bytes(fixture)
        environment = dict(os.environ, XDG_STATE_HOME=str(scratch))
        copied = subprocess.run(
            [str(wrapper), 'password-copy'], env=environment,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
        )
        assert copied.returncode == 0, 'Password copy command failed'
        time.sleep(0.25)  # Let real desktop clipboard watchers request the selection.
        for attempt in range(2):
            pasted = subprocess.run(
                ['wl-paste', '--no-newline'], capture_output=True, timeout=10,
            )
            assert pasted.returncode == 0 and pasted.stdout == fixture, (
                f'Clipboard contents were unavailable on paste {attempt + 1}'
            )
        print('PASS: password copy survives watchers and repeated paste requests')
    finally:
        subprocess.run(['wl-copy', '--clear'], check=True, timeout=10)
        subprocess.run(['agent-clean', 'path', str(scratch)], check=True)


if __name__ == '__main__':
    main()

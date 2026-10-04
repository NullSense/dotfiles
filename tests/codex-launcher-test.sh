#!/usr/bin/env bash
# Recurring launcher regression suite; no real network or Codex sessions.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repo/home/.local/bin/codex" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

launcher = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    private = root / '.local/lib/codex/bin'
    private.mkdir(parents=True)
    stubs = root / 'stubs'
    stubs.mkdir()
    binary = private / 'codex'
    binary.write_text('''#!/usr/bin/env python3
import fcntl, json, os, sys
from pathlib import Path
lock = Path(os.environ['XDG_STATE_HOME']) / 'codex-launcher/update.lock'
if lock.exists():
    with lock.open('w') as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
print(json.dumps(sys.argv[1:]))
sys.exit(int(os.environ.get('FAKE_EXIT', '0')))
''')
    binary.chmod(0o755)
    curl = stubs / 'curl'
    curl.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
home = Path(os.environ['HOME'])
with (home / 'checks').open('a') as f:
    f.write('check\\n')
out = Path(sys.argv[sys.argv.index('-o') + 1])
out.write_text('touch "$HOME/partial-executed"\\n')
if os.environ.get('OFFLINE') == '1':
    sys.exit(22)
out.write_text(''' + repr('''#!/bin/sh
test "$CODEX_RELEASE" = latest || exit 2
test "$CODEX_NON_INTERACTIVE" = 1 || exit 2
test "$CODEX_INSTALL_DIR" = "$HOME/.local/lib/codex/bin" || exit 2
test "${PATH%%:*}" = "$CODEX_INSTALL_DIR" || exit 2
printf 'installed\\n' >> "$HOME/updates"
exit "${INSTALL_EXIT:-0}"
''') + ''')
''')
    curl.chmod(0o755)
    env = dict(os.environ, HOME=tmp, XDG_STATE_HOME=str(root / 'state'),
               PATH=f'{stubs}:/usr/bin:/bin')
    env.pop('CODEX_LAUNCH_ACTIVE', None)

    def run(*args, **extra):
        return subprocess.run(['bash', launcher, *args], env=env | extra,
                              text=True, capture_output=True, timeout=10)

    r = run('resume', '--last', 'prompt with spaces')
    assert r.returncode == 0 and r.stdout == '["resume", "--last", "prompt with spaces"]\n', r
    assert (root / 'updates').read_text() == 'installed\n'
    assert not list((root / 'state/codex-launcher').glob('installer.*'))
    # Each fresh launch checks, and the application exit code is preserved.
    assert run('exec', 'hello', FAKE_EXIT='17').returncode == 17
    assert len((root / 'checks').read_text().splitlines()) == 2
    # Offline/partial downloads and failed installs retain a usable launch.
    r = run('resume', OFFLINE='1')
    assert r.returncode == 0 and 'update check failed' in r.stderr
    assert not (root / 'partial-executed').exists()
    assert run('resume', INSTALL_EXIT='1').returncode == 0
    assert run('update', OFFLINE='1').returncode == 1
    assert run('update').stdout == '["--version"]\n'
    checks = (root / 'checks').read_text()
    for command in ('--version', '--help', 'completion', 'app-server', 'exec-server'):
        assert run(command).returncode == 0
    assert run('exec', 'nested', CODEX_LAUNCH_ACTIVE='1').returncode == 0
    assert (root / 'checks').read_text() == checks
    binary.unlink()
    r = run('resume', OFFLINE='1')
    assert r.returncode == 1 and 'standalone package missing' in r.stderr
print('codex launcher: update, fallback, partial download, arguments, exit status, lock release and internal bypass passed')
PY

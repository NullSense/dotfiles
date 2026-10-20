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
                              text=True, capture_output=True, timeout=10, cwd=root)

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
    # Required Firstmate overrides select the actual embedded transport while
    # preserving policy/effort/notify arguments. Ordinary and remote launches
    # retain the shared-server path; prompt text after -- is never parsed.
    import json
    overrides = ('-c', 'model_reasoning_effort="medium"', '--disable', 'hooks',
                 '-c', 'notify=["bash","-c","touch /owned/turn-end"]')
    r = run(*overrides, CODEX_LAUNCH_ACTIVE='1')
    assert json.loads(r.stdout) == ['--no-daemon', *overrides], r
    for flag in ('--config=x=1', '--enable=memories', '--disable=hooks', '--search'):
        r = run(flag, CODEX_LAUNCH_ACTIVE='1')
        assert json.loads(r.stdout) == ['--no-daemon', flag], r
    for args in (('ordinary prompt',), ('--', '--search'),
                 ('--no-daemon', *overrides),
                 ('--remote', 'unix:///owned/server.sock', *overrides),
                 ('app-server', '-c', 'x=1')):
        r = run(*args, CODEX_LAUNCH_ACTIVE='1')
        assert json.loads(r.stdout) == list(args), r
    # Reproduce the preserved legacy Sift checkout: launch-time defaults replace
    # its exact obsolete MCP snapshot without changing a byte in the checkout.
    subprocess.run(['git', 'init', '-q', str(root)], check=True, env=env)
    config = root / '.codex/config.toml'
    config.parent.mkdir()
    legacy_config = r'''# Repository-scoped Codex settings; personal choices belong in ~/.codex/config.toml.
# AGENTS.md is the canonical instruction file read natively by each harness.
project_doc_max_bytes = 98304

# Mirrors root `.mcp.json`; servers are optional because local stacks are not always running.

[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]
required = false
startup_timeout_sec = 30
tool_timeout_sec = 60
default_tools_approval_mode = "writes"

[mcp_servers.postgres]
# Resolve the launcher in the current checkout or worktree; forward only the documented DSN inputs.
command = "bash"
args = ["-c", "exec \"$(git rev-parse --show-toplevel)/scripts/mcp-postgres.sh\""]
env_vars = ["SIFT_APP_DATABASE_URL", "SIFT_PG_PORT"]
required = false
startup_timeout_sec = 60
tool_timeout_sec = 60
default_tools_approval_mode = "writes"

[mcp_servers.sift]
url = "http://127.0.0.1:8788/mcp"
required = false
startup_timeout_sec = 5
tool_timeout_sec = 60
default_tools_approval_mode = "writes"

[mcp_servers.moon]
command = "moon"
args = ["mcp"]
# Codex forwards only a minimal environment; proto shims need a non-default PROTO_HOME.
env_vars = ["PROTO_HOME"]
required = false
startup_timeout_sec = 10
tool_timeout_sec = 60
default_tools_approval_mode = "writes"

# Sift uses Hugging Face repository IDs as storage-schema identity and requires
# model-card research. Limit the official Hub MCP to its compact filesystem/search
# surface; enable additional write/job tools deliberately in HF's MCP settings.
[mcp_servers.huggingface]
url = "https://huggingface.co/mcp"
enabled_tools = ["hf_fs"]
required = false
startup_timeout_sec = 15
tool_timeout_sec = 60
default_tools_approval_mode = "writes"
'''
    config.write_text(legacy_config)
    disabled = [item for name in ('context7', 'postgres', 'sift', 'moon', 'huggingface')
                for item in ('-c', f'mcp_servers.{name}.enabled=false')]
    r = run('resume', '--last', CODEX_LAUNCH_ACTIVE='1')
    assert json.loads(r.stdout) == ['--no-daemon', *disabled, 'resume', '--last'], r
    assert config.read_text() == legacy_config
    # Nested working directories still discover the exact root snapshot.
    nested = root / 'nested'
    nested.mkdir()
    r = subprocess.run(['bash', launcher, 'resume'], cwd=nested,
                       env=env | {'CODEX_LAUNCH_ACTIVE': '1'}, text=True,
                       capture_output=True, timeout=10)
    assert json.loads(r.stdout) == ['--no-daemon', *disabled, 'resume'], r
    # Operator MCP/directory/remote choices and noninteractive commands bypass
    # these defaults. Existing embedded selection remains in force for -c.
    for args in (('-c', 'mcp_servers.moon.enabled=true'),
                 ('--config=mcp_servers.sift.enabled=true',)):
        assert json.loads(run(*args, CODEX_LAUNCH_ACTIVE='1').stdout) == ['--no-daemon', *args]
    for args in (('-C', str(nested)), ('--cd='+str(nested),),
                 ('--remote', 'unix:///owned/server.sock'), ('mcp', 'list'),
                 ('exec', 'hello'), ('app-server',)):
        assert json.loads(run(*args, CODEX_LAUNCH_ACTIVE='1').stdout) == list(args)
    # Any edited or newer project config is outside this exact legacy exception.
    config.write_text(legacy_config + '\n# deliberate operator edit\n')
    assert json.loads(run('resume', CODEX_LAUNCH_ACTIVE='1').stdout) == ['resume']
    config.write_text('project_doc_max_bytes = 98304\n')
    assert json.loads(run('resume', CODEX_LAUNCH_ACTIVE='1').stdout) == ['resume']
    binary.unlink()
    r = run('resume', OFFLINE='1')
    assert r.returncode == 1 and 'standalone package missing' in r.stderr
print('codex launcher: update, fallback, partial download, arguments, exit status, lock release and internal bypass passed')
PY

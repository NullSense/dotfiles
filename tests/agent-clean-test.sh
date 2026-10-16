#!/usr/bin/env bash
# Regression coverage for the command-bytecode cleanup exception.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp/agent-clean-tests"
mkdir -p "$cache"
case $(findmnt -n -o FSTYPE -T "$cache") in tmpfs|ramfs) echo 'Disk-backed storage required' >&2; exit 1 ;; esac
scratch=$(mktemp -d "$cache/run.XXXXXX")
trap 'agent-clean path "$scratch"' EXIT
export TMPDIR="$scratch" AGENT_CLEAN_TEST_ROOT="$ROOT" PYTHONDONTWRITEBYTECODE=1
python3 - <<'PY'
import contextlib, importlib.machinery, importlib.util, io, os
from pathlib import Path
loader = importlib.machinery.SourceFileLoader('agent_clean', str(Path(os.environ['AGENT_CLEAN_TEST_ROOT'])/'home/.local/bin/agent-clean'))
spec = importlib.util.spec_from_loader(loader.name, loader)
clean = importlib.util.module_from_spec(spec)
loader.exec_module(clean)
home = Path(os.environ['TMPDIR'])/'home'
clean.BYTECODE_ROOTS = [home/'bin', home/'.local/bin', home/'.dotfiles/home/bin', home/'.dotfiles/home/.local/bin']
clean.TMP_ROOTS = [home/'.cache/agent-tmp']
clean.WORKTREES = home/'Programming/.sift-worktrees'
clean.users_of = lambda _: []
clean.containers_mounting = lambda _: []
def rejected(path):
    with contextlib.redirect_stderr(io.StringIO()):
        try: clean.allowed_path(str(path))
        except SystemExit as error: assert error.code == 2
        else: raise AssertionError('Allowed unsafe path: '+str(path))
for root in clean.BYTECODE_ROOTS:
    cache = root/'__pycache__'
    cache.mkdir(parents=True)
    bytecode = cache/'tool.cpython-314.pyc'
    bytecode.write_bytes(b'bytecode')
    assert clean.allowed_path(str(bytecode)) == bytecode
    assert clean.allowed_path(str(cache)) == cache
    uid = clean.os.getuid
    clean.os.getuid = lambda: uid()+1
    rejected(bytecode)
    rejected(cache)
    clean.os.getuid = uid
    with contextlib.redirect_stdout(io.StringIO()): clean.clean_paths([str(bytecode)], True)
    assert bytecode.exists()
    clean.users_of = lambda _: [12345]
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try: clean.clean_paths([str(bytecode)], False)
        except SystemExit as error: assert error.code == 2
        else: raise AssertionError('Deleted an in-use cache')
    assert bytecode.exists()
    clean.users_of = lambda _: []
    source = cache/'important.py'
    source.write_text('source')
    rejected(source)
    rejected(cache)
    with contextlib.redirect_stdout(io.StringIO()): clean.clean_paths([str(bytecode)], False)
    assert not bytecode.exists() and source.exists()
    nested = cache/'nested'
    nested.mkdir()
    rejected(nested)
    rejected(cache)
    outside = home/'documents'
    outside.mkdir(exist_ok=True)
    link = cache/'linked.pyc'
    link.symlink_to(outside, target_is_directory=True)
    rejected(link)
    rejected(cache)
    escaped = root/'escaped-cache'
    escaped.symlink_to(outside, target_is_directory=True)
    rejected(escaped/'payload.pyc')
    disguised = root/'__pycache__.old'
    rejected(disguised)
rejected(home/'Documents/__pycache__/document.pyc')
rejected(home/'bin/tool.pyc')
tmp = clean.TMP_ROOTS[0]/'owned'
tmp.mkdir(parents=True)
assert clean.allowed_path(str(tmp)) == tmp
rejected(clean.TMP_ROOTS[0])
print('PASS: owned command bytecode accepted; sources, mixed caches, nested directories, symlinks and unrelated home paths refused; dry-run and scoped deletion preserved')
PY

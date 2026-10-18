#!/usr/bin/env bash
# Regression coverage for owned command-bytecode and exact-owner network cleanup.
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

# Worktree build/test output is removable; the tracked directories that contain it are not.
worktree = clean.WORKTREES/'feature-x'
for generated in ['target/debug/incremental', 'lints/target/debug', 'lints/mutants.out',
                  'mutants.out', 'mutants.out.old']:
    (worktree/generated).mkdir(parents=True)
for tracked in ['lints/src/lib.rs', 'web/targeting/app.js']:
    source = worktree/tracked
    source.parent.mkdir(parents=True)
    source.write_text('tracked')
for relative in ['target', 'target/debug', 'target/debug/incremental', 'lints/target',
                 'lints/target/debug', 'mutants.out', 'mutants.out.old', 'lints/mutants.out',
                 'lints/mutants.out/survived.txt']:
    assert clean.allowed_path(str(worktree/relative)) == worktree/relative, relative
for relative in ['lints', 'lints/src', 'lints/src/lib.rs', 'web', 'web/targeting',
                 'web/targeting/app.js']:
    rejected(worktree/relative)
rejected(worktree)
rejected(clean.WORKTREES)
rejected(home/'Programming/sift/target')
rejected(home/'Programming/sift/lints/target')
print('PASS: worktree cargo target and cargo-mutants output accepted; containing tracked source, near-miss names and main-checkout build output refused')

# Packaged acceptance relays are fixtures, never their installation's services.
import subprocess
from unittest.mock import patch
def relay_case(name, running=False, running_ok=False, dry=False, reject=False):
    calls = []
    def docker(cmd, **kwargs):
        calls.append(cmd)
        if cmd == ['docker', 'inspect', '-f', '{{.State.Running}}', name]:
            return subprocess.CompletedProcess(cmd, 0, str(running).lower(), '')
        if cmd == ['docker', 'rm', '-f', name]:
            return subprocess.CompletedProcess(cmd, 0, name, '')
        raise AssertionError('Unexpected Docker call: '+repr(cmd))
    with patch.object(clean.subprocess, 'run', side_effect=docker), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try: clean.clean_containers([name], dry, running_ok)
        except SystemExit as error: assert reject and error.code == 2
        else: assert not reject, 'Accepted unsafe container: '+name
    removals = [cmd for cmd in calls if cmd[:2] == ['docker', 'rm']]
    assert removals == ([] if dry or reject else [['docker', 'rm', '-f', name]]), calls
    if reject and not running: assert calls == [], calls
project = 'sift-f115623031524582b7b7f1cdf0e0590b'
for suffix in ['api', 'cp']:
    relay = project+'-acceptance-relay-'+suffix
    relay_case(relay)
    relay_case(relay, running=True, reject=True)
    relay_case(relay, running=True, running_ok=True, dry=True)
    relay_case(relay, running=True, running_ok=True)
for name in [
    'sift-'+('a'*31)+'-acceptance-relay-api',
    'sift-'+('a'*33)+'-acceptance-relay-api',
    'sift-'+('A'*32)+'-acceptance-relay-api',
    'sift-'+('g'*32)+'-acceptance-relay-api',
    project+'-acceptance-relay-api-extra',
    project+'-acceptance-relay-indexer',
    project+'-sift-api-1',
    'sift-live-acceptance-relay-api',
    'infra-'+project+'-acceptance-relay-api',
]: relay_case(name, reject=True)
print('PASS: exact packaged relays, running guard, dry-run and volume-preserving removal; near-miss IDs, suffixes and live services refused')

# Any project's branch may own a disposable stack through a private scratch root.
import copy, json
owner_root = tmp/'oracle-feature-branch'
owner_root.mkdir()
owned = {'Id': 'a'*64, 'Name': '/oracle-audit-20261018-api',
         'HostConfig': {'RestartPolicy': {'Name': 'no'}},
         'State': {'Running': False, 'Paused': False, 'Restarting': False},
         'Mounts': [{'Type': 'bind', 'Source': str(owner_root/'source'), 'RW': False},
                    {'Type': 'volume', 'Source': '/var/lib/docker/volumes/keep', 'RW': True}]}
def owned_case(mutate=None, reject=False, dry=False, running_ok=False, root=None):
    current = copy.deepcopy(owned)
    if mutate: mutate(current)
    calls = []
    def docker(cmd, **kwargs):
        calls.append(cmd)
        if cmd == ['docker', 'inspect', current['Name'].removeprefix('/')]:
            return subprocess.CompletedProcess(cmd, 0, json.dumps([current]), '')
        if cmd == ['docker', 'rm', '-f', current['Id']]:
            return subprocess.CompletedProcess(cmd, 0, current['Id'], '')
        raise AssertionError('Unexpected Docker call: '+repr(cmd))
    args = ['docker', '--owner-root', str(root or owner_root), current['Name'].removeprefix('/')]
    if dry: args.insert(0, '--dry-run')
    if running_ok: args.insert(0, '--running')
    with patch.object(clean.subprocess, 'run', side_effect=docker), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try: clean.main(args)
        except SystemExit as error: assert reject and error.code == 2
        else: assert not reject, 'Accepted foreign or service container'
    removals = [c for c in calls if c[:2] == ['docker', 'rm']]
    assert removals == ([] if dry or reject else [['docker', 'rm', '-f', current['Id']]]), calls
owned_case()
owned_case(dry=True)
owned_case(lambda c: c['State'].update(Running=True), reject=True)
owned_case(lambda c: c['State'].update(Running=True), running_ok=True)
owned_case(lambda c: c.update(Name='/legalkb-bench-feature-xyz-api'))
owned_case(lambda c: c.update(Name='/oracle-api'), reject=True)
owned_case(lambda c: c['Mounts'][0].update(Source=str(tmp/'another-run/source')), reject=True)
owned_case(lambda c: c['Mounts'][0].update(Source=str(owner_root)+'-other/source'), reject=True)
owned_case(lambda c: c['Mounts'].append({'Type':'bind','Source':'/home/shared/data','RW':True}), reject=True)
owned_case(lambda c: c['HostConfig']['RestartPolicy'].update(Name='unless-stopped'), reject=True)
owned_case(lambda c: c['State'].update(Restarting=True), reject=True)
owned_case(lambda c: c.update(Id='a'*12), reject=True)
owned_case(root=home/'documents', reject=True)
owner_root.chmod(0o777)
owned_case(reject=True)
owner_root.chmod(0o755)
link_root = tmp/'linked-owner'
link_root.symlink_to(owner_root, target_is_directory=True)
owned_case(root=link_root, reject=True)
escape_mount = owner_root/'escaped'
escape_mount.symlink_to(home/'documents', target_is_directory=True)
owned_case(lambda c: c['Mounts'][0].update(Source=str(escape_mount/'data')), reject=True)
print('PASS: branch-independent owner-root containers; explicit running opt-in, exact ID, foreign binds, services, symlink escapes and volumes protected')

# Explicit networks can be removed with their scratch-owned stack, without project allowlists.
def stack_network_case(mutate=None, dry=False, reject=False, attach_race=False, resume=False):
    net = {'Id': 'b'*64, 'Name': 'oracle-audit-20261018-edge', 'Driver': 'bridge',
           'Scope': 'local', 'Ingress': False, 'ConfigOnly': False,
           'Containers': {owned['Id']: {'Name': owned['Name'].removeprefix('/')}}}
    if resume: net['Containers'] = {}
    if mutate: mutate(net)
    calls=[]
    removed=False
    def docker(cmd, **kwargs):
        nonlocal removed
        calls.append(cmd)
        if cmd == ['docker','inspect',owned['Name'].removeprefix('/')]:
            if resume: return subprocess.CompletedProcess(cmd,1,'','error: no such object: gone')
            return subprocess.CompletedProcess(cmd,0,json.dumps([owned]),'')
        if cmd[:3] == ['docker','network','inspect']:
            result=copy.deepcopy(net)
            if removed:
                result['Containers'] = {'f'*64:{'Name':'foreign'}} if attach_race else {}
                result['Status'] = {'IPAM': {'IPsInUse': 3}}
            return subprocess.CompletedProcess(cmd,0,json.dumps([result]),'')
        if cmd == ['docker','rm','-f',owned['Id']]:
            removed=True
            return subprocess.CompletedProcess(cmd,0,'','')
        if cmd == ['docker','network','rm',net['Id']]:
            return subprocess.CompletedProcess(cmd,0,'','')
        raise AssertionError(cmd)
    args=['docker','--owner-root',str(owner_root),'--network',net['Name'],owned['Name'].removeprefix('/')]
    if dry: args.insert(0,'--dry-run')
    with patch.object(clean.subprocess,'run',side_effect=docker), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try: clean.main(args)
        except SystemExit as error: assert reject and error.code==2
        else: assert not reject
    net_removals=[c for c in calls if c[:3]==['docker','network','rm']]
    assert net_removals == ([] if dry or reject else [['docker','network','rm',net['Id']]])
    if reject and not attach_race: assert not removed, calls
stack_network_case(lambda n:n.update(Containers={}),reject=True)
stack_network_case()
stack_network_case(dry=True)
stack_network_case(lambda n:n['Containers'].update({'f'*64:{'Name':'foreign'}}),reject=True)
stack_network_case(lambda n:n.update(Name='production-network'),reject=True)
stack_network_case(lambda n:n.update(Driver='overlay'),reject=True)
stack_network_case(lambda n:n.update(Ingress=True),reject=True)
stack_network_case(attach_race=True,reject=True)
stack_network_case(resume=True)
stack_network_case(lambda n:n.update(Id='d'*64),resume=True,reject=True)
print('PASS: explicit stack networks require exclusively proven owned endpoints; foreign, empty, service and raced networks protected; dry-run and full IDs preserved')

# Network cleanup is opt-in, exact-owner scoped, and never removes containers/volumes.
import copy, json, subprocess
from unittest.mock import patch
project = 'sift-test-c24be1649cda'
owner = str(Path(os.environ['TMPDIR'])/'fixture/b')
common = '/missing/fixture/main/.git'
labels = {'com.docker.compose.project': project, 'com.docker.compose.network': 'default',
          'dev.sift.test-infra.schema': '1', 'dev.sift.test-infra.uid': str(os.getuid()),
          'dev.sift.test-infra.stack': project, 'dev.sift.test-infra.worktree': owner,
          'dev.sift.test-infra.git-common-dir': common,
          'dev.sift.test-infra.flavor': 'inner', 'dev.sift.test-infra.run': '-',
          'dev.sift.test-infra.state-dir': owner+'/.local/test-infra'}
network = {'Id': 'f'*64, 'Name': project+'_default', 'Driver': 'bridge',
           'Labels': labels, 'Containers': {}}
container = {'Id': 'c'*64, 'Config': {'Labels': {'com.docker.compose.project': project}},
             'State': {'Status': 'exited', 'Running': False, 'Paused': False, 'Restarting': False}}
base = ['network', '--owner-worktree', owner, '--owner-git-common-dir', common, network['Name']]
def network_case(mutate=None, execute=False, reject=False, race=False, by_id=False, ref_race=False, abbreviated=False):
    calls = []
    current = copy.deepcopy(network)
    ref = copy.deepcopy(container)
    if mutate: mutate(current, ref)
    inspections = 0
    def docker(cmd, **kwargs):
        nonlocal inspections
        calls.append(cmd)
        if cmd[:3] == ['docker', 'network', 'inspect']:
            inspections += 1
            result = copy.deepcopy(current)
            if race and inspections > 1: result['Containers'] = {'active': {'Name': 'raced'}}
            return subprocess.CompletedProcess(cmd, 0, json.dumps([result]), '')
        if cmd[:3] == ['docker', 'ps', '-aq']:
            return subprocess.CompletedProcess(cmd, 0, ref['Id']+'\n', '')
        if cmd[:2] == ['docker', 'inspect']:
            if ref_race and inspections > 1: ref['State'].update(Status='running', Running=True)
            return subprocess.CompletedProcess(cmd, 0, json.dumps([ref]), '')
        if cmd[:3] == ['docker', 'network', 'rm']:
            return subprocess.CompletedProcess(cmd, 0, current['Id'], '')
        raise AssertionError('Unexpected Docker call: '+repr(cmd))
    args = list(base)
    if by_id: args[-1] = network['Id']
    if abbreviated: args[-1] = network['Id'][:12]
    if execute: args.append('--execute')
    with patch.object(clean.subprocess, 'run', side_effect=docker), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try: clean.main(args)
        except SystemExit as error:
            assert reject and error.code == 2, (reject, error)
        else: assert not reject, 'Accepted unsafe network'
    removals = [c for c in calls if c[:3] == ['docker', 'network', 'rm']]
    assert len(removals) == int(execute and not reject), calls
    if removals: assert removals == [['docker', 'network', 'rm', network['Id']]]
network_case()  # Default is preview, even for a stale fixture with an absent lease.
network_case(execute=True)
network_case(execute=True, by_id=True)
network_case(lambda n,c: n.update(Containers={'live': {'Name': 'active'}}), execute=True, reject=True)
network_case(lambda n,c: c['State'].update(Status='running', Running=True), execute=True, reject=True)
network_case(lambda n,c: c['State'].update(Status='restarting', Restarting=True), execute=True, reject=True)
network_case(lambda n,c: c['State'].update(Status='created'), execute=True, reject=True)
network_case(lambda n,c: n['Labels'].update({'dev.sift.test-infra.uid': str(os.getuid()+1)}), execute=True, reject=True)
network_case(lambda n,c: n['Labels'].update({'dev.sift.test-infra.worktree': '/another/owner'}), execute=True, reject=True)
network_case(lambda n,c: n['Labels'].pop('dev.sift.test-infra.schema'), execute=True, reject=True)
network_case(lambda n,c: n.update(Name='bridge'), execute=True, reject=True)
network_case(lambda n,c: n.update(Driver='host'), execute=True, reject=True)
network_case(execute=True, reject=True, race=True)
network_case(execute=True, reject=True, ref_race=True)
network_case(execute=True, reject=True, abbreviated=True)
lease_path = Path(owner)/'.local/test-infra/use.lock'
lease_path.parent.mkdir(parents=True)
with lease_path.open('wb') as lease:
    clean.fcntl.flock(lease, clean.fcntl.LOCK_EX | clean.fcntl.LOCK_NB)
    network_case(execute=True, reject=True)
network_case(execute=True)  # Released lease permits exact-owner cleanup.
print('PASS: network preview/execution, exact ID, active/transitional references, foreign/default networks and raced endpoints')

PY

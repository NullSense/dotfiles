#!/usr/bin/env bash
# Recurring command/lifecycle checks; no real desktop capture or service changes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SCREENRECORD_TEST_ROOT="$ROOT"
python - <<'PY'
import json, os, pathlib, subprocess, tempfile

root = pathlib.Path(os.environ['SCREENRECORD_TEST_ROOT'])
script = root / 'home/bin/screenrecord'
with tempfile.TemporaryDirectory(prefix='screenrecord-test-') as tmp:
    tmp = pathlib.Path(tmp)
    bindir = tmp / 'bin'
    bindir.mkdir()
    stub = '''#!/usr/bin/env python3
import os,sys,json,pathlib
p=pathlib.Path(os.environ['SCREENRECORD_TEST_STATE'])
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with (p/'calls').open('a') as f:f.write(json.dumps([name,args])+'\\n')
if name=='hyprctl':
 print(json.dumps([{'name':'DP-1','colorManagementPreset':os.environ.get('TEST_HDR','hdr')}]))
elif name=='systemctl':
 args=[a for a in args if a!='--user']
 action=args[0]
 if action=='is-active':sys.exit(0 if (p/args[-1]).exists() else 3)
 if action=='start':(p/args[-1]).touch()
 if action=='stop':(p/args[-1]).unlink(missing_ok=True)
elif name=='pgrep':sys.exit(0 if os.environ.get('TEST_OTHER_RECORDER')=='1' else 1)
'''
    for name in ['gpu-screen-recorder','hyprctl','systemctl','notify-send','pkill','pgrep','sleep']:
        p = bindir/name
        p.write_text(stub)
        p.chmod(0o755)
    env = dict(os.environ, PATH=str(bindir)+':'+os.environ['PATH'],
               SCREENRECORD_TEST_STATE=str(tmp), XDG_RUNTIME_DIR=str(tmp),
               SCREENRECORD_OUTPUT_DIR=str(tmp/'video'))
    def run(*args, good=True, **overrides):
        r = subprocess.run(['bash',str(script),*args],env=dict(env,**overrides),capture_output=True,text=True)
        assert (r.returncode == 0) == good, (args,r.returncode,r.stderr)
    def calls():
        return [json.loads(x) for x in (tmp/'calls').read_text().splitlines()]
    def reset():
        (tmp/'calls').write_text('')
    def encoder_args():
        return next(args for name,args in calls() if name=='gpu-screen-recorder')
    run('--game-worker=record')
    args=encoder_args()
    for key,value in {'-k':'av1_hdr','-encoder':'gpu','-fallback-cpu-encoding':'no',
                      '-s':'3840x2160','-f':'60','-a':'default_output','-q':'60000','-c':'mkv'}.items():
        assert args[args.index(key)+1]==value,(key,args)
    assert '-r' not in args
    assert args[-1].endswith('.mkv')
    reset()
    run('--game-worker=replay')
    args=encoder_args()
    assert args[args.index('-r')+1]=='120'
    assert args[args.index('-replay-storage')+1]=='ram'
    assert args[-1].endswith('/Gameplay/Replays')
    reset()
    run('--game-worker=record',good=False,TEST_HDR='srgb')
    assert not any(name=='gpu-screen-recorder' for name,args in calls())
    reset()
    run('--save-replay',good=False)
    assert not any('kill' in args for name,args in calls())
    reset()
    run('--replay')
    assert (tmp/'screenrecord-game@replay.service').exists()
    run('--save-replay')
    assert ['systemctl',['--user','kill','--kill-whom=main','--signal=SIGUSR1',
                         'screenrecord-game@replay.service']] in calls()
    reset()
    run('--game',good=False)
    run('--stop-recording')
    assert not any(name=='pkill' or 'stop' in args for name,args in calls())
    run('--replay')
    assert not (tmp/'screenrecord-game@replay.service').exists()
    reset()
    run('--game',good=False,TEST_OTHER_RECORDER='1')
    assert not any('start' in args for name,args in calls())
    run('--game')
    run('--game')
    assert not (tmp/'screenrecord-game@record.service').exists()
unit=(root/'home/.config/systemd/user/screenrecord-game@.service').read_text()
assert 'KillSignal=SIGINT' in unit and '[Install]' not in unit
print('PASS: HDR encoder arguments, RAM replay, save signal, mode isolation, and service lifecycle')
PY

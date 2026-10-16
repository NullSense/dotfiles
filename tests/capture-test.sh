#!/usr/bin/env bash
# Recurring capture lifecycle/clipboard tests. Opt in to real NVENC with --gpu.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp/capture-tests"
mkdir -p "$cache"
case $(findmnt -n -o FSTYPE -T "$cache") in tmpfs|ramfs) echo 'Disk-backed test storage required' >&2; exit 1 ;; esac
scratch=$(mktemp -d "$cache/run.XXXXXX")
trap 'agent-clean path "$scratch"' EXIT
export TMPDIR="$scratch" CAPTURE_TEST_ROOT="$ROOT" CAPTURE_TEST_GPU="${1:-}"
python3 - <<'PY'
import hashlib, importlib.machinery, importlib.util, json, os, pathlib, select, signal, subprocess, sys, time

root = pathlib.Path(os.environ['CAPTURE_TEST_ROOT'])
tmp = pathlib.Path(os.environ['TMPDIR'])
home = tmp / 'home'
bin_dir = home / 'bin'
bin_dir.mkdir(parents=True)
for name in ('screenrecord', 'screenshot', 'screenrecord-share', 'screenrecord-status', 'omarchy-capture-screenshot'):
    (bin_dir / name).symlink_to(root / 'home/bin' / name)
stubs = tmp / 'stubs'
stubs.mkdir()
stub = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, socket, sys, time
p = pathlib.Path(os.environ['CAPTURE_STATE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (p/'calls').open('a') as f: f.write(json.dumps([name,args])+'\n')
if name == 'wl-copy':
    (p/'clipboard').write_bytes(sys.stdin.buffer.read())
elif name == 'gpu-screen-recorder':
    def stop(*_):
        (p/'stopped').touch()
        sys.exit(0)
    signal.signal(signal.SIGINT, stop)
    sock = socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    sock.bind(args[args.index('-ipc')+1])
    sock.listen()
    sock.settimeout(.05)
    pathlib.Path(args[args.index('-o')+1]).write_bytes(b'fake-video')
    while True:
        try: client,_ = sock.accept()
        except socket.timeout: continue
        with client:
            request=json.loads(client.recv(4096))
            if os.environ.get('REJECT_PAUSE'):
                client.sendall(b'{"id":1,"result":"error","data":"test rejection"}\n')
            else:
                (p/'paused').write_text(str(request['data']))
                client.sendall(b'{"id":1,"result":"ok"}\n')
elif name == 'ffprobe':
    print(json.dumps({'format': {'duration':'3'}, 'streams':[{'codec_type':'video','codec_name':'h264'}]}))
elif name == 'pgrep': sys.exit(0 if os.environ.get('OTHER_RECORDER') else 1)
elif name == 'systemctl': sys.exit(3)
elif name == 'hyprctl':
    if 'clients' in args: print('[]')
    else: print(json.dumps([{'name':'DP-2','x':-1920,'y':0,'width':1920,'height':1080,
                            'scale':float(os.environ.get('MONITOR_SCALE',1)),'transform':0,'focused':True,
                            'activeWorkspace':{'id':1},'specialWorkspace':{'id':0}}]))
elif name == 'slurp':
    sys.stdin.read()
    print(os.environ.get('SELECTION','-100,20 100x80'))
elif name == 'hyprpicker':
    while True: time.sleep(.02)
elif name == 'pkill': sys.exit(1)
elif name == 'grim': pathlib.Path(args[-1]).write_bytes(b'png')
'''
for name in ('wl-copy','gpu-screen-recorder','ffprobe','pgrep','systemctl','hyprctl',
             'slurp','hyprpicker','pkill','grim','notify-send'):
    p = stubs / name
    p.write_text(stub)
    p.chmod(0o755)
state = tmp / 'state'
state.mkdir()
runtime = tmp / 'runtime'
runtime.mkdir()
env = dict(os.environ, HOME=str(home), PATH=str(stubs)+':'+os.environ['PATH'],
           CAPTURE_STATE=str(state), XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(state),
           XDG_CACHE_HOME=str(tmp/'cache'), SCREENRECORD_OUTPUT_DIR=str(tmp/'Videos with # spaces'),
           SCREENSHOT_COLORTEMP_BYPASSED='1', OMARCHY_SCREENSHOT_DIR=str(tmp/'Pictures'))
def run(name, *args, good=True, **overrides):
    r = subprocess.run([str(bin_dir/name),*args], env=dict(env,**overrides),
                       capture_output=True, text=True, timeout=15)
    assert (r.returncode == 0) == good, (name,args,r.returncode,r.stdout,r.stderr)
    return r.stdout.strip()
def calls():
    return [json.loads(x) for x in (state/'calls').read_text().splitlines()]
def value(args, option): return args[args.index(option)+1]
watcher = subprocess.Popen([str(bin_dir/'screenrecord-status'),'--watch'],env=env,stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE,bufsize=0)
def watch_until(status):
    deadline=time.monotonic()+3
    while time.monotonic()<deadline:
        ready,_,_=select.select([watcher.stdout],[],[],max(0,deadline-time.monotonic()))
        if ready:
            data=watcher.stdout.readline()
            assert data,watcher.stderr.read().decode()
            payload=json.loads(data)
            if payload['class']==status:return payload
    raise AssertionError('Watcher never emitted '+status)

# Start and stop the real shell entrypoint; fake only its external dependencies.
# The recorder is a real process with a real PID and SIGINT handler.
try:
    watch_until('idle')
    assert json.loads(run('screenrecord-status'))['text'] == ''
    run('screenrecord','--with-desktop-audio')
    watch_until('recording')
    args = next(a for n,a in calls() if n == 'gpu-screen-recorder')
    for k,v in {'-k':'h264','-encoder':'gpu','-fallback-cpu-encoding':'no',
                '-f':'30','-ac':'aac','-ab':'128',
                '-w':'100x80+-100+20',
                '-ffmpeg-opts':'movflags=+faststart-hybrid_fragmented'}.items():
        assert value(args,k) == v,(k,args)
    assert '-s' not in args  # Small regions must never be upscaled by GSR.
    file = pathlib.Path(value(args,'-o'))
    assert json.loads(run('screenrecord-status'))['class'] == 'recording'
    run('screenrecord','--toggle-pause')
    watch_until('paused')
    assert (state/'paused').read_text() == 'True'
    paused = json.loads(run('screenrecord-status'))
    assert paused['class'] == 'paused' and 'PAUSED' in paused['text']
    run('screenrecord','--toggle-pause')
    watch_until('recording')
    assert (state/'paused').read_text() == 'False'
    assert json.loads(run('screenrecord-status'))['class'] == 'recording'
    run('screenrecord','--stop-recording')
    watch_until('idle')
    assert json.loads(run('screenrecord-status'))['text'] == ''
    assert (state/'stopped').exists()
    assert (state/'clipboard').read_bytes() == (file.as_uri()+'\r\n').encode()
    assert '%23' in (state/'clipboard').read_text() and '%20' in (state/'clipboard').read_text()
    assert (state/'screenrecord/latest').read_text() == str(file)
    assert ['wl-copy',['--type','text/uri-list']] in calls()
    assert not any(n == 'ffmpeg' or (n == 'pkill' and any('gpu-screen' in x for x in a)) for n,a in calls())
    before = len(calls())
    run('screenrecord','--stop-recording',good=False)
    assert not any(n == 'wl-copy' for n,a in calls()[before:])
    run('screenrecord',good=False,OTHER_RECORDER='1')
    run('screenrecord','--preset=nonsense',good=False)
    for preset,res,fps in [('native','0x0','60'),('small','1280x720','30')]:
        (runtime/'screenrecord/ipc.sock').unlink(missing_ok=True)
        before = len(calls())
        run('screenrecord',f'--preset={preset}',SELECTION='-100,20 1x1')
        args = next(a for n,a in calls()[before:] if n == 'gpu-screen-recorder')
        assert value(args,'-w') == 'DP-2' and value(args,'-f') == fps
        if preset == 'native': assert '-s' not in args
        else: assert value(args,'-s') == res
        run('screenrecord','--stop-recording')
    (runtime/'screenrecord/ipc.sock').unlink(missing_ok=True)
    before = len(calls())
    run('screenrecord',MONITOR_SCALE='2',SELECTION='-1000,20 800x600')
    args = next(a for n,a in calls()[before:] if n == 'gpu-screen-recorder')
    assert value(args,'-s') == '1920x1080'  # Logical 800x600 -> physical 1600x1200.
    run('screenrecord','--stop-recording')
    (runtime/'screenrecord/ipc.sock').unlink(missing_ok=True)
    run('screenrecord',REJECT_PAUSE='1')
    run('screenrecord','--toggle-pause',good=False)
    assert json.loads(run('screenrecord-status'))['class'] == 'recording'
    run('screenrecord','--stop-recording')
finally:
    watcher.terminate()
    watcher.wait(timeout=3)
    pid_file = runtime/'screenrecord/pid'
    if pid_file.exists() and pid_file.read_text().strip():
        try: os.kill(int(pid_file.read_text()),signal.SIGINT)
        except ProcessLookupError: pass

# Screenshot MIME, negative coordinates, XDG directory and exact path return.
result = run('omarchy-capture-screenshot','smart','--print-path',SELECTION='-100,20 1x1')
assert result.endswith('.png') and pathlib.Path(result).exists()
grim = next(a for n,a in calls() if n == 'grim')
assert value(grim,'-g') == '-1920,0 1920x1080',grim
assert value(grim,'-l') == '1'
assert ['wl-copy',['--type','image/png']] in calls()
assert run('screenshot','--print-path',SELECTION='') == ''
print('PASS: real start/stop lifecycle, file clipboard, NVENC arguments, no global kill, screenshot cancellation/negative geometry/MIME')
print('PASS: recording status hides when idle, pause/resume waits for IPC acknowledgement, rejects failed pause')

loader = importlib.machinery.SourceFileLoader('capture_share',str(bin_dir/'screenrecord-share'))
spec = importlib.util.spec_from_loader(loader.name,loader)
share = importlib.util.module_from_spec(spec)
loader.exec_module(share)
os.environ.update(env)
# Invalid budgets fail without starting an encode.
for budget in (float('nan'),float('inf'),0,-1,1001):
    try: share.export(file,target_mb=budget)
    except ValueError: pass
    else: raise AssertionError(budget)

# Oversized GPU outputs retry at a lower bitrate, and never publish a file
# over budget. Simulate rate-control misses independently of GPU availability.
original_run = share.run
def simulate_sizes(sizes):
    rates=[]
    def fake(args,**kwargs):
        if args[0] == 'ffmpeg':
            assert value(args,'-c:v') == 'h264_nvenc'
            assert 'scale_cuda' in value(args,'-vf') and '-fs' not in args
            rates.append(int(value(args,'-b:v')))
            pathlib.Path(args[-1]).write_bytes(b'x'*next(sizes))
            return subprocess.CompletedProcess(args,0)
        return original_run(args,**kwargs)
    return fake,rates
source = tmp/'rate-control.mp4'
source.write_bytes(b'source'*100000)
share.run,rates = simulate_sizes(iter([250000,180000]))
try:
    result = share.export(source,target_mb=.2)
    assert result.stat().st_size == 180000 and rates[1] < rates[0]
    before = set((source.parent/'Shared').iterdir())
    share.run,rates = simulate_sizes(iter([250000,250000,250000]))
    try: share.export(source,target_mb=.2)
    except ValueError: pass
    else: raise AssertionError('Oversized export published')
    assert set((source.parent/'Shared').iterdir()) == before
finally:
    share.run = original_run
print('PASS: budget validation, oversize retries, and failed-export cleanup')

if os.environ.get('CAPTURE_TEST_GPU') == '--gpu':
    # Real NVIDIA decode/scale/encode. Stub only UI/clipboard, never FFmpeg.
    (stubs/'ffprobe').unlink()
    source = tmp / 'synthetic audio.mp4'
    subprocess.run(['ffmpeg','-v','error','-nostdin','-f','lavfi','-i','testsrc2=size=1280x720:rate=30',
                    '-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','6',
                    '-c:v','h264_nvenc','-preset','p4','-b:v','6M','-c:a','aac','-movflags','+faststart',
                    str(source)],check=True)
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    start = time.monotonic()
    dest = share.export(source,target_mb=.2)
    duration, video, audio = share.probe(dest)
    assert dest.stat().st_size <= 200_000
    assert abs(duration - 6) <= .25 and audio
    assert video['codec_name'] == 'h264' and video['pix_fmt'] == 'yuv420p'
    raw = dest.read_bytes()
    assert raw.index(b'moov') < raw.index(b'mdat')
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    assert (state/'clipboard').read_bytes() == (dest.as_uri()+'\r\n').encode()
    small = share.export(source,preset='small')
    assert small.exists()
    assert share.export(dest,target_mb=1) == dest  # No re-encode when it fits.
    assert not list((tmp/'cache/screenrecord').glob('export-*'))
    print(f'PASS: real NVDEC/CUDA/NVENC, {dest.stat().st_size} bytes / 200000, full {duration}s + audio, faststart, original preserved ({time.monotonic()-start:.2f}s incl. second preset)')
PY

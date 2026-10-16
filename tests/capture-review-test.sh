#!/usr/bin/env bash
# Native GTK review/audio controls acceptance; requires a graphical session + NVIDIA.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp/capture-review-tests"
mkdir -p "$cache"
case $(findmnt -n -o FSTYPE -T "$cache") in tmpfs|ramfs) echo 'Disk-backed storage required' >&2; exit 1 ;; esac
scratch=$(mktemp -d "$cache/run.XXXXXX")
trap 'agent-clean path "$scratch"' EXIT
export TMPDIR="$scratch" CAPTURE_TEST_ROOT="$ROOT" PYTHONDONTWRITEBYTECODE=1
ffmpeg -v error -nostdin -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 2 \
    -c:v h264_nvenc "$scratch/preview.mp4"
/usr/bin/python3 - <<'PY'
import argparse, importlib.machinery, importlib.util, json, os, pathlib, subprocess, time
import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk, GLib
tmp=pathlib.Path(os.environ['TMPDIR'])
os.environ['XDG_STATE_HOME']=str(tmp/'state')
loader=importlib.machinery.SourceFileLoader('capture_review',str(pathlib.Path(os.environ['CAPTURE_TEST_ROOT'])/'home/bin/screenrecord-review'))
spec=importlib.util.spec_from_loader(loader.name,loader)
review=importlib.util.module_from_spec(spec)
loader.exec_module(review)
app=Gtk.Application(application_id='local.screenrecord.Review')
app.register(None)
copies=[]
review.share.copy_file=lambda path: copies.append(path)
review.share.notify=lambda *_: None
path=tmp/'preview.mp4'
w=review.Review(app,path)
w.present()
context=GLib.MainContext.default()
def until(predicate):
    deadline=time.monotonic()+8
    while not predicate() and time.monotonic()<deadline:
        while context.pending(): context.iteration(False)
        time.sleep(.01)
    assert predicate(), 'Timed out waiting for native GTK state'
until(lambda: w.stream.is_prepared())
assert w.stream.get_error() is None, w.stream.get_error()
assert w.stream.get_duration()==2_000_000
if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
    def clients():
        return json.loads(subprocess.check_output(['hyprctl','clients','-j']))
    until(lambda: any(c['pid']==os.getpid() for c in clients()))
    window=next(c for c in clients() if c['pid']==os.getpid())
    assert window['class']=='local.screenrecord.Review' and window['floating'], window
assert copies==[]
w.original(None)
assert copies==[path]
w.caption.set_text('Caption: <safe> & 100%')
assert not w.copy_original.get_sensitive()
assert w.caption_preview.get_text()=='Caption: <safe> & 100%'
w.start.set_value(.5)
w.end.set_value(1.5)
w.mute.set_active(True)
w.destination.set_selected(w.app_keys.index('whatsapp-video'))
assert w.budget.get_value()==60 and not w.cap.get_sensitive()
w.destination.set_selected(w.app_keys.index(None))
w.cap.set_active(False)
assert not w.budget.get_sensitive()
exports=[]
def fake_export(path,**options):
    exports.append(options)
    return path
review.share.export=fake_export
w.begin_export(None)
until(lambda: not w.busy)
assert len(copies)==2 and exports[0]['copy'] is False
assert exports[0]['mute'] and exports[0]['start']==.5 and exports[0]['end']==1.5
assert exports[0]['target_mb'] is None
w.copy_after.set_active(False)
w.begin_export(None)
until(lambda: not w.busy)
assert len(copies)==2
def cancelled(path,**options):
    assert options['cancel_event'].wait(3)
    raise InterruptedError('Export cancelled')
review.share.export=cancelled
w.copy_after.set_active(True)
w.begin_export(None)
assert w.closing(None) is True
until(lambda: not w.busy)
assert len(copies)==2
review.audio_devices=lambda: [('default_output','Speakers'),('device:voice_cleaned','Voice (Cleaned)')]
args=argparse.Namespace(desktop=False,microphone=True)
audio_app=Gtk.Application(application_id='local.screenrecord.Audio')
audio_app.register(None)
a=review.AudioSetup(audio_app,args)
a.present()
if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
    until(lambda: any(c['pid']==os.getpid() and c['class']=='local.screenrecord.Audio' for c in clients()))
    assert next(c for c in clients() if c['pid']==os.getpid() and c['class']=='local.screenrecord.Audio')['floating']
assert a.result is None
a.controls[1][2].set_selected(1)
a.accept(None)
assert a.result=={'audio':'device:voice_cleaned'}
b=review.AudioSetup(audio_app,argparse.Namespace(desktop=False,microphone=False))
assert b.controls[1][1].get_active() and b.controls[1][2].get_selected()==1
b.close()
assert b.result is None
print('PASS: native video playback; review before clipboard; caption, trim, mute, app/custom budget controls; export-only and cancellation; audio source persistence; Hyprland floating windows')
PY

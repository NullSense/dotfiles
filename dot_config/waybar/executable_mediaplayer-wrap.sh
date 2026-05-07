#!/usr/bin/env sh
# Single-instance wrapper for mediaplayer.py.
#
# Waybar's SIGUSR2 reload re-execs custom/{exec} children without killing the
# previous one, so they accumulate (one extra pair per reload). This wrapper
# tracks the previous PID in $XDG_RUNTIME_DIR and kills it on startup.
#
# We `exec python3 ...` so the python process inherits this shell's PID,
# meaning the recorded $$ is also the python PID — kill is precise.

set -eu
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/waybar-mediaplayer.pid"

# Belt-and-suspenders: kill (a) the previous PID we recorded, and (b) any
# stray python3 mediaplayer.py owned by us that isn't us. SIGKILL because
# mediaplayer.py installs its SIGTERM handler via signal.signal() rather than
# GLib.unix_signal_add(), which is unreliable while GLib's MainLoop is
# blocked in C — TERM gets queued but never delivered to the Python handler.

if [ -r "$PIDFILE" ]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then
        kill -9 "$old" 2>/dev/null || true
    fi
fi

# Sweep stragglers from past sessions that weren't recorded in the pidfile.
for pid in $(pgrep -u "$(id -u)" -f 'python3.*waybar/mediaplayer\.py'); do
    [ "$pid" = "$$" ] && continue
    kill -9 "$pid" 2>/dev/null || true
done

echo "$$" > "$PIDFILE"
exec python3 -u "$HOME/.config/waybar/mediaplayer.py"

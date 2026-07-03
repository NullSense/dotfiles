#!/usr/bin/env bash
# Waybar wrapper for the hyprwhspr module — passes through the stock tray status
# JSON and merges a dictation-REWRITE health badge onto it.
#
# Rewrite is considered ON iff:
#   (a) the hyprwhspr-ai daemon socket exists, AND
#   (b) the currently-active rewrite backend endpoint accepts a TCP connection.
# (Cheap proxy — no model call — safe to run on waybar's 1s interval.)
#
# Failure-safe: any error → emit the stock tray output unchanged, never break the widget.
set -uo pipefail

TRAY="/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprwhspr-ai.sock"
BACKENDS="$HOME/.config/hyprwhspr-ai/backends.json"

base="$("$TRAY" status 2>/dev/null)"
[ -n "$base" ] || base='{"text":"","class":"","tooltip":""}'

rw_ok=0
if [ -S "$SOCK" ]; then
  hp="$(python3 - "$BACKENDS" 2>/dev/null <<'PY'
import json, sys, urllib.parse
d = json.load(open(sys.argv[1]))
b = d["backends"][d["active"]]
u = urllib.parse.urlparse(b["base_url"])
print(f"{u.hostname or '127.0.0.1'} {u.port or 80}")
PY
)"
  if [ -n "$hp" ]; then
    read -r host port <<<"$hp"
    timeout 0.3 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null && rw_ok=1
  fi
fi

if command -v jq >/dev/null 2>&1; then
  if [ "$rw_ok" = 1 ]; then
    printf '%s' "$base" | jq -c '.tooltip = ((.tooltip // "") + "\n✎ rewrite: ON")'
  else
    printf '%s' "$base" | jq -c '
      .text    = ((.text // "") + " ✎̶")
    | .class   = (((.class // "") | if type=="array" then join(" ") else . end) + " rewrite-off")
    | .tooltip = ((.tooltip // "") + "\n✎̶ rewrite: OFF — hyprwhspr-ai daemon or backend down")'
  fi
else
  printf '%s' "$base"
fi

#!/usr/bin/env bash
# confirm-workspace.sh — shows a zenity dialog before switching to workspaces 5-10.
#
# Usage: confirm-workspace.sh <ws_number>
#   If ws >= 5 and user confirms, runs: hyprctl dispatch workspace <ws>
#   If ws < 5 or user cancels: no-op.
#
# Called from hyprland keybindings:
#   bind = $mod, 5, exec, ~/.config/waybar/confirm-workspace.sh 5
#   ... up to 10.

set -u

WS="${1:-}"
if [[ -z "$WS" ]] || ! [[ "$WS" =~ ^[0-9]+$ ]]; then
  echo "Usage: confirm-workspace.sh <ws_number>" >&2
  exit 1
fi

# Only prompt for work workspaces (5-10). 1-4 switch instantly.
if (( WS < 5 )); then
  "$HOME/bin/hypr-dispatch" dispatch "workspace $WS" "hl.dsp.focus({ workspace = \"$WS\" })" >/dev/null 2>&1 || true
  exit 0
fi

# Time gate: the "punch in?" nag only makes sense in the evening — during the
# day, work workspaces switch instantly with no prompt. Only from this hour
# (24h clock) onward do we ask "are you sure you want to work this late?".
# Change to 20 for an 8pm cutoff.
WORK_CONFIRM_AFTER_HOUR=18
HOUR=$((10#$(date +%H)))          # 10# forces base-10 (avoids octal on 08/09)
if (( HOUR < WORK_CONFIRM_AFTER_HOUR )); then
  "$HOME/bin/hypr-dispatch" dispatch "workspace $WS" "hl.dsp.focus({ workspace = \"$WS\" })" >/dev/null 2>&1 || true
  exit 0
fi

# Show confirmation dialog.
# zenity --question returns 0 on OK/Yes, 1 on Cancel/No.
RESPONSE=$(zenity --question \
  --title="Switch to workspace $WS?" \
  --text="You're about to switch to workspace $WS (work).\n\nAre you sure you want to punch in?" \
  --no-wrap \
  --width=350 \
  --height=150 \
  2>&1)

# zenity exits 0 = user clicked Yes/OK, 1 = Cancel
if [[ $? -eq 0 ]]; then
  "$HOME/bin/hypr-dispatch" dispatch "workspace $WS" "hl.dsp.focus({ workspace = \"$WS\" })" >/dev/null 2>&1 || true
fi

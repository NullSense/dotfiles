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
CTL="$HOME/.config/waybar/hyprwhspr-rewrite-ctl.sh"
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
NOTIFY_STAMP="$RUN/hyprwhspr-rewrite-notify"   # rate-limit failure notifications
NOTIFY_MIN_INTERVAL=120                         # seconds between repeat alerts

base="$("$TRAY" status 2>/dev/null)"
[ -n "$base" ] || base='{"text":"","class":"","tooltip":""}'

# Rewrite health: disabled (you turned it off) | ok | error:<reason>.
# Distinguishes an intentional OFF (dim, no alarm) from a genuine backend
# failure (red badge + a rate-limited desktop notification).
h="$(bash "$CTL" health 2>/dev/null || echo 'error:health probe failed')"

if ! command -v jq >/dev/null 2>&1; then printf '%s' "$base"; exit 0; fi

case "$h" in
  disabled)
    printf '%s' "$base" | jq -c '
        .class   = (((.class // "") | if type=="array" then join(" ") else . end) + " rewrite-disabled")
      | .tooltip = ((.tooltip // "") + "\n✎ rewrite: OFF (you disabled it — middle-click to enable)")' ;;
  ok)
    printf '%s' "$base" | jq -c '.tooltip = ((.tooltip // "") + "\n✎ rewrite: ON  (middle-click to toggle)")' ;;
  error:*)
    reason="${h#error:}"
    # rate-limited notification on genuine failure
    now=$(date +%s); last=$(cat "$NOTIFY_STAMP" 2>/dev/null || echo 0)
    if (( now - last >= NOTIFY_MIN_INTERVAL )); then
      notify-send -a hyprwhspr -i dialog-error -u critical \
        "Dictation rewrite is failing" "$reason — dictation still works (raw text)." 2>/dev/null || true
      echo "$now" >"$NOTIFY_STAMP"
    fi
    printf '%s' "$base" | jq -c --arg r "$reason" '
        .text    = ((.text // "") + " ✎̶")
      | .class   = (((.class // "") | if type=="array" then join(" ") else . end) + " rewrite-error")
      | .tooltip = ((.tooltip // "") + "\n✎̶ rewrite: ERROR — " + $r)' ;;
  *)
    printf '%s' "$base" ;;
esac

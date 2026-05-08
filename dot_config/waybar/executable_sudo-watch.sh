#!/usr/bin/env bash
# sudo-watch — waybar streaming module for the sudo-active flag.
#
# Long-running event loop: emits one JSON line per state transition.
# Two trigger sources, both event-driven (zero polling):
#   1. `inotifywait` on /run/user/$UID/sudo-active — fires on create,
#      modify, delete (covers PAM open/close events).
#   2. `timeout` set to the exact TTL deadline — fires when the auth
#      cache expires with no further sudo activity (the file itself
#      doesn't change, so we have to model the deadline ourselves).
#
# waybar reads each JSON line as the new state. No `interval` poll
# needed; the only fallback is waybar restarting the exec on death.
#
# Flag file format (key=value lines, written by /usr/local/bin/sudo-flag.sh):
#   user=<PAM_RUSER>
#   epoch=<unix_ts>
#   type=<PAM_TYPE>
#   tty=<PAM_TTY>
#   addr=<hyprland window address>
#   ws=<hyprland workspace name>
#
# Requires: inotify-tools (`pacman -S --needed inotify-tools`).
# Falls back to a 5s sleep loop if inotifywait is missing — degrades
# gracefully into low-rate polling.
set -u

flag="/run/user/$(id -u)/sudo-active"
flag_dir=$(dirname "$flag")
ttl=${SUDO_CACHE_SEC:-300}

mkdir -p "$flag_dir" 2>/dev/null || true

# Choose the wait primitive once. Falls back to plain sleep if no inotify.
have_inotify=0
command -v inotifywait >/dev/null 2>&1 && have_inotify=1

# Wait for ANY filesystem event in flag_dir, or until $1 seconds elapse,
# whichever comes first. With no inotify available, just sleep $1.
wait_or_event() {
  local s="$1"
  if (( have_inotify )); then
    timeout "$s" inotifywait -qq -e modify,create,delete,close_write \
      "$flag_dir" 2>/dev/null || true
  else
    sleep "$s"
  fi
}

emit_state() {
  local text alt class tt
  if [[ -f "$flag" ]]; then
    local mtime age remaining rem_min rem_sec
    mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - mtime ))
    if (( age < ttl )); then
      declare -A F=()
      local k v
      while IFS='=' read -r k v; do
        [[ -n "$k" ]] && F[$k]="$v"
      done < "$flag"

      remaining=$(( ttl - age ))
      rem_min=$(( remaining / 60 ))
      rem_sec=$(( remaining % 60 ))

      local ws=${F[ws]:-} ws_label=""
      case "$ws" in
        special:*) ws_label="scratch:${ws#special:}" ;;
        "")        ws_label="" ;;
        *)         ws_label="ws$ws" ;;
      esac
      if [[ -n "$ws_label" ]]; then
        text="󰌾 $ws_label"
      else
        text="󰌾"
      fi

      tt="sudo cache active — ~${rem_min}m ${rem_sec}s left"
      tt+="\\nuser: ${F[user]:-?}"
      [[ -n "${F[tty]:-}" && "${F[tty]:-}" != "?" ]] && tt+="\\ntty:  ${F[tty]}"
      [[ -n "$ws" ]] && tt+="\\nws:   $ws"
      [[ -n "${F[addr]:-}" ]] && tt+="\\naddr: ${F[addr]}"

      local text_json tooltip_json
      text_json=$(jq -Rn --arg t "$text" '$t')
      tooltip_json=$(jq -Rn --arg t "$tt" '$t' | sed 's/\\\\n/\\n/g')
      printf '{"text":%s,"alt":"active","class":"active","tooltip":%s}\n' \
        "$text_json" "$tooltip_json"
      return 0
    fi
  fi
  printf '{"text":"","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
}

# Event loop. emit_state happens on:
#   - startup (initial state)
#   - any inotify event in flag_dir
#   - exact TTL deadline (timeout fires before any inotify event)
while true; do
  emit_state

  if [[ -f "$flag" ]]; then
    mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - mtime ))
    sleep_for=$(( ttl - age ))
    (( sleep_for < 1 )) && sleep_for=1
    wait_or_event "$sleep_for"
  else
    # No flag — wait for one to appear (no TTL applies).
    if (( have_inotify )); then
      inotifywait -qq -e create,moved_to "$flag_dir" 2>/dev/null || sleep 5
    else
      sleep 5
    fi
  fi
done

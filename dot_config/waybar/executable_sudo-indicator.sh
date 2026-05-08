#!/usr/bin/env bash
# sudo-indicator — waybar custom module + click handler.
#
# Reads /run/user/$UID/sudo-active maintained by pam_exec via
# /usr/local/bin/sudo-flag.sh. The flag is refreshed (not deleted) on every
# PAM event; the user-space TTL (default 300s = sudo's cache lifetime)
# decides "active" vs "idle". Survives the `sudo true` <100ms-session race.
#
# Flag format — one `key=value` per line:
#   user=<PAM_RUSER>
#   epoch=<unix_ts>
#   type=<PAM_TYPE>
#   tty=<PAM_TTY>
#   addr=<hyprland window address, may be empty>
#   ws=<hyprland workspace name, may be empty>
#
# Modes:
#   (default)  emit waybar JSON {text, tooltip, class}
#   focus      hyprctl dispatch focuswindow on the captured address
set -u

flag="/run/user/$(id -u)/sudo-active"
ttl=${SUDO_CACHE_SEC:-300}

# Read flag into associative array. Returns 1 if missing/expired/invalid.
read_flag() {
  [[ -f "$flag" ]] || return 1
  local mtime age
  mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
  (( age < ttl )) || return 1
  declare -gA F=()
  local k v
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && F[$k]="$v"
  done < "$flag"
  AGE=$age
  return 0
}

case "${1:-}" in
  focus)
    if read_flag && [[ -n "${F[addr]:-}" ]]; then
      hyprctl dispatch focuswindow "address:${F[addr]}" >/dev/null 2>&1 || true
    fi
    exit 0
    ;;
  ""|check)
    if read_flag; then
      remaining=$(( ttl - AGE ))
      rem_min=$(( remaining / 60 ))
      rem_sec=$(( remaining % 60 ))

      # Bar text: lock + workspace badge if we captured one.
      ws=${F[ws]:-}
      if [[ -n "$ws" ]]; then
        # Strip 'special:' prefix for compactness; show as e.g. ws3 or scratch
        case "$ws" in
          special:*) ws_label="scratch:${ws#special:}" ;;
          *)         ws_label="ws$ws" ;;
        esac
        text="󰌾 $ws_label"
      else
        text="󰌾"
      fi

      # Tooltip — full breakdown.
      tt="sudo cache active — ~${rem_min}m ${rem_sec}s left"
      tt+="\\nuser: ${F[user]:-?}"
      [[ -n "${F[tty]:-}" && "${F[tty]:-}" != "?" ]] && tt+="\\ntty:  ${F[tty]}"
      [[ -n "$ws" ]] && tt+="\\nws:   $ws"
      [[ -n "${F[addr]:-}" ]] && tt+="\\naddr: ${F[addr]}"

      # JSON-encode safely (text + tooltip may contain special chars).
      text_json=$(jq -Rn --arg t "$text" '$t')
      tooltip_json=$(jq -Rn --arg t "$tt" '$t' | sed 's/\\\\n/\\n/g')
      printf '{"text":%s,"alt":"active","class":"active","tooltip":%s}\n' \
        "$text_json" "$tooltip_json"
      exit 0
    fi
    # Idle pill: emit a dim lock glyph so the chrome stays visible
    # whether sudo is active or not. Empty `text` would render as a
    # zero-width module → looks "missing". CSS dims via #custom-sudo.idle.
    printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
    ;;
  *)
    echo "usage: $0 [check|focus]" >&2
    exit 2
    ;;
esac

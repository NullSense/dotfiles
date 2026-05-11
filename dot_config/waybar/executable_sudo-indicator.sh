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
      # failed = sudo daemon detected prompt→idle without running.
      # Brief red flash, self-expires after 3s.
      if [[ "${F[type]:-}" == "failed" ]]; then
        if (( AGE > 3 )); then
          rm -f "$flag" 2>/dev/null || true
          printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"sudo locked"}\n'
          exit 0
        fi
        printf '{"text":"󰌾 ✗","alt":"failed","class":"failed","tooltip":"sudo authentication failed\\nuser: %s\\ntty:  %s"}\n' \
          "${F[user]:-?}" "${F[tty]:-?}"
        exit 0
      fi

      # auth_prompt = sudo is asking for password right now. Two ways to
      # clear: (1) sudo PID disappears (Ctrl+C, terminal closed, sudo
      # exited with auth fail), (2) prompt has been pending too long
      # (PROMPT_TTL — covers stuck states / unreliable PID checks).
      if [[ "${F[type]:-}" == "auth_prompt" ]]; then
        prompt_ttl=${SUDO_PROMPT_TTL:-60}
        sudo_pid=${F[sudo_pid]:-}
        if [[ -n "$sudo_pid" ]] && ! kill -0 "$sudo_pid" 2>/dev/null; then
          rm -f "$flag" 2>/dev/null || true
          printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"sudo locked"}\n'
          exit 0
        fi
        if (( AGE > prompt_ttl )); then
          rm -f "$flag" 2>/dev/null || true
          printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"sudo locked"}\n'
          exit 0
        fi
        # Closed lock + ellipsis. Workspace badge if known so user sees
        # which terminal is asking — captured by /usr/local/bin/sudo-prompt.sh.
        ws=${F[ws]:-}
        ws_label=""
        [[ -n "$ws" ]] && case "$ws" in
          special:*) ws_label="scratch:${ws#special:}" ;;
          *)         ws_label="ws$ws" ;;
        esac
        if [[ -n "$ws_label" ]]; then text="󰌾 $ws_label …"; else text="󰌾 …"; fi
        tt="sudo asking for password"
        [[ -n "$ws_label" ]] && tt+="\\nws:   $ws"
        tt+="\\nuser: ${F[user]:-?}"
        [[ -n "${F[tty]:-}" && "${F[tty]:-}" != "?" ]] && tt+="\\ntty:  ${F[tty]}"
        text_json=$(jq -Rn --arg t "$text" '$t')
        tooltip_json=$(jq -Rn --arg t "$tt" '$t' | sed 's/\\\\n/\\n/g')
        printf '{"text":%s,"alt":"prompt","class":"prompt","tooltip":%s}\n' \
          "$text_json" "$tooltip_json"
        exit 0
      fi

      remaining=$(( ttl - AGE ))
      rem_min=$(( remaining / 60 ))
      rem_sec=$(( remaining % 60 ))

      # Bar text + class differ for "running now" vs "cache active":
      #   open_session  → running   bright + ws label
      #   close_session → cached    dim,    no ws (sudo done, cache warm)
      kind=${F[type]:-}
      ws=${F[ws]:-}
      ws_label=""
      [[ -n "$ws" ]] && case "$ws" in
        special:*) ws_label="scratch:${ws#special:}" ;;
        *)         ws_label="ws$ws" ;;
      esac

      if [[ "$kind" == "close_session" ]]; then
        # Cache warm but no command running. Render IDENTICALLY to the
        # idle state — closed lock, no badge — so the pill doesn't sit
        # on the bar for 5 minutes after every `sudo <cmd>`. The flag is
        # still tracked by sudo-pill-daemon for proper state transitions
        # (idle → cached → prompt etc.). The cache-remaining time is
        # surfaced via tooltip-on-hover for users who actually want it.
        tt="sudo locked\\n(cache active for next sudo: ~${rem_min}m ${rem_sec}s)"
        tooltip_json=$(jq -Rn --arg t "$tt" '$t' | sed 's/\\\\n/\\n/g')
        printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":%s}\n' "$tooltip_json"
        exit 0
      fi

      # open_session — command actually running with elevated privs.
      # OPEN lock + active class to make "actively using sudo" obvious.
      if [[ -n "$ws_label" ]]; then text="󰿆 $ws_label"; else text="󰿆"; fi
      class="active"
      tt="sudo running with elevated privs — cache ~${rem_min}m ${rem_sec}s"
      tt+="\\nuser: ${F[user]:-?}"
      [[ -n "${F[tty]:-}" && "${F[tty]:-}" != "?" ]] && tt+="\\ntty:  ${F[tty]}"
      [[ -n "$ws" ]] && tt+="\\nws:   $ws"
      [[ -n "${F[addr]:-}" ]] && tt+="\\naddr: ${F[addr]}"

      text_json=$(jq -Rn --arg t "$text" '$t')
      tooltip_json=$(jq -Rn --arg t "$tt" '$t' | sed 's/\\\\n/\\n/g')
      printf '{"text":%s,"alt":"%s","class":"%s","tooltip":%s}\n' \
        "$text_json" "$class" "$class" "$tooltip_json"
      exit 0
    fi
    # Idle: closed lock, dim. Means "sudo will require password if invoked".
    printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"sudo locked — password required for next sudo"}\n'
    ;;
  *)
    echo "usage: $0 [check|focus]" >&2
    exit 2
    ;;
esac

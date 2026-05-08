#!/usr/bin/env bash
# sudo-watch — waybar streaming module. Long-running event loop that
# emits one JSON line per state transition. Zero polling — every event
# source is kernel-driven (no periodic stat-the-world).
#
# Event sources, all event-driven:
#   inotifywait -t  → file create/modify/delete  AND  TTL deadline
#                     (the timeout doubles as our deadline timer; when
#                     the flag's TTL elapses with no file event, inotifywait
#                     exits via timeout and the loop emits the new idle state)
#   tail --pid      → sudo process death (during auth_prompt). Touches a
#                     sentinel inside flag_dir on death, which trips the
#                     same inotifywait → no separate select-loop needed.
#
# waybar config:
#   "interval": "once"   ← streaming; the canonical waybar string form.
#                          Custom modules with `interval: 0` (numeric) are
#                          undefined behaviour — sometimes treated as "poll
#                          forever" depending on version.
#
# Requires inotify-tools. Falls back gracefully (sleep loop) without it.
set -u

flag="/run/user/$(id -u)/sudo-active"
flag_dir=$(dirname "$flag")
pid_marker="$flag_dir/.sudo-pill-pid-died"
ttl=${SUDO_CACHE_SEC:-300}
prompt_ttl=${SUDO_PROMPT_TTL:-60}

mkdir -p "$flag_dir"
rm -f "$pid_marker" 2>/dev/null || true

# Background subprocess registry — kill them all on exit.
WATCHERS=()
cleanup() {
  local pid
  for pid in "${WATCHERS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -f "$pid_marker" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

have_inotify=0
command -v inotifywait >/dev/null 2>&1 && have_inotify=1

# ── state computation ──────────────────────────────────────────────────────
read_flag() {
  declare -gA F=()
  AGE=0
  [[ -f "$flag" ]] || return 1
  local mtime k v
  mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
  AGE=$(( $(date +%s) - mtime ))
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && F[$k]="$v"
  done < "$flag"
  return 0
}

emit_state() {
  if read_flag; then
    local kind=${F[type]:-}

    if [[ "$kind" == "auth_prompt" ]]; then
      local sudo_pid=${F[sudo_pid]:-}
      # Cancel detection: sudo died → clear & idle.
      if [[ -n "$sudo_pid" ]] && ! kill -0 "$sudo_pid" 2>/dev/null; then
        rm -f "$flag" 2>/dev/null
        printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
        return
      fi
      # Stuck-prompt fallback.
      if (( AGE > prompt_ttl )); then
        rm -f "$flag" 2>/dev/null
        printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
        return
      fi
      printf '{"text":"󰌾 …","alt":"prompt","class":"prompt","tooltip":"sudo is asking for your password\\nuser: %s\\ntty:  %s"}\n' \
        "${F[user]:-?}" "${F[tty]:-?}"
      return
    fi

    # Active state — auth succeeded, cache fresh.
    if (( AGE < ttl )); then
      local remaining rem_min rem_sec ws ws_label text tt
      remaining=$(( ttl - AGE ))
      rem_min=$(( remaining / 60 ))
      rem_sec=$(( remaining % 60 ))
      ws=${F[ws]:-}
      case "$ws" in
        special:*) ws_label="scratch:${ws#special:}" ;;
        "")        ws_label="" ;;
        *)         ws_label="ws$ws" ;;
      esac
      [[ -n "$ws_label" ]] && text="󰌾 $ws_label" || text="󰌾"
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
      return
    fi
  fi

  # Idle: dim lock so the pill chrome stays visible.
  printf '{"text":"󰌾","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
}

# ── PID-death watcher ──────────────────────────────────────────────────────
# Spawns one `tail --pid=$sudo_pid` per call. When sudo dies, touches the
# sentinel inside flag_dir, which trips inotifywait below → loop iterates,
# emit_state sees the dead PID and emits idle.
spawn_pid_watcher() {
  local sudo_pid="$1"
  [[ -z "$sudo_pid" ]] && return
  kill -0 "$sudo_pid" 2>/dev/null || return
  ( tail --pid="$sudo_pid" -f /dev/null 2>/dev/null
    touch "$pid_marker" 2>/dev/null
    rm -f "$pid_marker" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  WATCHERS+=("$!")
}

# ── main event loop ────────────────────────────────────────────────────────
while true; do
  emit_state

  # Determine the timeout for inotifywait — the moment at which the current
  # state would expire absent any other event. inotifywait's -t flag handles
  # this in-kernel (timerfd), so this is event-driven, not polling.
  read_flag || true
  if [[ "${F[type]:-}" == "auth_prompt" ]]; then
    timeout=$(( prompt_ttl - AGE ))
    spawn_pid_watcher "${F[sudo_pid]:-}"
  elif [[ -f "$flag" ]] && (( AGE < ttl )); then
    timeout=$(( ttl - AGE ))
  else
    timeout=0   # idle — no deadline, just wait for the next event
  fi
  (( timeout < 1 )) && timeout=0   # 0 = wait forever in inotifywait

  if (( have_inotify )); then
    if (( timeout > 0 )); then
      inotifywait -qq -t "$timeout" \
        -e modify,create,delete,close_write,moved_to \
        "$flag_dir" 2>/dev/null || true
    else
      inotifywait -qq \
        -e modify,create,delete,close_write,moved_to \
        "$flag_dir" 2>/dev/null || true
    fi
  else
    # Degraded fallback: sleep until the deadline (or a longer stretch when
    # idle, since we have no way to wake on file events).
    if (( timeout > 0 )); then sleep "$timeout"; else sleep 5; fi
  fi

  # Reap any pid watchers that finished. Active ones survive — they'll be
  # reaped on the next iteration after sudo death triggers a re-emit.
  for i in "${!WATCHERS[@]}"; do
    kill -0 "${WATCHERS[$i]}" 2>/dev/null || unset "WATCHERS[$i]"
  done
done

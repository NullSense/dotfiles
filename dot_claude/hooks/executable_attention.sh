#!/usr/bin/env bash
# attention.sh — manage a Hyprland window tag for the calling agent's terminal.
#
# Tag-based mechanism (vs OSC-2 title sentinels) because TUIs like Claude
# Code rewrite their own window title constantly; Hyprland tags are
# out-of-band and survive any title rewrite.
#
# Walks the hook's own process tree to find BOTH:
#   1. The agent binary (claude / codex / opencode / gemini / copilot / aider)
#      → derives agent-id automatically. No need to pass it from the hook.
#   2. The parent terminal emulator (ghostty / alacritty / foot / kitty /
#      wezterm / st) → derives the Hyprland window address.
#
# So every agent's hook config is identical: `attention.sh set` / `clear`.
# That's the DRY win — wire the same two lines into every agent's hooks
# and the script figures out which agent and which window.
#
# Usage:
#   attention.sh set [<agent-id>]      # auto-detects agent if not given
#   attention.sh clear [<agent-id>]
#
# The optional <agent-id> override is for cases where the hook runs in a
# wrapper (e.g. `bash -c '...'`) that loses the agent in $PPID's comm.
#
# Border rule lives in ~/.config/hypr/windows.conf:
#   windowrule = border_color rgb(FF3344) rgb(880808), match:tag attention-<id>
set -u

action="${1:-}"
agent_override="${2:-}"
[[ -z "$action" ]] && { echo "usage: $0 {set|clear} [agent-id]" >&2; exit 2; }

# Map a process comm name to a known agent-id. Empty = not a known agent.
agent_for_comm() {
  case "$1" in
    claude|claude-code|claude-cli)        echo claude   ;;
    codex|codex-cli)                       echo codex    ;;
    opencode|opencode-cli)                 echo opencode ;;
    gemini|gemini-cli|gcli)                echo gemini   ;;
    copilot|gh-copilot|github-copilot-cli) echo copilot  ;;
    aider)                                 echo aider    ;;
    *) echo "" ;;
  esac
}

# Map a process comm name to a known terminal. Empty = not a terminal.
is_terminal() {
  case "$1" in
    ghostty|alacritty|foot|kitty|wezterm|st|kitty-wrapped) return 0 ;;
    *) return 1 ;;
  esac
}

# Walk the process tree from PPID upward, capturing the first agent and the
# first terminal we encounter. Stop at PID 1.
agent_id="$agent_override"
term_pid=""
pid=$PPID
while [[ -n "$pid" && "$pid" != "1" ]]; do
  comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "")
  if [[ -z "$agent_id" ]]; then
    detected=$(agent_for_comm "$comm")
    [[ -n "$detected" ]] && agent_id="$detected"
  fi
  if [[ -z "$term_pid" ]] && is_terminal "$comm"; then
    term_pid="$pid"
  fi
  [[ -n "$agent_id" && -n "$term_pid" ]] && break
  pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo "")
done

# Both must be known to proceed.
if [[ -z "$agent_id" || -z "$term_pid" ]]; then
  exit 0
fi
tag="attention-$agent_id"

# Find the Hyprland window whose .pid matches the terminal.
addr=$(hyprctl clients -j 2>/dev/null | \
  jq -r --arg p "$term_pid" '.[] | select(.pid == ($p|tonumber)) | .address' | head -1)
[[ -z "$addr" ]] && exit 0

case "$action" in
  set)   hyprctl dispatch    tagwindow "+$tag" "address:$addr" >/dev/null 2>&1 || true ;;
  clear) hyprctl dispatch -- tagwindow "-$tag" "address:$addr" >/dev/null 2>&1 || true ;;
  *)     echo "usage: $0 {set|clear} [agent-id]" >&2; exit 2 ;;
esac

# Desktop notification (mako/dunst/whatever org.freedesktop.Notifications
# is registered). Per-agent replace-id so repeated firings for the same
# agent overwrite rather than stack. On `clear`, send a 1ms expire-time
# empty notification with the same id to dismiss any open one.
notify_id=$(( $(printf '%s' "$agent_id" | cksum | awk '{print $1}') % 65000 + 30000 ))
case "$action" in
  set)
    case "$agent_id" in
      claude)   icon=face-monkey;     pretty="Claude" ;;
      codex)    icon=applications-development; pretty="Codex" ;;
      opencode) icon=applications-development; pretty="OpenCode" ;;
      gemini)   icon=face-cool;       pretty="Gemini" ;;
      copilot)  icon=face-smile;      pretty="Copilot" ;;
      aider)    icon=applications-development; pretty="Aider" ;;
      *)        icon=dialog-information; pretty="$agent_id" ;;
    esac
    notify-send \
      --urgency=normal \
      --replace-id="$notify_id" \
      --icon="$icon" \
      --app-name="$pretty" \
      --hint="string:x-canonical-private-synchronous:agent-$agent_id" \
      "$pretty needs you" \
      "waiting for your input" \
      2>/dev/null || true
    ;;
  clear)
    # Close any open notification for this agent without queuing a new one.
    notify-send \
      --replace-id="$notify_id" \
      --hint="string:x-canonical-private-synchronous:agent-$agent_id" \
      --expire-time=1 \
      "" "" 2>/dev/null || true
    ;;
esac

pkill -SIGRTMIN+8 waybar 2>/dev/null || true
exit 0

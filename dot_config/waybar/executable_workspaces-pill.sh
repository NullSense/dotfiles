#!/usr/bin/env bash
# workspaces-pill — custom waybar workspace indicator with attention coloring.
#
# Replaces the built-in `hyprland/workspaces` module to gain dynamic per-number
# Pango coloring driven by Hyprland tags (the same `attention-<agent>` tag
# scheme that drives custom/agents). waybar's static `format-icons` cannot
# express this — every state change would need a config-reload.
#
# Output (waybar JSON):
#   text     Pango-marked-up "1 2 3 4 5 6" with each digit colored per state
#   tooltip  multi-line per-workspace summary (real \n, not literal)
#   class    css hook (`workspaces` + `attention` when at least one ws is lit)
#
# Color palette (gruvbox-aligned, matches style.css tokens):
#   active+focused-monitor : @yellow  (#fabd2f) bold
#   active+other-monitor   : @aqua    (#8ec07c)
#   attention              : agent brand color (claude=#D97757, etc.)
#   has windows            : @fg3     (#a89984)
#   empty / persistent     : @bg4     (#504945)
#
# Modes:
#   (default) check  emit JSON status
#   focus-attention  jump to first workspace with an attention tag
#   next / prev      step workspace e+1 / e-1 (used by waybar scroll handlers)
#
# Refresh model: signal-driven via SIGRTMIN+8 (shared with custom/agents).
# `~/.local/bin/hypr-waybar-bridge` listens on Hyprland's socket2 and signals
# waybar on relevant events (workspace, openwindow, urgent, monitor*, ...).
# Hooks that change attention tags (claude/codex/etc.) already fire the same
# signal, so no duplicated wiring.
set -u

TAG_PREFIX='attention-'

# Per-agent brand colors. Keep aligned with agent-attention.sh AGENT_TABLE
# and aiquota's icons.rs MANIFEST so the bar shares one identity vocabulary.
declare -A AGENT_COLORS=(
  [claude]="#D97757"
  [codex]="#10A37F"
  [opencode]="#FF5C00"
  [gemini]="#8E75B2"
  [copilot]="#6E5494"
)

# Ordered list of workspaces to always show (matches the union of the
# `persistent-workspaces` map previously declared in config.jsonc for both
# monitors). Ad-hoc workspaces (created on the fly) are appended at the end
# only while they exist.
PERSISTENT_WS=(1 2 3 4 5 6)

# Gruvbox-ish hex picks. Hardcoded because Pango markup doesn't accept
# GTK @define-color tokens. If you reskin the bar, retune these.
COLOR_ACTIVE_FOCUSED="#fabd2f"   # yellow / theme accent
COLOR_ACTIVE_OTHER="#8ec07c"     # aqua — active on a non-focused monitor
COLOR_OCCUPIED="#a89984"         # fg3 — has windows but not active
COLOR_EMPTY="#504945"            # bg4 — empty / unfocused-persistent

usage() {
  cat <<'EOF' >&2
usage: workspaces-pill.sh [check|focus-attention|next|prev]
EOF
  exit 2
}

case "${1:-check}" in
  next)              hyprctl dispatch workspace e+1 >/dev/null 2>&1 || true; exit 0 ;;
  prev)              hyprctl dispatch workspace e-1 >/dev/null 2>&1 || true; exit 0 ;;
  focus-attention)
    addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg pre "$TAG_PREFIX" '
      [.[] | select((.tags // []) | any(startswith($pre)))][0].address // empty')
    [[ -n "$addr" ]] && hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
    exit 0 ;;
  check|"")          ;;
  *)                 usage ;;
esac

monitors=$(hyprctl monitors -j 2>/dev/null || echo '[]')
workspaces=$(hyprctl workspaces -j 2>/dev/null || echo '[]')
clients=$(hyprctl clients -j 2>/dev/null || echo '[]')

# Active workspace on the focused monitor (the one the user is "on").
focused_ws=$(jq -r '[.[] | select(.focused)][0].activeWorkspace.id // empty' <<<"$monitors")

# All monitors' active workspaces (space-separated for grep -w).
active_wses=$(jq -r '[.[].activeWorkspace.id] | join(" ")' <<<"$monitors")

# Workspaces that contain at least one window.
populated_wses=$(jq -r '[.[] | select(.windows > 0) | .id] | join(" ")' <<<"$workspaces")

# Build the dynamic-extras list: any non-special workspace currently
# present that isn't already in PERSISTENT_WS. Sorted numerically.
all_real_wses=$(jq -r '[.[] | select(.id > 0) | .id] | sort | unique | .[]' <<<"$workspaces")
extra_wses=()
for w in $all_real_wses; do
  in_persistent=0
  for p in "${PERSISTENT_WS[@]}"; do [[ "$p" == "$w" ]] && { in_persistent=1; break; }; done
  (( in_persistent )) || extra_wses+=("$w")
done

# Render a single workspace number with state-appropriate Pango markup.
# Emits "STATE\tMARKUP" on stdout (tab-separated). Caller splits with `cut`.
# State is returned in-band rather than via a global because the typical
# call site is `parts+=("$(render_ws ...)")` — that subshell would discard
# any global the function set.
render_ws() {
  local ws="$1"
  local color weight_open weight_close
  local agents state
  agents=$(jq -r --arg pre "$TAG_PREFIX" --arg ws "$ws" '
    .[] | select(.workspace.id == ($ws|tonumber)) | (.tags // [])[] |
    select(startswith($pre)) | sub("^"+$pre; "")' <<<"$clients" | sort -u | tr '\n' ' ')
  agents="${agents% }"

  if [[ -n "$agents" ]]; then
    # First agent's brand color; multi-agent workspaces are rare and the
    # tooltip lists every agent regardless. Attention overrides focus
    # color, but if the user is also currently on this workspace we
    # underline so the "where am I" cue isn't lost.
    local primary="${agents%% *}"
    color="${AGENT_COLORS[$primary]:-#fb4934}"
    if [[ "$ws" == "$focused_ws" ]]; then
      weight_open='<b><u>'; weight_close='</u></b>'
    else
      weight_open='<b>'; weight_close='</b>'
    fi
    state="attention:$agents"
  elif [[ "$ws" == "$focused_ws" ]]; then
    color="$COLOR_ACTIVE_FOCUSED"
    weight_open='<b>'; weight_close='</b>'
    state="active-focused"
  elif [[ " $active_wses " == *" $ws "* ]]; then
    color="$COLOR_ACTIVE_OTHER"
    weight_open=''; weight_close=''
    state="active-other"
  elif [[ " $populated_wses " == *" $ws "* ]]; then
    color="$COLOR_OCCUPIED"
    weight_open=''; weight_close=''
    state="occupied"
  else
    color="$COLOR_EMPTY"
    weight_open=''; weight_close=''
    state="empty"
  fi
  printf '%s\t<span foreground="%s">%s%s%s</span>' \
    "$state" "$color" "$weight_open" "$ws" "$weight_close"
}

# Snapshot the windows currently in a workspace, for the tooltip.
ws_titles() {
  local ws="$1"
  jq -r --arg ws "$ws" '
    .[] | select(.workspace.id == ($ws|tonumber)) |
    "  \(.title // .class // "?")"' <<<"$clients"
}

parts=()
tooltip_lines=()
any_attention=0
for ws in "${PERSISTENT_WS[@]}" "${extra_wses[@]}"; do
  rendered=$(render_ws "$ws")
  state="${rendered%%$'\t'*}"
  markup="${rendered#*$'\t'}"
  parts+=("$markup")

  case "$state" in
    attention:*)
      any_attention=1
      agents="${state#attention:}"
      tooltip_lines+=("ws $ws — attention: $agents")
      while IFS= read -r t; do
        [[ -n "$t" ]] && tooltip_lines+=("$t")
      done < <(ws_titles "$ws")
      ;;
    active-focused) tooltip_lines+=("ws $ws — active (focused)") ;;
    active-other)   tooltip_lines+=("ws $ws — active (other monitor)") ;;
    occupied)
      tooltip_lines+=("ws $ws — occupied")
      while IFS= read -r t; do
        [[ -n "$t" ]] && tooltip_lines+=("$t")
      done < <(ws_titles "$ws")
      ;;
    empty)          tooltip_lines+=("ws $ws — empty") ;;
  esac
done

text=$(IFS=' '; printf '%s' "${parts[*]}")

# Real newlines so jq encodes them as JSON \n, which waybar parses back into
# Pango line breaks. Earlier iterations used literal "\n" two-char strings
# and ended up rendering "\n" verbatim in the tooltip.
tooltip=$(printf '%s\n' "${tooltip_lines[@]}")

class="workspaces"
(( any_attention )) && class="$class attention"

text_json=$(jq -Rn --arg t "$text" '$t')
tooltip_json=$(jq -Rn --arg t "$tooltip" '$t')
printf '{"text":%s,"tooltip":%s,"class":"%s"}\n' \
  "$text_json" "$tooltip_json" "$class"

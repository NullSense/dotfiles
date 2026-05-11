#!/usr/bin/env bash
# agent-attention — waybar custom module + click handler.
#
# Discovers pending-agent windows by Hyprland tag (`attention-<agent-id>`).
# Tags are set/cleared by per-agent hooks (~/.claude/hooks/attention.sh and
# equivalents for codex/opencode/gemini/copilot). Tag-based mechanism
# instead of OSC-2 title sentinels because Claude Code's TUI rewrites its
# own title constantly — tags survive that.
#
# Pill format (Pango markup):
#   <count><brand-glyph>  per agent, brand-colored, joined by double-space
# e.g. `2 1 1 󰲾`
# Idle: shows a dim Nerd Font robot glyph so the pill stays visible.
#
# Modes:
#   (default)    emit waybar JSON {text, tooltip, class}
#   focus        focus the pending window; if >1, walker-dmenu picker
#   dismiss-all  clears every attention-* tag across all windows
set -u

TAG_PREFIX='attention-'

# Per-agent branding. Keep aligned with ~/code/aiquota/src/icons.rs MANIFEST
# so the bar / aiquota / hooks share one identity vocabulary.
#   id|fa_brand_glyph|fallback_nf_glyph|brand_color
# fa_brand_glyph empty = no FA7 entry, render fallback in default font.
AGENT_TABLE=(
  "claude||󰹜|#D97757"
  "codex||󰦆|#10A37F"
  "opencode||󰊘|#FF5C00"
  "gemini||󰺾|#8E75B2"
  "copilot||󰐈|#6E5494"
)

clients_json() { hyprctl clients -j 2>/dev/null; }

# Returns array of {address, ws, title, agent} for every window that has
# at least one `attention-<agent>` tag. Multi-tagged windows expand to one
# entry per attention tag (rare, but possible if two agents share a term).
pending_array() {
  clients_json | jq --arg pre "$TAG_PREFIX" -c '
    [.[] |
      . as $w |
      (.tags // []) |
      map(select(startswith($pre))) |
      map({
        address: $w.address,
        ws: $w.workspace.name,
        title: $w.title,
        agent: (. | sub("^" + $pre; ""))
      }) |
      .[]
    ]'
}

# Pango markup for a single agent badge: "<count><colored-glyph>".
render_agent() {
  local id="$1" count="$2"
  local row rid fa nf color
  for row in "${AGENT_TABLE[@]}"; do
    IFS='|' read -r rid fa nf color <<<"$row"
    [[ "$rid" == "$id" ]] || continue
    if [[ -n "$fa" ]]; then
      printf '<span foreground="%s">%d</span><span foreground="%s" face="Font Awesome 7 Brands">%b</span>' \
        "$color" "$count" "$color" "$fa"
    else
      printf '<span foreground="%s">%d %b</span>' "$color" "$count" "$nf"
    fi
    return 0
  done
  printf '<span>%d %s</span>' "$count" "$id"
}

case "${1:-}" in
  focus)
    arr=$(pending_array)
    n=$(jq 'length' <<<"$arr")
    if [[ "$n" == "0" ]]; then exit 0; fi
    if [[ "$n" == "1" ]]; then
      addr=$(jq -r '.[0].address' <<<"$arr")
      hyprctl dispatch focuswindow "address:$addr" >/dev/null
      exit 0
    fi
    pick=$(jq -r '.[] | "\(.address)\t\(.agent)\tws \(.ws)\t\(.title)"' <<<"$arr" \
            | walker --dmenu --placeholder "Pending agents")
    [[ -z "$pick" ]] && exit 0
    addr=$(awk -F'\t' '{print $1}' <<<"$pick")
    hyprctl dispatch focuswindow "address:$addr" >/dev/null
    ;;
  dismiss-all)
    # Strip every attention-* tag from every window — useful if a hook
    # crashed leaving a stale tag behind.
    while IFS=$'\t' read -r addr tag; do
      [[ -z "$addr" || -z "$tag" ]] && continue
      hyprctl dispatch -- tagwindow "-$tag" "address:$addr" >/dev/null 2>&1 || true
    done < <(clients_json | jq -r --arg pre "$TAG_PREFIX" \
      '.[] | . as $w | (.tags // [])[] | select(startswith($pre)) | "\($w.address)\t\(.)"')
    pkill -SIGRTMIN+8 waybar 2>/dev/null || true
    notify-send -t 1500 "agent-attention" "Cleared all pending tags."
    ;;
  ""|check)
    arr=$(pending_array)
    n=$(jq 'length' <<<"$arr")
    if [[ "$n" == "0" ]]; then
      # Dim placeholder so the pill stays visible (system armed, idle).
      printf '{"text":"󰚩","alt":"idle","class":"idle","tooltip":"No agents waiting"}\n'
      exit 0
    fi

    # Aggregate counts per agent_id, render in stable order from AGENT_TABLE.
    declare -A counts=()
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      counts[$id]=$(( ${counts[$id]:-0} + 1 ))
    done < <(jq -r '.[].agent' <<<"$arr")

    parts=()
    for row in "${AGENT_TABLE[@]}"; do
      rid=${row%%|*}
      [[ -n "${counts[$rid]:-}" ]] || continue
      parts+=("$(render_agent "$rid" "${counts[$rid]}")")
    done
    # Surface unknown agents (no AGENT_TABLE entry) at the end so they don't
    # silently disappear from the count.
    for k in "${!counts[@]}"; do
      seen=0
      for row in "${AGENT_TABLE[@]}"; do [[ "${row%%|*}" == "$k" ]] && seen=1; done
      [[ $seen == 0 ]] && parts+=("$(render_agent "$k" "${counts[$k]}")")
    done
    text=$(IFS='  '; printf '%s' "${parts[*]}")

    # Build the tooltip with REAL newlines, then let jq's --rawfile encode
    # them as JSON `\n` escapes. waybar parses those back into actual line
    # breaks for Pango. Previous version emitted literal "\n" (two chars)
    # which round-tripped to a literal `\n` in the rendered tooltip.
    tooltip=$(jq -r '.[] | "\(.agent) · ws \(.ws) — \(.title)"' <<<"$arr")

    text_json=$(jq -Rn --arg t "$text" '$t')
    tooltip_json=$(jq -Rn --arg t "$tooltip" '$t')
    printf '{"text":%s,"alt":"%s","class":"pending","tooltip":%s}\n' \
      "$text_json" "$n" "$tooltip_json"
    ;;
  *)
    echo "usage: $0 [check|focus|dismiss-all]" >&2
    exit 2
    ;;
esac

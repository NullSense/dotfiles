#!/usr/bin/env bash
# disk-usage.sh — waybar custom/disk module with a cached top-users breakdown.
#
# Usage:
#   disk-usage.sh pill <path> <label> <glyph>   # waybar JSON (fast: df only)
#   disk-usage.sh refresh <path> <label>        # recompute du cache (background)
#   disk-usage.sh ncdu <path>                   # open interactive ncdu
#
# The pill shows df %used INSTANTLY (df is a statfs call, ~1ms). The tooltip's
# ranked "top directories" list is EXPENSIVE (du walks the tree), so it is
# computed only when the user right-clicks the module.  Never launch a full
# filesystem walk merely because Waybar started: on a cold Btrfs boot that can
# contend with balance/swap activation and charge gigabytes of page cache to
# waybar.service.
set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$CACHE_DIR"

do_refresh() {  # <path> <label>  — heavy; runs under flock, writes <cache>
  local path=$1 label=$2
  local cache="$CACHE_DIR/disk-$label.tt"
  local lock="$CACHE_DIR/disk-$label.lock"
  exec 9>"$lock"
  flock -n 9 || exit 0         # another refresh already running
  # du -x: stay on this filesystem; -d1: one level; bytes for exact ranking.
  # Errors (unreadable dirs under /) are dropped. Top 8 by size, humanized.
  du -xd1 -B1 "$path" 2>/dev/null \
    | sort -rn \
    | sed '1d' \
    | head -8 \
    | awk '{
        b=$1; $1=""; sub(/^ /,"")
        h=b; u="B"
        if (b>=1073741824){h=b/1073741824;u="G"}
        else if (b>=1048576){h=b/1048576;u="M"}
        else if (b>=1024){h=b/1024;u="K"}
        name=$0; sub(/.*\//,"",name)
        printf "  <span color=\x27#8ec07c\x27>%6.1f%s</span>  %s\n", h, u, name
      }' > "$cache.tmp" && mv "$cache.tmp" "$cache"
}

case "${1:-}" in
  refresh)
    do_refresh "$2" "$3"
    exit 0
    ;;
  ncdu)
    # Detached (setsid -f): waybar waitpid()s the click handler and pauses
    # this module's polling until it exits — an exec'd terminal froze the
    # pill while the ncdu window stayed open. See gpu-status.sh.
    setsid -f alacritty --class=com.local.floating-monitor -e ncdu -x "$2" </dev/null &>/dev/null
    exit 0
    ;;
  pill) : ;;   # fall through
  *) echo '{"text":"?","tooltip":"usage: disk-usage.sh pill <path> <label> <glyph>"}'; exit 0 ;;
esac

# ---- pill mode ------------------------------------------------------------
path=$2; label=$3; glyph=${4:-}
cache="$CACHE_DIR/disk-$label.tt"

# df: used%, used, size (one statfs, instant).
read -r pcent usedh sizeh < <(df -h --output=pcent,used,size "$path" 2>/dev/null | tail -1)
pcent=${pcent%\%}; pcent=${pcent// /}
pcent=${pcent:-0}

if   (( pcent >= 90 )); then cls="crit"
elif (( pcent >= 75 )); then cls="warn"
else                         cls="ok"
fi

if [[ -f "$cache" ]]; then
  breakdown=$(cat "$cache")
  updated=$(date -r "$cache" '+%F %R' 2>/dev/null || echo unknown)
  staleness="  <span color='#928374'>(cached ${updated})</span>"
else
  breakdown="  <span color='#928374'>not scanned yet</span>"
  staleness=""
fi

tt="<b>${label}</b>  ${path}\n"
tt+="used   <b>${usedh}</b> / ${sizeh}   (${pcent}%)\n"
tt+="\n<b>Largest here</b>${staleness}\n${breakdown}\n"
tt+="\n  L-click  ncdu      R-click  refresh now"

tt=${tt//\\n/$'\n'}   # literal "\n" from double-quoted strings → real newline
tt=${tt//\\/\\\\}; tt=${tt//\"/\\\"}; tt=${tt//$'\n'/\\n}

printf '{"text":"%s  %s%%","tooltip":"%s","class":"%s","percentage":%s}\n' \
  "$glyph" "$pcent" "$tt" "$cls" "$pcent"

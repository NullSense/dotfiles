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
# computed off the hot path: the pill reads a cache file, and only kicks a
# detached, flock-guarded `du` job when the cache is missing or older than
# $TTL. So waybar never blocks on du; the breakdown just self-refreshes.
set -u

TTL=1800                       # cache lifetime, seconds (30 min)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$CACHE_DIR"

cache_age() {  # prints seconds since mtime, or a huge number if missing
  local f=$1
  [[ -f "$f" ]] || { echo 999999; return; }
  echo $(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
}

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
    exec alacritty --class=com.local.floating-monitor -e ncdu -x "$2"
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

# Kick a background refresh if the breakdown cache is stale/missing.
age=$(cache_age "$cache")
if (( age > TTL )); then
  setsid -f "$0" refresh "$path" "$label" >/dev/null 2>&1 || \
    ( "$0" refresh "$path" "$label" & ) >/dev/null 2>&1
fi

if [[ -f "$cache" ]]; then
  breakdown=$(cat "$cache")
  staleness=""
  (( age > TTL )) && staleness="  <span color='#928374'>(refreshing…)</span>"
else
  breakdown="  <span color='#928374'>computing…  (first run)</span>"
  staleness=""
fi

tt="<b>${label}</b>  ${path}\n"
tt+="used   <b>${usedh}</b> / ${sizeh}   (${pcent}%)\n"
tt+="\n<b>Largest here</b>${staleness}\n${breakdown}\n"
tt+="\n  L-click  ncdu      R-click  refresh now"

tt=${tt//\\/\\\\}; tt=${tt//\"/\\\"}; tt=${tt//$'\n'/\\n}

printf '{"text":"%s  %s%%","tooltip":"%s","class":"%s","percentage":%s}\n' \
  "$glyph" "$pcent" "$tt" "$cls" "$pcent"

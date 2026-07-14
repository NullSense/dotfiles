#!/usr/bin/env bash
# mem-status.sh — waybar custom/memory module.
#
# Pill:    <used>/<total>G   [ ⇄<swap>G ]   RAM used out of total; the swap
#          segment appears only when swap is actually in use (>0.1G) — on a
#          zram-only box swap is usually 0, and a permanent "S0.0G" is noise.
# Tooltip: RAM used/avail/total, cached, and swap; plus the top 5 RSS procs.
#
# Reads /proc/meminfo + /proc/*/statm — no fork of `free`/`ps` in the hot path
# for the numbers; the top-procs list uses one `ps` call (cheap, ~10ms).
set -u

case "${1:-}" in
  btop) exec alacritty --class=com.local.floating-monitor -e btop ;;
esac

# --- /proc/meminfo (values in kB) ------------------------------------------
declare -A M
while read -r key val _; do
  M[${key%:}]=$val
done < /proc/meminfo

kb_g() { awk -v k="$1" 'BEGIN{printf "%.1f", k/1048576}'; }
kb_g0() { awk -v k="$1" 'BEGIN{printf "%.0f", k/1048576}'; }

total=${M[MemTotal]:-0}
avail=${M[MemAvailable]:-0}
cached=$(( ${M[Cached]:-0} + ${M[SReclaimable]:-0} ))
used=$(( total - avail ))
swtotal=${M[SwapTotal]:-0}
swfree=${M[SwapFree]:-0}
swused=$(( swtotal - swfree ))

used_g=$(kb_g "$used"); total_g=$(kb_g0 "$total")
avail_g=$(kb_g "$avail"); cached_g=$(kb_g "$cached")
pct=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.0f", (t>0)? u*100/t : 0}')

# Swap segment only when meaningfully in use.
sw_seg=""
swused_g=$(kb_g "$swused")
if awk -v s="$swused" 'BEGIN{exit !(s>104857)}'; then   # >0.1G
  sw_seg="  <span color='#fabd2f'>⇄${swused_g}G</span>"
fi

if   (( pct >= 90 )); then cls="crit"
elif (( pct >= 75 )); then cls="warn"
else                       cls="ok"
fi

# --- Top RSS processes ------------------------------------------------------
top=$(ps -eo rss=,comm= --sort=-rss 2>/dev/null | head -5 | \
  awk "{ printf \"  <span color='#d3869b'>%5.1fG</span>  %s\n\", \$1/1048576, \$2 }")

tt="<b>RAM</b>   <b>${used_g}G</b> / ${total_g}G   (${pct}%)\n"
tt+="avail  ${avail_g}G      cached ${cached_g}G\n"
swpct=$(awk -v u="$swused" -v t="$swtotal" 'BEGIN{printf "%.0f", (t>0)? u*100/t : 0}')
tt+="swap   ${swused_g}G / $(kb_g0 "$swtotal")G   (${swpct}%)\n"
tt+="\n<b>Top memory</b>\n${top}\n"
tt+="\n  L-click  btop"

tt=${tt//\\n/$'\n'}   # literal "\n" from double-quoted strings → real newline
tt=${tt//\\/\\\\}; tt=${tt//\"/\\\"}; tt=${tt//$'\n'/\\n}

printf '{"text":"  %s/%sG%s","tooltip":"%s","class":"%s","percentage":%s}\n' \
  "$used_g" "$total_g" "$sw_seg" "$tt" "$cls" "$pct"

#!/usr/bin/env bash
# mem-status.sh — waybar custom/memory module.
#
# Pill:    <used>/<total>G   [ ⇄<swap>G ]   RAM used out of total; the swap
#          segment appears only when swap is actually in use (>0.1G) — on a
#          zram-only box swap is usually 0, and a permanent "S0.0G" is noise.
# Tooltip: RAM used/avail/total, cached, swap, shmem; top 5 apps by PSS; and
#          tmpfs mounts >512M — INCLUDING inside foreign mount namespaces
#          (bwrap/agent-isolated sandboxes get a private /tmp that no
#          per-process tool attributes; a sandboxed build tree once ate 25G
#          while every RSS/PSS list pointed at nothing).
#
# Reads /proc/meminfo + /proc/*/smaps_rollup; the tmpfs sweep is statvfs-only
# (O(1) per mount, deduped by superblock) — no du, safe at the 5s poll.
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
# Swap nearly full is a pressure signal in its own right (zram-only box:
# next spike goes straight to thrash/OOM) — escalate even if RAM% looks ok.
if [[ "$cls" != "crit" ]] && awk -v s="$swused" -v t="$swtotal" 'BEGIN{exit !(t>0 && s/t>0.9)}'; then
  cls="crit"
fi

# --- Top memory by APPLICATION + tmpfs sweep --------------------------------
# Two sections from one python run, split on a TMPFS marker line:
#  1. Top apps by aggregated PSS (a browser's dozens of renderer processes
#     roll into ONE honest number; PSS so shared pages aren't double-counted).
#  2. tmpfs mounts >512M across ALL reachable mount namespaces. Shmem pages
#     live in the page cache, not in any process — ps/btop/PSS are blind to
#     them, and sandbox (bwrap) namespaces hide even the mount. statvfs each
#     namespace's tmpfs mounts via /proc/<pid>/root, dedupe by superblock.
# Time-boxed: one process stuck in a D-state (its smaps_rollup read blocks on
# mmap_lock — routine during model loads / memory pressure) would otherwise
# wedge this poll forever, and waybar's run→wait→sleep loop freezes the pill
# on the stale value until the script exits. On timeout `out` comes back
# empty and the cheap ps-RSS fallback below fills the tooltip instead.
out=$(timeout -k 1 3 python3 - <<'PY' 2>/dev/null
import glob, os
agg = {}
for f in glob.glob('/proc/[0-9]*/smaps_rollup'):
    pid = f.split('/')[2]
    try:
        comm = open(f'/proc/{pid}/comm').read().strip()
        for line in open(f):
            if line.startswith('Pss:'):
                agg[comm] = agg.get(comm, 0) + int(line.split()[1])
                break
    except Exception:
        pass
for c, kb in sorted(agg.items(), key=lambda x: -x[1])[:5]:
    print(f"  <span color='#d3869b'>{kb/1048576:5.1f}G</span>  {c}")

print('TMPFS')
try:
    host_ns = os.readlink('/proc/self/ns/mnt')
except OSError:
    host_ns = ''
seen_ns, seen_sb, mounts = set(), set(), []
for nslink in glob.glob('/proc/[0-9]*/ns/mnt'):
    pid = nslink.split('/')[2]
    try:
        ns = os.readlink(nslink)
    except OSError:
        continue                      # other users' procs — not our RAM story
    if ns in seen_ns:
        continue
    seen_ns.add(ns)
    try:
        with open(f'/proc/{pid}/mountinfo') as f:
            rows = [l.split() for l in f if ' - tmpfs ' in l]
    except OSError:
        continue
    for r in rows:
        sb, mnt = r[2], r[4]          # major:minor = superblock, dedupes binds
        if sb in seen_sb:
            continue
        seen_sb.add(sb)
        path = f'/proc/{pid}/root{mnt}'
        try:
            maj, mn = (int(x) for x in sb.split(':'))
            # Path resolution can land on a DIFFERENT fs than the mountinfo
            # row claims (over-mounts, sandbox masks over $HOME) — then
            # statvfs would report a disk, not the tmpfs. Verify first.
            if os.stat(path).st_dev != os.makedev(maj, mn):
                continue
            v = os.statvfs(path)
        except (OSError, ValueError):
            continue
        used = (v.f_blocks - v.f_bfree) * v.f_frsize
        if used <= 512 * 2**20:
            continue
        label = mnt
        if ns != host_ns:
            try:
                comm = open(f'/proc/{pid}/comm').read().strip()
            except OSError:
                comm = '?'
            label += f"  <i>sandbox ns of {comm}/{pid}</i>"
        mounts.append((used, label))
for used, label in sorted(mounts, reverse=True)[:5]:
    print(f"  <span color='#fe8019'>{used/2**30:5.1f}G</span>  {label}")
PY
)
top=${out%%$'\n'TMPFS*}
tmpfs=${out#*TMPFS}; tmpfs=${tmpfs#$'\n'}
[[ "$tmpfs" == "$out" ]] && tmpfs=""
[[ -z "$top" ]] && top=$(ps -eo rss=,comm= 2>/dev/null | awk '{a[$2]+=$1} END{for(c in a)printf "%d %s\n",a[c],c}' | sort -rn | head -5 | awk "{printf \"  <span color='#d3869b'>%5.1fG</span>  %s\n\", \$1/1048576, \$2}")

shmem=${M[Shmem]:-0}
shmem_g=$(kb_g "$shmem")

tt="<b>RAM</b>   <b>${used_g}G</b> / ${total_g}G   (${pct}%)\n"
tt+="avail  ${avail_g}G      cached ${cached_g}G\n"
swpct=$(awk -v u="$swused" -v t="$swtotal" 'BEGIN{printf "%.0f", (t>0)? u*100/t : 0}')
tt+="swap   ${swused_g}G / $(kb_g0 "$swtotal")G   (${swpct}%)\n"
# shmem = tmpfs/shm files resident in RAM. Invisible to the per-process list
# below — when this is big, the culprit is in the tmpfs section, not a process.
tt+="shmem  ${shmem_g}G   <i>(RAM-backed files — not owned by any process)</i>\n"
tt+="\n<b>Top memory (apps, PSS)</b>\n${top}\n"
if [[ -n "$tmpfs" ]]; then
  tt+="\n<b>tmpfs &gt;0.5G (delete files / end owner to free)</b>\n${tmpfs}\n"
fi
if awk -v s="$swused" -v t="$swtotal" 'BEGIN{exit !(t>0 && s/t>0.9)}'; then
  tt+="\n<span color='#fb4934'><b>⚠ swap ≥90% full — reclaim RAM or the next spike thrashes</b></span>\n"
fi
tt+="\n  L-click  btop"

tt=${tt//\\n/$'\n'}   # literal "\n" from double-quoted strings → real newline
tt=${tt//\\/\\\\}; tt=${tt//\"/\\\"}; tt=${tt//$'\n'/\\n}

printf '{"text":"󰍛 %s/%sG%s","tooltip":"%s","class":"%s","percentage":%s}\n' \
  "$used_g" "$total_g" "$sw_seg" "$tt" "$cls" "$pct"

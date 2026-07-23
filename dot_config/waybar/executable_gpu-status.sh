#!/usr/bin/env bash
# gpu-status.sh — waybar custom/gpu module (RTX 5090, single-GPU).
#
# Pill:    󰢮 <used>/<total>G      VRAM used out of total, in GiB.
# Tooltip: util / temp / power  +  ranked top VRAM consumers with REAL names
#          (resolves the interpreter-name problem: a bare "python" process is
#          relabeled to the script it runs — e.g. hyprwhspr, ComfyUI — so you
#          can tell WHAT is holding VRAM, not just that "Python" is).
# Class:   ok / warn / crit  (by VRAM %) — drives the pill accent in style.css.
#
# One nvidia-smi call for the summary + one for the process table (~35ms each).
# Emitted as waybar JSON (return-type "json", markup pango in the tooltip).
set -u

SMI=$(command -v nvidia-smi) || { printf '{"text":"󰢮 n/a","tooltip":"nvidia-smi not found","class":"crit"}\n'; exit 0; }

# Every data-path nvidia-smi call is time-boxed. During a large VRAM allocation
# (a model loading — e.g. vLLM grabbing 15G) the driver can block for seconds;
# an unbounded call here would wedge the whole waybar module, freezing the value
# AND stalling click dispatch until waybar is killed. waybar runs interval
# scripts as run→wait-for-exit→sleep, so the pill shows a STALE value for as
# long as any call blocks: two calls must fit inside the 5s poll (2×2s=4s),
# and -k hard-kills an nvidia-smi that ignores TERM while stuck in an ioctl.
# (Click actions below exec directly, no smi.)
smi() { timeout -k 1 2 "$SMI" "$@"; }

# --- Handle click actions --------------------------------------------------
case "${1:-}" in
  nvtop)
    exec alacritty --class=com.local.floating-monitor -e nvtop
    ;;
  smi)
    exec alacritty --class=com.local.floating-monitor -e sh -c 'nvidia-smi; echo; read -r _'
    ;;
esac

# --- Summary line ----------------------------------------------------------
# used,total (MiB), util%, tempC, powerW
IFS=',' read -r MEM_USED MEM_TOTAL UTIL TEMP POWER < <(
  smi --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw \
      --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '
)
# Query timed out or errored → keep the module alive with a transient pill
# rather than rendering a bogus "0.0G"; the next poll retries in 5s.
if [[ -z ${MEM_USED:-} ]]; then
  printf '{"text":"󰢮 …","tooltip":"nvidia-smi busy (query timed out)","class":"warn"}\n'
  exit 0
fi
MEM_USED=${MEM_USED:-0}; MEM_TOTAL=${MEM_TOTAL:-1}
UTIL=${UTIL:-0}; TEMP=${TEMP:-0}; POWER=${POWER:-0}

# MiB -> GiB with one decimal, and a percentage for the class threshold.
used_g=$(awk -v m="$MEM_USED" 'BEGIN{printf "%.1f", m/1024}')
total_g=$(awk -v m="$MEM_TOTAL" 'BEGIN{printf "%.0f", m/1024}')
pct=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN{printf "%.0f", (t>0)? u*100/t : 0}')

if   (( pct >= 90 )); then cls="crit"
elif (( pct >= 65 )); then cls="warn"
else                       cls="ok"
fi

# --- Top VRAM consumers, with name resolution ------------------------------
# nvidia-smi gives pid + used_memory; the process_name it reports is the exe
# basename (e.g. "python"), which is useless. We re-resolve each pid to a
# human name from /proc: for interpreters (python/node/…) we dig the script
# out of the cmdline; otherwise we use comm.
resolve_name() {
  local pid=$1 comm cmd base
  comm=$(cat "/proc/$pid/comm" 2>/dev/null) || { echo "pid $pid"; return; }
  case "$comm" in
    python*|node|node*|ruby|perl|java|bash|sh|uv|.venv*)
      # find first cmdline arg that looks like a script path, take its basename
      cmd=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null)
      base=$(printf '%s\n' "$cmd" | grep -m1 -E '\.py$|/(main|app|server|cli)\b|/bin/[a-z]' | head -1)
      if [[ -n "$base" ]]; then
        # prettify a few known homes
        case "$base" in
          */hyprwhspr/*) echo "hyprwhspr (dictation)"; return ;;
          */ComfyUI/*|*comfy*) echo "ComfyUI"; return ;;
          */llama*)     echo "llama.cpp"; return ;;
        esac
        echo "$comm:$(basename "$base")"
      else
        echo "$comm"
      fi
      ;;
    *) echo "$comm" ;;
  esac
}

rows=""
# Parse the full process table (both C compute and G graphics) so browser /
# compositor VRAM shows alongside the dictation model. --query-compute-apps
# alone omits every graphics client. Regex pulls PID + trailing NNNMiB.
while IFS='|' read -r pid used; do
  [[ -z "$pid" ]] && continue
  name=$(resolve_name "$pid")
  ug=$(awk -v m="$used" 'BEGIN{printf "%.1f", m/1024}')
  rows+="$used|$ug|$name|$pid"$'\n'
done < <(smi 2>/dev/null | grep -oE '[0-9]+ +[CG][+CG]* +.* [0-9]+MiB' | \
           sed -E 's/^([0-9]+) +[CG][+CG]* +.* ([0-9]+)MiB/\1|\2/')

# Sort desc by MiB, keep top 6, format aligned lines with pango.
top=$(printf '%s' "$rows" | sort -t'|' -k1 -rn | head -6 | \
  awk -F'|' "NF>=4{printf \"  <span color='#8ec07c'>%5.1fG</span>  %s  <span color='#928374'>(%d)</span>\n\", \$2, \$3, \$4}")
[[ -z "$top" ]] && top="  <span color='#928374'>no compute processes</span>"

# Bar-ish header for the tooltip.
tt="<b>GPU</b>  RTX 5090\n"
tt+="VRAM   <b>${used_g}G</b> / ${total_g}G   (${pct}%)\n"
tt+="Util   ${UTIL}%     Temp  ${TEMP}°C     Power ${POWER}W\n"
tt+="\n<b>Top VRAM</b>\n${top}\n"
tt+="\n  L-click  nvtop      R-click  nvidia-smi"

# Normalize any literal "\n" (from double-quoted header strings) into REAL
# newlines first — otherwise the backslash-doubling below turns them into
# "\\n" and waybar renders a literal \n instead of a line break.
tt=${tt//\\n/$'\n'}
# JSON-escape: backslash first, then double-quotes, then newlines → \n.
tt_json=${tt//\\/\\\\}
tt_json=${tt_json//\"/\\\"}
tt_json=${tt_json//$'\n'/\\n}

printf '{"text":"󰢮 %s/%sG","tooltip":"%s","class":"%s","percentage":%s}\n' \
  "$used_g" "$total_g" "$tt_json" "$cls" "$pct"

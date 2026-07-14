#!/usr/bin/env bash
# llamaswap-status.sh — waybar custom/llamaswap module.
#
# Shows what the local LLM server (llama-swap :9292) currently has resident in
# VRAM, since llama-swap hot-swaps a single model on demand and you otherwise
# can't tell which one is loaded without opening the UI.
#
# Pill:    󰚩 <model>         one model  loaded  (class "loaded")
#          󰚩 <n> models      more than one       (class "loaded")
#          󰚩 loading…        a model is spinning up (class "loading")
#          󰚩 idle            server up, nothing resident (class "idle", dim)
#          (hidden)          server down / unreachable
# Tooltip: resident model(s) with their friendly names, + count of available.
# Click:   opens the llama-swap web UI.
set -u

HOST="http://localhost:9292"
case "${1:-}" in
  ui) exec xdg-open "$HOST/" ;;
esac

# /running is authoritative for what's resident; /v1/models gives names.
running=$(curl -s --max-time 2 "$HOST/running" 2>/dev/null) || running=""
if [[ -z "$running" ]]; then
  # Server unreachable — emit empty text so the pill collapses out of the bar.
  printf '{"text":"","tooltip":"llama-swap unreachable (:9292)","class":"down"}\n'
  exit 0
fi

models=$(curl -s --max-time 2 "$HOST/v1/models" 2>/dev/null)

# Active ids (handle both ["id"] and [{"model":"id","state":...}] shapes).
mapfile -t active < <(printf '%s' "$running" | jq -r '.running[]? | if type=="object" then .model else . end' 2>/dev/null)
# Any model in a transient (spinning-up) state? Anything that isn't the
# terminal "unloaded" and isn't already counted as resident above.
loading=$(printf '%s' "$models" | jq -r '[.data[]? | select((.status.value // "unloaded") != "unloaded")] | length' 2>/dev/null)
loading=${loading:-0}
avail=$(printf '%s' "$models" | jq -r '.data | length' 2>/dev/null)
avail=${avail:-0}

name_of() {  # friendly name for a model id, falling back to the id
  printf '%s' "$models" | jq -r --arg id "$1" '.data[]? | select(.id==$id) | .name // .id' 2>/dev/null | head -1
}

n=${#active[@]}
if (( n >= 1 )); then
  cls="loaded"
  if (( n == 1 )); then
    # Pill uses the short model id (predictable width); the tooltip carries
    # the friendly name.
    text="󰚩 ${active[0]}"
  else
    text="󰚩 $n models"
  fi
  tt="<b>llama-swap</b>  resident\n"
  for id in "${active[@]}"; do
    fn=$(name_of "$id"); tt+="  <span color='#8ec07c'>●</span> ${fn:-$id}\n"
  done
elif (( loading > 0 )); then
  cls="loading"; text="󰚩 loading…"
  tt="<b>llama-swap</b>\n  a model is loading…\n"
else
  cls="idle"; text="󰚩 idle"
  tt="<b>llama-swap</b>  idle\n  no model resident\n"
fi
tt+="\n${avail} models available\n  L-click  open web UI"

tt=${tt//\\n/$'\n'}   # literal "\n" from double-quoted strings → real newline
tt=${tt//\\/\\\\}; tt=${tt//\"/\\\"}; tt=${tt//$'\n'/\\n}
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tt" "$cls"

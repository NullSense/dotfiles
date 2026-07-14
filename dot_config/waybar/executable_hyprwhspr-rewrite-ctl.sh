#!/usr/bin/env bash
# hyprwhspr-rewrite-ctl.sh — enable/disable the dictation REWRITE pass and probe
# its health, for the waybar hyprwhspr pill (middle-click) and the rewrite hook.
#
# Rewrite state is a single toggle file the hook also reads, so "off" means the
# post-transcription hook short-circuits to raw text WITHOUT calling the LLM
# (no wasted latency). Turning off also unloads the model from VRAM immediately
# (llama-swap reloads it on demand when you turn rewrite back on).
set -uo pipefail

STATE_DIR="$HOME/.config/hyprwhspr-ai"
TOGGLE="$STATE_DIR/rewrite-enabled"          # "0" = disabled; anything else / absent = enabled
BACKENDS="$STATE_DIR/backends.json"
mkdir -p "$STATE_DIR"

is_enabled() { [[ "$(cat "$TOGGLE" 2>/dev/null || echo 1)" != "0" ]]; }

# Resolve the active rewrite backend's base_url → "host port modelid kind".
backend_target() {
  python3 - "$BACKENDS" 2>/dev/null <<'PY'
import json, sys, urllib.parse
d = json.load(open(sys.argv[1]))
b = d["backends"][d["active"]]
u = urllib.parse.urlparse(b["base_url"])
print(f"{u.hostname or '127.0.0.1'} {u.port or 80} {b.get('model','')} {b.get('kind','')}")
PY
}

# health → prints: ok | disabled | error:<reason>
health() {
  is_enabled || { echo disabled; return; }
  local host port model kind
  read -r host port model kind < <(backend_target) || { echo "error:backends.json unreadable"; return; }
  [[ -z "$host" ]] && { echo "error:no active rewrite backend"; return; }
  # cheap TCP gate first
  if ! timeout 0.4 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    echo "error:backend $host:$port unreachable"; return
  fi
  # kind "llama-server" (see llm_backend.py docstring) always accepts TCP even
  # when the specific model can't serve — true for BOTH llama-swap (:9292,
  # many models behind one port) and an always-resident vLLM instance (its
  # own dedicated port, e.g. :8001 for the E4B). Either way, presence in the
  # OpenAI-standard /v1/models listing is what "loaded" actually means, so
  # gate on `kind`, not a hardcoded llama-swap port (generalized 2026-07-14
  # when dictation-rewrite moved off llama-swap:9292 onto vLLM:8001).
  if [[ "$kind" == "llama-server" && -n "$model" ]]; then
    if ! curl -s --max-time 1.5 "http://$host:$port/v1/models" | jq -e --arg m "$model" \
         '.data[]?|select(.id==$m)' >/dev/null 2>&1; then
      echo "error:backend $host:$port has no '$model' model"; return
    fi
  fi
  echo ok
}

case "${1:-status}" in
  is-enabled) is_enabled && echo 1 || echo 0 ;;
  health)     health ;;
  on)
    echo 1 >"$TOGGLE"
    notify-send -a hyprwhspr -i audio-input-microphone -u low \
      "Dictation rewrite ON" "Transcripts cleaned by the local model."
    pkill -RTMIN+12 waybar 2>/dev/null || true ;;
  off)
    echo 0 >"$TOGGLE"
    # Free the rewrite model's VRAM now — but only llama-swap (:9292) supports
    # an /unload endpoint; vLLM (e.g. :8001) holds the E4B always-resident with
    # no equivalent call, so this is a no-op there. Either way "off" still stops
    # the LLM call via the toggle file above (the hook short-circuits to raw
    # text) — on vLLM it just won't additionally free VRAM.
    read -r host port _ _ < <(backend_target)
    [[ "$port" == "9292" ]] && curl -s --max-time 3 "http://$host:$port/unload?model=rewrite" >/dev/null 2>&1 || true
    notify-send -a hyprwhspr -i audio-input-microphone -u low \
      "Dictation rewrite OFF" "Raw Parakeet text (vocabulary still applied)."
    pkill -RTMIN+12 waybar 2>/dev/null || true ;;
  toggle) if is_enabled; then "$0" off; else "$0" on; fi ;;
  *)      is_enabled && echo enabled || echo disabled ;;
esac

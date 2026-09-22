#!/usr/bin/env bash
# Waybar module: X-T3 webcam state and GPU screen recording.
# General privacy monitoring is disabled; do not render unchecked mic/camera
# states as idle. X-T3 controls and the GPU recorder indicator remain active.
# Backends: lsusb / systemctl / fuser for X-T3; pgrep for GPU recording.

set -u

CAM_USB_ID="04cb:02dd"   # Fujifilm X-T3
LOOPBACK="/dev/video10"
SERVICE="xt3-webcam.service"

# --- Carbon-inspired palette ------------------------------------------------
COLOR_OFF="#4b5263"      # dim grey — GPU recorder idle
COLOR_XT3_OFF="#5c6370"  # slightly lighter grey — X-T3 unplugged
COLOR_IDLE="#d19a66"     # amber — X-T3 plugged but service stopped
COLOR_READY="#98c379"    # green — X-T3 streaming, awaiting consumer
COLOR_LIVE="#e06c75"     # red — X-T3 in a call
COLOR_LIVE_DIM="#7a3a3e" # dim red — pulse-off frame for LIVE
COLOR_SCREEN="#c678dd"   # purple — screen sharing

# --- Carbon-style MDI Outlined glyphs (Nerd Font) ---------------------------
ICON_XT3_OFF="󰷐"          # camera-off-outline
ICON_XT3_IDLE="󰄀"         # camera-outline
ICON_XT3_READY="󰄀"        # camera-outline (green tint)
ICON_XT3_LIVE="󰻃"         # record-circle-outline
ICON_SCREEN="󰹑"           # monitor-share

# --- X-T3 state probes ------------------------------------------------------
camera_present() { lsusb 2>/dev/null | grep -q "$CAM_USB_ID"; }
service_active() { systemctl --user is-active --quiet "$SERVICE"; }

consumer_present() {
  local pids comm
  pids=$(fuser "$LOOPBACK" 2>/dev/null) || return 1
  for pid in $pids; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    case "$comm" in
      ffmpeg|gphoto2) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

# General privacy-dots polling is disabled: its repeated process scans are
# expensive. Preserve the separate DRM/KMS recorder check on every poll.
screen_active=0
pd_tooltip="Privacy monitoring disabled"
if pgrep -f '^gpu-screen-recorder' >/dev/null 2>&1; then
  screen_active=1
  pd_tooltip+=$'\n'"Screen recording: active (gpu-screen-recorder)"
fi

# --- X-T3 indicator ---------------------------------------------------------
if ! camera_present; then
  xt3_glyph="$ICON_XT3_OFF"; xt3_color="$COLOR_XT3_OFF"
  xt3_class="off"; xt3_tooltip="X-T3 unplugged"
elif ! service_active; then
  xt3_glyph="$ICON_XT3_IDLE"; xt3_color="$COLOR_IDLE"
  xt3_class="idle"; xt3_tooltip="X-T3 plugged · service stopped (click to start)"
elif consumer_present; then
  xt3_glyph="$ICON_XT3_LIVE"
  # Per-glyph blink: alternate color every poll so only the recording dot
  # pulses, never the cell background. EPOCHSECONDS parity → 1Hz at 2s poll.
  if (( ${EPOCHSECONDS:-$(date +%s)} % 2 )); then
    xt3_color="$COLOR_LIVE"
  else
    xt3_color="$COLOR_LIVE_DIM"
  fi
  xt3_class="live"; xt3_tooltip="X-T3 LIVE — call in progress"
else
  xt3_glyph="$ICON_XT3_READY"; xt3_color="$COLOR_READY"
  xt3_class="ready"; xt3_tooltip="X-T3 ready"
fi

# --- Compose: GPU recorder and X-T3 indicators -----------------------------
dot() {
  # $1 = active flag (0/1), $2 = on-color, $3 = glyph
  local color
  if [ "$1" -eq 1 ]; then color="$2"; else color="$COLOR_OFF"; fi
  printf '<span foreground="%s">%s</span>' "$color" "$3"
}

text="$(dot "$screen_active" "$COLOR_SCREEN" "$ICON_SCREEN") "
text+="<span foreground=\"$xt3_color\">$xt3_glyph</span>"

# --- Tooltip: monitoring status and X-T3 state -----------------------------
if [ -n "$pd_tooltip" ]; then
  full_tooltip="$pd_tooltip"$'\n'"X-T3: ${xt3_tooltip#X-T3 }"
else
  full_tooltip="$xt3_tooltip"
fi

# --- JSON output ------------------------------------------------------------
text_json=${text//\"/\\\"}
tooltip_json=${full_tooltip//\"/\\\"}
tooltip_json=${tooltip_json//$'\n'/\\n}

printf '{"text":"%s","tooltip":"%s","class":"%s","alt":"%s"}\n' \
  "$text_json" "$tooltip_json" "$xt3_class" "$xt3_class"

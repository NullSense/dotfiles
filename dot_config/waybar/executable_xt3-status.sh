#!/usr/bin/env bash
# Unified waybar module: privacy state + X-T3 webcam state.
# Visual style: Material Design Outlined glyphs (Nerd Font) chosen to match
# IBM Carbon's clean 2px-stroke aesthetic. Colors via inline pango spans so
# each indicator can carry its own hue while the module itself stays one cell.
#
# Detection backend:
#   - privacy-dots (AUR) — handles pipewire mic/cam/screen via dbus; we parse
#     its JSON and replace its icons with Carbon-style ones.
#   - Direct sysfs/usb checks for X-T3 specifics.

set -u

CAM_USB_ID="04cb:02dd"   # Fujifilm X-T3
LOOPBACK="/dev/video10"
SERVICE="xt3-webcam.service"

# --- Carbon-inspired palette (tweak to taste) -------------------------------
COLOR_OFF="#5c6370"      # neutral grey
COLOR_IDLE="#d19a66"     # amber — needs action
COLOR_READY="#98c379"    # green — armed
COLOR_LIVE="#e06c75"     # red — broadcasting
COLOR_MIC="#56b6c2"      # teal
COLOR_CAM="#e5c07b"      # yellow
COLOR_SCREEN="#c678dd"   # purple

# --- Carbon-style MDI Outlined glyphs (Nerd Font) ---------------------------
ICON_XT3_OFF="󰷐"          # camera-off-outline (mdi)
ICON_XT3_IDLE="󰄀"         # camera-outline (mdi)
ICON_XT3_READY="󰄀"        # camera-outline (mdi) — same shape, green tint
ICON_XT3_LIVE="󰻃"         # record-circle-outline (mdi)
ICON_MIC="󰍮"              # microphone-outline (mdi)
ICON_CAM="󰄁"              # video-outline (mdi)  — generic system-wide cam
ICON_SCREEN="󰹑"           # monitor-share (mdi)

# --- X-T3 state probes ------------------------------------------------------
camera_present() { lsusb 2>/dev/null | grep -q "$CAM_USB_ID"; }
service_active() { systemctl --user is-active --quiet "$SERVICE"; }

consumer_present() {
  local pids comm
  pids=$(fuser "$LOOPBACK" 2>/dev/null) || return 1
  for pid in $pids; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    case "$comm" in
      ffmpeg|gphoto2) ;;   # producer side — ignore
      *) return 0 ;;        # any other holder = consumer
    esac
  done
  return 1
}

# --- Privacy probes via privacy-dots ----------------------------------------
# privacy-dots returns JSON like {"text":"<span ...>󰍬</span> ...","class":"..."}
# We just need to know which categories are active; we render our own glyphs.
mic_active=0
cam_active=0
screen_active=0

if command -v privacy-dots >/dev/null 2>&1; then
  pd_text=$(privacy-dots 2>/dev/null | jq -r '.text // empty' 2>/dev/null || true)
  # Look for the original glyphs that privacy-dots emits in any of its forks.
  # Microphone codepoints in MDI: U+F036C, U+F036D, U+F036E
  # Camera/video codepoints: U+F0567, U+F0568, U+F0100
  # Screen: U+F0E51 or "monitor"
  case "$pd_text" in
    *󰍬*|*󰍮*|*microphone*) mic_active=1 ;;
  esac
  case "$pd_text" in
    *󰕧*|*󰕨*|*󰄀*|*camera*|*video*) cam_active=1 ;;
  esac
  case "$pd_text" in
    *󰹑*|*screen*|*monitor-share*) screen_active=1 ;;
  esac
fi

# --- X-T3 indicator ---------------------------------------------------------
if ! camera_present; then
  xt3_glyph="$ICON_XT3_OFF"; xt3_color="$COLOR_OFF"
  xt3_class="off"; xt3_tooltip="X-T3 unplugged"
elif ! service_active; then
  xt3_glyph="$ICON_XT3_IDLE"; xt3_color="$COLOR_IDLE"
  xt3_class="idle"; xt3_tooltip="X-T3 plugged · service stopped (click to start)"
elif consumer_present; then
  xt3_glyph="$ICON_XT3_LIVE"; xt3_color="$COLOR_LIVE"
  xt3_class="live"; xt3_tooltip="X-T3 LIVE — call in progress"
else
  xt3_glyph="$ICON_XT3_READY"; xt3_color="$COLOR_READY"
  xt3_class="ready"; xt3_tooltip="X-T3 ready"
fi

# --- Compose pango-marked text ----------------------------------------------
parts=()
[ "$mic_active"    -eq 1 ] && parts+=("<span foreground=\"$COLOR_MIC\">$ICON_MIC</span>")
[ "$cam_active"    -eq 1 ] && parts+=("<span foreground=\"$COLOR_CAM\">$ICON_CAM</span>")
[ "$screen_active" -eq 1 ] && parts+=("<span foreground=\"$COLOR_SCREEN\">$ICON_SCREEN</span>")
parts+=("<span foreground=\"$xt3_color\">$xt3_glyph</span>")

# Join with thin spaces (U+2009) for breathing room without being too wide.
text=$(printf '%s ' "${parts[@]}")
text="${text%$' '}"

# Escape quotes for JSON.
text_json=${text//\"/\\\"}
tooltip_json=${xt3_tooltip//\"/\\\"}

printf '{"text":"%s","tooltip":"%s","class":"%s","alt":"%s"}\n' \
  "$text_json" "$tooltip_json" "$xt3_class" "$xt3_class"

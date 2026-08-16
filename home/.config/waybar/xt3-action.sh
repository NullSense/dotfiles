#!/usr/bin/env bash
# Waybar click handler for xt3-webcam.service with notify-send feedback.
#
# Why a wrapper instead of inline systemctl: the service has
# StartLimitBurst=3/StartLimitIntervalSec=60. A bare `systemctl restart` is
# silently refused once the limit is hit, which is exactly what made the
# waybar click feel dead. We `reset-failed` first, then surface the result —
# success, USB-missing, or the journal tail on failure — through notify-send.

set -u

SERVICE="xt3-webcam.service"
CAM_USB_ID="04cb:02dd"
ICON="camera-web"
ACTION="${1:-restart}"

notify() {
  # $1=summary, $2=body, $3=urgency (optional: low|normal|critical)
  local urgency="${3:-normal}"
  notify-send -a "X-T3 webcam" -i "$ICON" -u "$urgency" "$1" "$2"
}

camera_present() { lsusb 2>/dev/null | grep -q "$CAM_USB_ID"; }

journal_tail() {
  journalctl --user -u "$SERVICE" -n 8 --no-pager -o cat 2>/dev/null \
    | grep -v '^$' | tail -4
}

case "$ACTION" in
  start|restart)
    if ! camera_present; then
      notify "X-T3 not detected" \
        "USB ID $CAM_USB_ID is not on the bus. Plug the camera in, power it on, and confirm it is in PC tether mode." \
        normal
      exit 1
    fi
    # Clear start-limit-hit / failed state so restart is actually attempted.
    systemctl --user reset-failed "$SERVICE" 2>/dev/null || true
    if err=$(systemctl --user restart "$SERVICE" 2>&1); then
      # systemd returns immediately; give ExecStartPre + gphoto2 detect a moment.
      sleep 1
      if systemctl --user is-active --quiet "$SERVICE"; then
        notify "X-T3 webcam started" "Streaming to /dev/video10."
      else
        notify "X-T3 service failed to start" \
          "$(journal_tail)" \
          critical
        exit 1
      fi
    else
      notify "systemctl restart failed" "$err" critical
      exit 1
    fi
    ;;
  stop)
    if err=$(systemctl --user stop "$SERVICE" 2>&1); then
      notify "X-T3 webcam stopped" "Loopback /dev/video10 released."
    else
      notify "systemctl stop failed" "$err" critical
      exit 1
    fi
    ;;
  status)
    state=$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)
    body=$(journal_tail)
    notify "X-T3 webcam: ${state:-unknown}" "${body:-No recent journal lines.}"
    ;;
  *)
    notify "Unknown action" "xt3-action.sh: '$ACTION' (expected start|restart|stop|status)" critical
    exit 2
    ;;
esac

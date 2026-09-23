#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
conf="$repo_root/home/.config/hypr/autostart.conf"

# Telegram's exec-once line must:
#  1. Force QT_QPA_PLATFORM=xcb — works around Qt bug QTBUG-137131, where
#     Telegram's QtQuick panels fail native-Wayland EGL context creation on
#     this NVIDIA driver ("QEGLPlatformContext: Failed to create context:
#     3009" / "QRhiGles2: Failed to create context" — journalctl -b).
#  2. Gate launch on org.kde.StatusNotifierWatcher being owned first, same
#     as the Bitwarden line above it — otherwise Telegram loses the tray
#     race on a cold login and QDBusTrayIcon logs "ServiceUnknown: The name
#     is not activatable."
line=$(grep -E "Telegram'\$" "$conf")

case "$line" in
  *QT_QPA_PLATFORM=xcb*) ;;
  *) echo "Telegram autostart line missing QT_QPA_PLATFORM=xcb (QTBUG-137131 workaround)" >&2; exit 1 ;;
esac

case "$line" in
  *StatusNotifierWatcher*) ;;
  *) echo "Telegram autostart line missing the StatusNotifierWatcher-ready gate" >&2; exit 1 ;;
esac

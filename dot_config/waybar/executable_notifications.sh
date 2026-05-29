#!/usr/bin/env bash
# waybar custom/notifications — shows mako state (DND / cinema / normal) plus the
# count of pending notifications. Click-to-toggle DND.
#
# Refresh: SIGRTMIN+11 (fired by the click actions and by hypr-cinema-mode on
# fullscreen enter/exit) for instant state changes, plus a slow interval in
# config.jsonc as a fallback so the pending count stays roughly fresh (mako has
# no "notification changed" signal to subscribe to).
set -uo pipefail

modes="$(makoctl mode 2>/dev/null || true)"
count="$(makoctl list 2>/dev/null | jq -r '(.data[0] | length) // 0' 2>/dev/null)"
[[ "$count" =~ ^[0-9]+$ ]] || count=0

badge=""
[ "$count" -gt 0 ] && badge=" $count"

if printf '%s\n' "$modes" | grep -qx 'do-not-disturb'; then
    icon="󰂛"; class="dnd"; state="Do Not Disturb — notifications hidden"
elif printf '%s\n' "$modes" | grep -qx 'cinema'; then
    icon="󰂚"; class="cinema"; state="Cinema mode (fullscreen) — quiet & brief"
elif [ "$count" -gt 0 ]; then
    icon="󰂚"; class="active"; state="$count pending notification(s)"
else
    icon="󰂜"; class="idle"; state="Notifications on"
fi

tooltip="$state

Left-click:   toggle Do Not Disturb
Right-click:  dismiss all
Middle-click: restore last dismissed"

jq -cn --arg text "${icon}${badge}" --arg class "$class" --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'

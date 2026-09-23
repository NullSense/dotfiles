#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
unit="$repo_root/home/.config/systemd/user/waybar.service"

# omarchy's autostart launches its own waybar unless the waybar-off flag
# exists; the unit must recreate that flag before it starts, or login gets
# two bars.
grep -q '^ExecStartPre=.*touch %h/.local/state/omarchy/toggles/waybar-off' "$unit"

# The flag must be written before the stray-waybar reaper runs.
flag_line=$(grep -n 'toggles/waybar-off' "$unit" | head -1 | cut -d: -f1)
reap_line=$(grep -n '^ExecStartPre=-/usr/bin/pkill' "$unit" | cut -d: -f1)
(( flag_line < reap_line ))

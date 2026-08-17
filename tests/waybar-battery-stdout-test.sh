#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
unit="$repo_root/home/.config/systemd/user/waybar.service"

# Waybar 0.15.0 prints battery status through stdout on every module update.
# Its actionable warnings and errors use stderr and remain journalled.
grep -qx 'StandardOutput=null' "$unit"
grep -qx 'StandardError=journal' "$unit"

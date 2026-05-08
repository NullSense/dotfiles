#!/usr/bin/env bash
# aiquota-cycle — left-click handler for waybar custom/aiquota.
# Cycles display mode: auto -> 5h -> 7d -> auto, persisted to a state file
# the aiquota binary reads on each invocation.
set -eu

dir="${XDG_RUNTIME_DIR:-/tmp}/aiquota"
file="$dir/mode"
mkdir -p "$dir"

cur="auto"
[[ -f "$file" ]] && cur=$(<"$file")

case "$cur" in
  auto) next="5h"   ;;
  5h)   next="7d"   ;;
  7d|*) next="auto" ;;
esac

printf '%s' "$next" > "$file"

# Trigger immediate refresh of the aiquota module (signal: 9 in config.jsonc).
pkill -SIGRTMIN+9 waybar 2>/dev/null || true

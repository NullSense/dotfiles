#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/home/.config/waybar/config.jsonc"
helper="$repo_root/home/bin/hypr-preselect"

block=$(sed -n '/"custom\/preselect"[[:space:]]*:/,/^[[:space:]]*},[[:space:]]*$/p' "$config")

grep -q '"interval"[[:space:]]*:[[:space:]]*"once"' <<<"$block"
if grep -q '"interval"[[:space:]]*:[[:space:]]*0' <<<"$block"; then
    echo "custom/preselect must not use Waybar's tight-loop interval 0" >&2
    exit 1
fi

output=$($helper status)
jq -e 'has("text") and has("tooltip") and has("class")' <<<"$output" >/dev/null

echo "waybar preselect signal-only configuration: ok"

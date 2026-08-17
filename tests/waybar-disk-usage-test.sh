#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/home/.config/waybar/disk-usage.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export XDG_CACHE_HOME="$test_root/cache"
export DISK_USAGE_DU_MARKER="$test_root/du-called"

du() {
  : >"$DISK_USAGE_DU_MARKER"
  command du "$@"
}
export -f du

output=$("$script" pill / root test)
[[ "$output" == *'"text"'* ]]
[[ "$output" == *'not scanned yet'* ]]
[[ ! -e "$DISK_USAGE_DU_MARKER" ]]

"$script" refresh / root
[[ -e "$DISK_USAGE_DU_MARKER" ]]

#!/usr/bin/env bash
set -euo pipefail

config="${1:-$HOME/.config/mpv/mpv.conf}"

assert_setting() {
  local expected="$1"
  local count
  count="$(grep -Ec "^[[:space:]]*${expected//./\\.}[[:space:]]*(#.*)?$" "$config" || true)"
  if [[ "$count" != 1 ]]; then
    printf 'expected exactly one %s setting in %s; found %s\n' "$expected" "$config" "$count" >&2
    exit 1
  fi
}

assert_setting 'demuxer-max-bytes=512MiB'
assert_setting 'demuxer-max-back-bytes=128MiB'

if grep -Eq '^[[:space:]]*demuxer-max-(back-)?bytes=(1|2|3|4|5|6|7|8|9)[0-9]*GiB' "$config"; then
  printf 'mpv cache exceeds the per-process memory budget in %s\n' "$config" >&2
  exit 1
fi

printf 'mpv resource budget: ok\n'

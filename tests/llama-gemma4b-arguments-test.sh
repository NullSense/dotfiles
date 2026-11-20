#!/usr/bin/env bash
# README.md's tests/*.sh interface exercises the launcher's actual argv without loading a model.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
arguments=$(
  SLOTS_DIR="$root/tests"
  MODE=sum
  SPEC=off
  exec() { printf '%s\n' "$@"; }
  source "$root/home/bin/llm-servers/llama-gemma4b"
)
[[ "$arguments" == *$'\n--load-mode\nnone\n'* ]]
[[ "$arguments" != *$'\n--no-mmap\n'* ]]

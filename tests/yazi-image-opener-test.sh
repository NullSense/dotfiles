#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG="$ROOT/home/.config/yazi/yazi.toml"

if ! grep -Fq '{ run = "tev-fit %s", desc = "View in tev (HDR, sized)", orphan = true, for = "unix" },' "$CONFIG"; then
    printf 'FAIL: Yazi image opener must pass selected paths with the current %%s formatter\n' >&2
    exit 1
fi

if grep -Fq 'tev-fit "$@"' "$CONFIG"; then
    printf 'FAIL: deprecated Yazi $@ opener formatter is present\n' >&2
    exit 1
fi

printf 'PASS: yazi image opener\n'

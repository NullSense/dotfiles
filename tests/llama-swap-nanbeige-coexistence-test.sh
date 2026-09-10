#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
llama_swap_config=${LSWAP_CFG:-$repo_root/home/.config/llama-swap/config.yaml}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

raw_nanbeige_coexistence_contract_is_valid() {
    local config=$1

    # jq variables belong to yq, not the shell.
    # shellcheck disable=SC2016
    yq -e '
        (.models."nanbeige4.2-3b".cmd // "") as $command
        | ([ $command | scan("MAXLEN=[^[:space:]\\\"]+") ] == ["MAXLEN=32768"])
          and ([ $command | scan("GPU_UTIL=[^[:space:]\\\"]+") ] == ["GPU_UTIL=0.45"])
          and (.models | has("nanbeige-sift") | not)
          and ([
              .models[]
              | (.aliases // [])[]
              | select(
                  . == "sift-nanbeige"
                  or . == "sift-agent"
                  or . == "sift-decompose"
              )
          ] | length == 0)
          and (.matrix.vars.a == "nanbeige4.2-3b")
          and (.matrix.vars.n == "nemotron-embed-1b")
          and (.matrix.vars.m == "nemotron-rerank-1b")
          and (.matrix.vars.x == "tei-sparse")
          and (.matrix.sets."sift-chat" == "a & n & m & x")
    ' "$config" >/dev/null 2>&1
}

raw_nanbeige_coexistence_contract_is_valid "$llama_swap_config" \
    || fail 'raw Nanbeige and the Sift retrieval trio lack their exact co-residency set'

fixture_dir=$(mktemp -d)
trap 'rm -r -- "$fixture_dir"' EXIT
fixture="$fixture_dir/llama-swap.yaml"

yq -y '.matrix.sets."sift-chat" = "a & n & m"' "$llama_swap_config" >"$fixture"
if raw_nanbeige_coexistence_contract_is_valid "$fixture"; then
    fail 'co-residency contract accepted a set without sparse retrieval'
fi

printf 'PASS: raw Nanbeige and Sift retrieval co-residency contract\n'
